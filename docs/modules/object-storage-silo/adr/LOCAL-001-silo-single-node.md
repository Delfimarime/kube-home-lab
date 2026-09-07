# LOCAL-001. The object store is Silo, single-node and single-drive

**Status:** accepted · **Scope:** module — `object-storage-silo` · **Date:** 2026-09-07

**The object store is `pgsty/silo` — the maintained community fork of MinIO — running one pod
against one drive, from a chart this repository authors.**

## Decision

Run **Silo** single-node, single-drive: one StatefulSet, one replica, one PVC, from
`helm/silo-standalone/` — a chart authored here, the custom case of
[ADR 010](../../../adr/010-resources-delivered-via-chart.md) placed per
[ADR 027](../../../adr/027-charts-are-first-class-artifacts.md).

- **The image is the pin**, `pgsty/silo:RELEASE.2026-09-03T13-18-01Z-distroless` — the variant
  documented as running under any `--user`, which is what an unprivileged pod needs — carried as
  `silo.image_tag`. There is no upstream chart whose version could be pinned instead.
- **One drive, so no erasure coding**, no pools, no rebalancing and no site replication. Silo
  runs unencoded against a single path, which is the mode this cluster has hardware for.
- **`fullnameOverride: s3-svc`**, so every object this chart renders — the StatefulSet, the
  Service, the claim — carries that one name, and the published `endpoint` is byte-identical to
  the string every consumer is already configured with. The chart appends nothing to it, which
  is the difference from the shape that produced the suffix in the first place.
- **The root credential comes from a Secret this module renders empty and an operator fills**
  ([ADR 007](../../../adr/007-modules-receive-credentials.md),
  [ADR 022](../../../adr/022-secrets-are-rendered-empty.md)), under the product-neutral keys
  `ACCESS_KEY` and `SECRET_KEY`. The chart reads them with `secretKeyRef` and maps them onto the
  process's `MINIO_ROOT_USER` and `MINIO_ROOT_PASSWORD`, so the Secret's schema names no product
  and survives the next implementation change.
- **Two ports on one Service**: 9000 for the S3 API, 9001 for the console. Neither is routed
  unless it is given a hostname.
- **Resource limits and the runtime settings that make them safe are part of the chart, not a
  tuning exercise**: requests `cpu 200m` / `memory 512Mi`, limits `cpu 2000m` / `memory 2Gi`, and
  `GOMEMLIMIT=1700MiB`, `GOMAXPROCS=2`, `MINIO_API_REQUESTS_MAX=128` on the container. **The chart
  refuses to render a memory limit with no `GOMEMLIMIT`.**

## Context

This module's contract does not move. Something here needs an S3-compatible endpoint because the
telemetry stores are configured against object storage — see
[`observability-storage-grafana-lgtm`](../../observability-storage-grafana-lgtm/README.md) — and
a consumer receives an address, a region and a Secret name. This decision is only about what
serves them.

**What changed is the ground under the previous answer.** That decision picked RustFS over MinIO,
and said so plainly: Apache-2.0 was what removed MinIO from the list, more than any technical
property, because a licence change and a shrinking community build had already happened once.
Both halves of that reading have since resolved. `minio/minio` was marked no longer maintained in
February 2026 and **archived on 25 April 2026**; MinIO Inc. moved its attention to commercial
products, and the community build had by then lost most of its web console. The thing that was
being avoided arrived. RustFS, meanwhile, is still the pre-1.0 dependency it was chosen as, and
the module's data is every stored signal.

An archived repository is not the end of a codebase that a decade of clients are written against,
and the candidates are now shaped by that:

