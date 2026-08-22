# LOCAL-001. The object store is RustFS, running standalone

**Status:** accepted · **Scope:** module — `object-storage-rustfs` · **Date:** 2026-08-16

## Context

Something in this repository now needs an S3-compatible endpoint: the telemetry stores are
configured against object storage, because that is the backend their own vendors support, and
no environment here has an S3 endpoint of its own. See
[`observability-storage-grafana-lgtm`](../../observability-storage-grafana-lgtm/README.md) for
what wanted it and why.

This decision is only about *what provides it*. That anything needs object storage at all is the
consuming module's decision, and reversing this one — swapping the implementation — changes
nothing outside this module, because a consumer receives an address, a region and a Secret name.

The constraint is the usual one: two nodes, one operator, weeks of nobody looking. Nothing here
scales out, and a storage system that only makes sense at four nodes with sixteen drives is a
storage system this cluster cannot run.

The candidates, and what each is actually for:

| Candidate | Shape at this size | Why not |
| --- | --- | --- |
| **MinIO** | one pod, one volume | The obvious answer. AGPLv3 since 2021, and the community build has had console and management features removed over time — the product being installed today is not the one most documentation describes |
| **Garage** | one pod, one volume | Designed for exactly this — small self-hosted clusters, stable 1.x. Narrower S3 API surface, and the parts that are missing are the ones a compactor tends to use |
| **SeaweedFS** | master, volume server, filer, S3 gateway | Four components to get one endpoint. The topology is the product |
| **Rook / Ceph** | a cluster of its own | An order of magnitude more machine than exists here |
| **RustFS** | one pod, one volume | Apache-2.0, S3-compatible, small resident footprint, and API-compatible enough to migrate to or from MinIO. **Pre-1.0** |

## Decision

Run **RustFS** from its upstream chart (`charts.rustfs.com`, pinned exactly), in **standalone**
mode:

- `mode.standalone.enabled` — one pod, one PVC. The chart's default is `mode.distributed`, four
  replicas across sixteen volumes; erasure coding, pools and rebalancing all belong to that shape
  and are left untouched
- `secret.existingSecret` — one access key pair, read from a Secret this module renders empty and
  an operator fills, so no credential is rendered into anything
  ([ADR 007](../../../adr/007-modules-receive-credentials.md),
  [ADR 022](../../../adr/022-secrets-are-rendered-empty.md))
- `config.rustfs.obs_log_directory` blanked — logs to stdout rather than to a second PVC
- `config.rustfs.obs_endpoint` disabled — RustFS emits its own telemetry over OTLP, and the
  collector that would receive it stores its data here
- `ingress.enabled` and `gatewayApi.enabled` both off; the route, when one is asked for, comes
  from `extraManifests`

Native case per [ADR 010](../../../adr/010-resources-delivered-via-chart.md): the upstream chart
renders everything it needs, including the route. Nothing is authored here and nothing is wrapped.

**Both of the chart's own exposure switches are off deliberately, and the chart is why they had
to be looked at.** `ingress.enabled` defaults to *true*; and what `gatewayApi` renders is a route
to the admin console on port 9001 — its backend port is hardcoded to `service.console.port` —
alongside a hostname-less HTTP-to-HTTPS redirect route and a Traefik-specific sticky-session
object, and it creates a `Gateway` of its own when not given one. So the chart cannot expose the
right port and can expose the wrong one by default. `extraManifests` renders the route this module
actually wants, through the same chart, with no wrapper and no second pinned version.

## Rationale

- **One pod and one volume is the only shape that belongs here.** Every candidate above can be
  made to run at this size; the difference is whether that is a supported configuration or a
  configuration the project tolerates. RustFS names standalone as a mode and the chart ships a
  switch for it.
- **Apache-2.0 is what removed MinIO from the list**, more than any technical property. MinIO is
  more mature and would be the safer choice on every axis except the one where a licence change
  and a shrinking community build have already happened once. Being wrong about that is
  reversible; this module publishes an address and a Secret name, and nothing about a consumer
  changes when the pod behind them does.
- **Garage was the close second and lost on API surface, not on judgement.** It is the more
  conservative pick for a homelab and stable where RustFS is not. The deciding factor is that
  Mimir's compactor and store-gateway exercise more of the S3 API than an ordinary client does,
  and Garage's gaps are in exactly that region. If RustFS's pre-1.0 status turns into a problem,
  Garage is where to look first, and the work is a values change plus a data copy.
- **The console earns its pod.** Being able to list a bucket and confirm that objects exist is
  how the "nothing was stored and nobody noticed" failure gets diagnosed, and this module's
  buckets are created by hand, which makes that failure likely rather than theoretical.

## Consequences

- **Pre-1.0 software holds every stored signal.** The chart pins appVersion `1.0.0-rc.3`, which is
  the newest upstream publishes. On-disk format stability between pre-1.0 releases is
  undocumented. Assume at least one upgrade requires emptying the buckets, and read the release
  notes before moving the pin.

  *Revised 2026-08-23.* This originally read that the chart pinned `1.0.0-beta.12` while upstream
  had reached `1.0.0-rc.2`, so the chart trailed the product by two releases — which was true when
  written and was half the reason to stay put. Upstream has since published charts for every
  release candidate and renumbered them: the chart carried its own `0.x` sequence through the
  betas and now uses the same string as the appVersion. Chart and product no longer diverge, the
  gap that argument rested on is closed, and the pin moved to `1.0.0-rc.3` with it. Rendering the
  new chart against this module's values produced output identical to the old one but for the
  version labels and the image tag, so nothing in the values schema moved underneath it.
- **A pinned chart is a pinned appVersion**, and overriding the image tag to get a newer server
  is not on offer here. The chart's values are written against the version it ships; separating
  the two is how a values schema drifts out from under a module silently
  ([ADR 010](../../../adr/010-resources-delivered-via-chart.md)).
- **Every signal now fails together.** Metrics, logs and traces had a volume each and failed
  independently. One process, one volume, one node — the blast radius is the whole of
  observability, and the recovery is restoring one thing rather than three.
- **The node pin moved rather than disappeared.** A `local-path` PVC binds to the node the pod
  first ran on, exactly as each store's own PVC did. Object storage did not decouple data from a
  machine at one replica, and nothing in this repository does.
- **The S3 API is a read-write surface**, unlike the OTLP endpoint it sits behind. Routing it
  makes stored telemetry retrievable and deletable by whatever reaches the listener, so the
  write-only argument that made the ingest endpoint defensible does not carry over. The route
  exists because an operator has to reach a bucket without a port-forward; which listener it
  attaches to is the only thing deciding who else can.
- **Reversible, at the cost of a copy.** Swapping the implementation is a values change plus
  `aws s3 sync` between two endpoints, because every consumer is configured with an address and
  a key rather than with anything RustFS-specific. That is the property this whole module exists
  to preserve, and it is worth not spending.