| Candidate | Shape here | Standing |
| --- | --- | --- |
| **`pgsty/silo`** | one pod, one drive | The fork that kept a release line: multi-arch images and a `-distroless` variant, a stated one-to-two-month cadence, ~2.7k stars, ~40 contributors, **the full web console restored**, and CI that enforces the S3 API, the `MINIO_*` variables, the `x-minio-*` headers, the `/minio/*` routes and the on-disk format including `.minio.sys`. **AGPL-3.0-or-later** |
| **`minio/minio`** | one pod, one drive | Archived. No further releases, and the console was already gone |
| **`openminio/openminio`** | one pod, one drive | A bare fork — 16 stars, 3 forks, **zero releases**, no published image, no chart. The maturity on offer is the MinIO codebase's, not this repository's |
| **RustFS** | one pod, one volume | The incumbent, still pre-1.0, with undocumented on-disk stability between releases |
| **Garage** | one pod, one volume | Still the conservative pick, still narrower across exactly the S3 surface a compactor exercises |

**Silo publishes no chart of its own.** Its documentation directs you at the MinIO Operator's
Tenant chart with an image override.

## Rationale

- **Compatibility is the whole migration.** Every consumer is configured with a host, a port, a
  region and an access key, and Silo's CI enforces that those keep meaning what they meant: the
  API, the environment variables, the headers, the routes, the on-disk layout. Changing the store
  is then a change of image and a copy of the data, not a change of contract — which is the
  property [REQ-09](../../../requirements.md) asks for and the reason this module exists.
- **A maintained release line is the thing neither alternative offers.** RustFS's risk was pre-1.0
  format churn under every stored signal; MinIO's is that there will be no next release at all.
  Silo's cadence and contributor count are what is actually being bought here, and they are also
  the thing to watch — see Consequences.
- **The console earns its pod, and this fork is the one that has it.** The buckets here are
  created by hand, so "nothing was stored and nobody noticed" is a likely failure rather than a
  theoretical one, and listing a bucket is how it gets diagnosed. The community MinIO build had
  had that removed; Silo restored it.
- **One replica is the honest shape, and the arithmetic is why.** MinIO caps erasure-set parity at
  half the set. Two nodes with two drives each is a four-drive set, so the most parity available
  is EC:2 — read quorum 2, but parity equal to half the set makes write quorum K+1, which is 3.
  Lose one node and two drives remain: **reads survive and writes fail.** Node-failure-tolerant
  writes need four or more nodes, or two independent deployments with asynchronous site
  replication between them. This cluster is one node, or a couple. A replicated topology here
  would buy a degraded read path in exchange for the operational weight of a distributed store,
  and [§1.4](../../../../CONSTITUTION.md#1-boundaries) is the rule that says not to.
- **A chart here beats an Operator and an override.** The documented path is the MinIO Operator's
  Tenant chart — CRDs and a controller, to run one pod — with the image swapped for Silo's. That
  second half is precisely what [§2.5](../../../../CONSTITUTION.md#2-modules) exists to prevent:
  a chart's values are written against the version it ships, and overriding the image separates
  the two so the schema can drift out from under this module silently. A small chart owned here is
  the cheaper bill, and the topology is what keeps it small.
- **The limits are a correctness argument, not a tuning one.** MinIO sizes its own request
  concurrency from the RAM it *observes*, roughly `(0.75 × total RAM) / 2MiB` — under a cgroup
  limit that is the node's memory and not the container's, so the process budgets for a machine it
  does not have. The Go runtime does the same thing one layer down: with no `GOMEMLIMIT` it grows
  the heap past the container limit until the kernel kills it, and an OOM kill of this pod is every
  signal at once. `GOMEMLIMIT` at ≈83% of the limit gives the collector headroom to act before the
  ceiling; `GOMAXPROCS` matches the CPU limit so the scheduler is not sized for cores the pod
  cannot use; `MINIO_API_REQUESTS_MAX` replaces the guess the process would otherwise make. A
  memory limit without the first of these is a slow crash loop that looks like a storage bug, so
  the chart refuses to render it.

## Alternatives

- **Stay on RustFS.** Costs nothing today and leaves every stored signal behind pre-1.0 software
  with undocumented format stability between releases. The move is a copy either way; doing it
  while the store holds days of telemetry rather than months is the cheaper moment.
- **`minio/minio` itself, pinned at its last release.** Archived on 25 April 2026, so the pin is
  permanent and no security fix is coming. It also arrives without the console.
- **`openminio/openminio`.** The other fork. Zero releases, no published images and no chart means
  this repository would be building and hosting an image before it could install anything, and the
  maturity people credit the name with belongs to the upstream codebase rather than to that
  repository's ability to maintain it.
- **The MinIO Operator's Tenant chart with the image overridden**, which is what Silo's own
  documentation recommends. It installs CRDs and a controller in order to run a single pod, and it
  asks this repository to run somebody else's pinned chart against an image it was not released
  with. Two costs, for a topology this cluster will never use.
- **Garage.** The close second last time and still credible: stable 1.x, designed for exactly this
  size, AGPL-free. It loses on S3 surface — its gaps sit where Mimir's compactor and store-gateway
  work — and, now, on migration: Silo keeps the on-disk format and the API a MinIO client already
  speaks, and Garage is a re-test of every consumer.
- **Two nodes, four drives, erasure coding.** See the arithmetic above: it buys reads through a
  node failure and not writes, which for an ingest path is the half that does not help.
- **A PVC per store and no object store at all.** What this repository did before
  [observability-storage LOCAL-006](../../observability-storage-grafana-lgtm/adr/LOCAL-006-stores-keep-their-data-in-an-object-store.md).
  It removes a component and puts each store's durability back on one node's disk.

## Consequences

- **The licence that removed MinIO from the list is now the licence being installed.** Silo is
  AGPL-3.0-or-later, and the decision this replaces named Apache-2.0 as its deciding factor. That
  factor is being reversed deliberately, not quietly dropped: AGPLv3 binds a distributor, and this
  is a private cluster that distributes nothing, so the clause that made the licence a live
  question for a product company is inert here. What the earlier reading was really about was
  **the direction of a company**, which the archive has now settled — and a community fork is not
  the company. If anything here ever became a hosted service for somebody else, this is the
  sentence to come back to.
- **The pin is an image tag, not a chart version**, because the chart is this repository's. That
  is a second version to move by hand and a second thing to get wrong: the chart's `Chart.yaml`
  version tracks its values schema and `silo.image_tag` tracks the product, and nothing checks
  that the values still suit the image. Read Silo's release notes before moving the tag.
- **A chart to maintain**, against this repository's stated preference for upstream charts with
  upstream values. It is small — a StatefulSet, a Service, a placeholder-free Secret reference, a
  route — only because the topology is.
- **Every signal still fails together, and now nothing survives a node loss at all.** One pod, one
  volume, one node. The erasure arithmetic above says a two-node build would have kept reads; this
  build keeps nothing, which is the same position RustFS left the cluster in and is stated here so
  it is not mistaken for an improvement bought by the migration.
- **The migration costs a copy and a retyped credential, and no consumer change.** `aws s3 sync`
  between the two endpoints while both run; the Service name is `s3-svc` on both sides, so
  `endpoint` never changes. What an operator does have to redo is the Secret: the keys are
  `ACCESS_KEY`/`SECRET_KEY` now rather than `RUSTFS_*`, because the chart reads them by reference
  instead of mounting the whole Secret as environment. **Silo will not start against an empty root
  credential**, so a fresh environment crash-loops until that patch lands.
- **`s3-svc` is now a name this repository chose.** It was an upstream chart's `-svc` suffix
  before; keeping it is what makes the endpoint string stable across the swap, and it means the
  next implementation has to keep it too or every consumer is reconfigured.
- **The PVC now outlives the module.** A `volumeClaimTemplates` claim is not garbage-collected
  with its StatefulSet, so pruning the Application no longer deletes the data — a change from the
  Deployment-plus-PVC shape, and one that turns "removing the module block loses every signal"
  into "removing the module block leaves an orphaned claim somebody has to find".
- **Revisit if Silo's cadence lapses.** Two release cycles missed, or the compatibility CI going
  quiet, and this is a fork with the same problem as its parent. The exit is the same as the
  entrance — an image change and a copy — and Garage is where to look next.
