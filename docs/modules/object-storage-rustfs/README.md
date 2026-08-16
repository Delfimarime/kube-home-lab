# Module: object-storage-rustfs

**Status:** draft ·
**Satisfies:** [REQ-05, REQ-09, REQ-10](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-rustfs-standalone.md),
[ADR 005](../../adr/005-modules-are-applicationsets.md),
[ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 008](../../adr/008-postgresql-is-external.md),
[ADR 010](../../adr/010-resources-delivered-via-chart.md),
[ADR 014](../../adr/014-exposed-does-not-mean-authorized.md),
[ADR 016](../../adr/016-metrics-is-the-fourth-input.md),
[ADR 022](../../adr/022-secrets-are-rendered-empty.md)

## Intent

One S3-compatible endpoint in the cluster, for workloads whose supported storage backend is an
object store rather than a volume.

**This module satisfies no requirement on its own, and that is worth stating plainly.** Nobody
here wants object storage; what they want is for the telemetry stores to run in a shape their
own vendors support, and every one of those shapes is written against S3. The module exists as
an enabler, and its justification is a decision rather than a requirement — the same way
cert-manager's chart choices are justified. If the thing consuming it goes away, so does this.

It publishes an address, a region and the name of a Secret, and knows nothing about who uses
them ([ADR 007](../../adr/007-modules-receive-credentials.md)). It does not know that its
buckets hold telemetry, and nothing here should ever teach it.

**Why this is provisioned when PostgreSQL is not.** [ADR 008](../../adr/008-postgresql-is-external.md)
holds that a database is a thing an environment already has — reachable, administered, with a
lifecycle older than this repository. An S3 endpoint is not: no environment here has one, and
none would grow one for its own sake. The line is what an environment plausibly already runs,
not the size of the thing, and object storage falls on the other side of it.

Scoped to one environment like every module: each cluster that ships it gets its own endpoint
and its own disk ([ADR 011](../../adr/011-environments-are-clusters.md)). Nothing is shared, and
nothing replicates anywhere.

## Provisions

One Argo CD `ApplicationSet` ([ADR 005](../../adr/005-modules-are-applicationsets.md)), whose
`List` generator produces one Application — one static entry, as that ADR requires even at one:

| Wave | Application | Chart | Condition |
| --- | --- | --- | --- |
| 0 | `rustfs-credentials` | `secret-template` — imported, see [ADR 022](../../adr/022-secrets-are-rendered-empty.md) | `secret_name` is null |
| 1 | `rustfs` | `rustfs` (charts.rustfs.com) | always |

Native case per [ADR 010](../../adr/010-resources-delivered-via-chart.md) for the workload
itself: the upstream chart renders everything, including the route when one is asked for.
Nothing is wrapped and no chart is authored here.

**The waves are load-bearing.** RustFS refuses to start without an access key, so the Secret has
to exist first — empty is enough for the pod to be scheduled, and filling it is the operator's
step below. Where `secret_name` names an existing Secret there is no first Application at all:
this module reads that object and never owns it.

**Standalone, which is one Deployment of one replica and one volume.** `mode.standalone.enabled`
— the chart's default is `mode.distributed`, four replicas across sixteen PVCs, which is a shape
this cluster will never have ([LOCAL-001](adr/LOCAL-001-rustfs-standalone.md)). Erasure coding,
pools and rebalancing all belong to that other shape and are left alone. Both switches are set
rather than relying on one to imply the other.

**Everything is renamed to `s3`** through `fullnameOverride`, so the address consumers are
configured with names the protocol rather than the product: the Service is `s3-svc`, the volume
`s3-data`. Swapping the implementation is then a values change that no consumer notices, which is
the property [REQ-09](../../requirements.md) asks for and the whole reason this module publishes
an address at all.

**One volume, not two.** `config.rustfs.obs_log_directory` is blanked, which is the chart's
switch between writing its logs to a second PVC and writing them to stdout. Stdout is what a log
collector reads, so blanking it both removes a volume and makes the workload's logs visible to
whatever tails containers — a file on a PVC inside a pod is a log nobody will ever see.

**The console stays on and stays unrouted.** `config.rustfs.console_enable` is the chart's
default and is left there: it is how a person lists a bucket or checks that a write landed, and
`kubectl port-forward` is the whole access path. Turning it off would save nothing measurable and
remove the only interactive way to answer "is anything actually in there".

**Nothing here creates a bucket.** The chart provisions none, and no consumer creates its own —
see [Prerequisites](#prerequisites). This is the module's sharpest edge and it is not hidden in
an open item.

**Its own telemetry is off.** RustFS exposes no `/metrics` endpoint and the chart renders no
`ServiceMonitor`; it emits over OTLP instead, through `config.rustfs.obs_endpoint`. So this
module takes no `metrics` input at all — [ADR 016](../../adr/016-metrics-is-the-fourth-input.md)
is explicit that a module with no metrics endpoint does not take one — and the exporter is left
disabled. **It cannot be wired to the collector that stores telemetry in these buckets**: that
module consumes this one's address, so pointing this one back at its receiver is a cycle
OpenTofu refuses at plan time, not a configuration choice. An environment that wants RustFS's
own telemetry sets the endpoint as a literal string, accepting that it is telemetry about the
store being written into the store.

### Exposure

**Nothing is exposed, and there is no input that would expose it.** The S3 endpoint is consumed
from inside the cluster, over cluster DNS, on port 9000. This module takes no `gateway` and
publishes no external URL.

That is a narrower position than an earlier draft of this spec took, and the chart is why. Two
of its values would emit something:

- **`ingress.enabled` defaults to `true`**, with an nginx class. It is switched off explicitly,
  because a default that exposes a store would be [REQ-06](../../requirements.md) failing by
  omission rather than by decision.
- **`gatewayApi` renders a route to the *console* on port 9001** — not the S3 API — plus a
  second HTTP-to-HTTPS redirect route and a Traefik-specific sticky-session object. An admin UI
  over every stored object is the one thing this module must never expose, so the switch is off
  and none of it is used.

Routing the S3 API itself would therefore need a wrapper chart rendering an `HTTPRoute` at port
9000, and it is deliberately not built. That surface is read *and* write over every stored
signal, so unlike the OTLP receiver there is no argument that it is write-only, and
[ADR 014](../../adr/014-exposed-does-not-mean-authorized.md)'s "the listener decides" would be
carrying far more weight than it does anywhere else here. If an environment ever needs it, the
wrapper is the honest way to add it and this paragraph is the argument to re-read first.

### Credentials

**One access key pair, by reference** ([ADR 007](../../adr/007-modules-receive-credentials.md),
[REQ-05](../../requirements.md)). The chart's `secret.existingSecret` names a Secret it reads
rather than a value it renders, so no credential reaches a values.yaml, a rendered `Application`
spec or state. The chart also refuses to render if given inline keys that are empty or its own
well-known defaults, which is one fewer failure mode to document — and is why the placeholder is
this repository's chart rather than the upstream one's Secret.

**The pair is shared, and the buckets are what keep the stores apart.** Every consumer
authenticates as the same identity; what stops one store touching another's data is that each
writes to its own bucket and is configured with no other. That is a convention this module
enforces nothing about: the credential can reach every bucket, so a misconfigured bucket name is
a store writing into a neighbour's data rather than an access denial. Per-bucket keys with a
policy each are what RustFS offers and this module does not use — one operator, one cluster and
no adversary that partitioning would stop. Revisit it the day the endpoint is routed.

## Prerequisites

**The access key, filled in.** With `secret_name` left null this module renders the Secret
itself — empty, with `access_key` and `secret_key` present — and its contents are ignored on
every sync ([ADR 022](../../adr/022-secrets-are-rendered-empty.md)), so what an environment owes
is a value and not an object. Naming an existing Secret instead is the other half of that
decision: this module then only reads it, and creating it is somebody else's job.

```sh
kubectl patch secret object-storage-credentials -n object-storage \
  --type merge -p "$(jq -n --arg a "$(printf %s "$ACCESS_KEY" | base64)" \
                          --arg s "$(printf %s "$SECRET_KEY" | base64)" \
                          '{data:{RUSTFS_ACCESS_KEY:$a,RUSTFS_SECRET_KEY:$s}}')"

kubectl rollout restart deployment/s3 -n object-storage
```

**The key names are environment variable names, and that is not cosmetic.** The chart mounts the
whole Secret with `envFrom`, so every key becomes a variable in the container — which means a
Secret holding the right values under any other names produces a process with no credential at
all. The placeholder carries exactly these two for that reason.

The restart is not optional either: the values are read at start, so a pod that came up against
the empty Secret keeps the empty values until it is replaced.

**The same value, again, wherever a consumer runs.** A Secret is namespaced, so each consuming
module renders its own placeholder in its own namespace and an operator fills that one too —
**under whatever key names that workload reads, which are not these two.** Same secret, different
keys, because the keys belong to whoever consumes them. Two copies of one credential, and nothing
detects them disagreeing: the symptom is a store that starts cleanly and gets `403` on every
write.

**Every bucket a consumer names, created by hand once RustFS is running.** Nothing creates them:
not the chart, and not Mimir, Loki or Tempo, each of which requires its bucket to already exist
and reports its absence as an ingest error rather than a startup one. Using any S3 client
against the endpoint, port-forwarded or from inside the cluster:

```sh
kubectl port-forward -n object-storage svc/s3-svc 9000:9000
aws --endpoint-url http://localhost:9000 s3 mb s3://mimir
aws --endpoint-url http://localhost:9000 s3 mb s3://loki
aws --endpoint-url http://localhost:9000 s3 mb s3://tempo
```

The names are whatever the consuming module was configured with; this module has no bucket input
and no opinion, because an input naming something nothing creates would be a value with no
reader.

**A `StorageClass` that binds a volume**, `local-path` on k3s by default. Its
`WaitForFirstConsumer` binding pins the volume — and therefore this pod, and therefore every
store's data — to whichever node it first landed on.

## Inputs

```hcl
namespace = "object-storage"

secret_name = null                   # null: rendered here, empty, keys in place
                                     # set:  an existing Secret this module only reads

storage = {
  size          = "20Gi"
  class         = "local-path"
  node_selector = null                # e.g. { "kubernetes.io/hostname" = "k3s-01" }
}

region = "us-east-1"                  # what consumers must be configured with
```

Plus the chart version, and where Argo CD reads the placeholder chart from.

**This module takes none of the three shared contracts, and that is unusual enough to say.**
`gateway` is absent because nothing here is ever routed — see [Exposure](#exposure). `database`
and `oidc` would be meaningless: this is the thing other workloads store state *in*, and its one
credential is an access key rather than a person. `metrics` is absent too, because the workload
exposes no `/metrics` endpoint for a `ServiceMonitor` to name.

**`region` is an input rather than a constant** because S3 clients send it and compare it, and
because an environment migrating buckets in from somewhere else has a name to match. It is
otherwise arbitrary — there are no regions here.

**`storage.size` has no sensible default and 20Gi is a guess.** It is the whole disk budget for
every signal this cluster stores, and the retention set per tenant in the consuming module is
what has to fit inside it. Those two numbers are set in different files by different reasoning
and nothing compares them.

**`storage.node_selector` names the machine that holds the data.** Not an anti-affinity or a
tolerance: one pod, one volume, one node, chosen deliberately rather than by whichever node the
scheduler picked on the day.

## Outputs

| Output | Used by |
| --- | --- |
| `endpoint` | any workload configured with an S3 backend — `s3-svc.<namespace>.svc.cluster.local:9000` |
| `region` | the same, as the region its client sends |
| `credentials_secret_name` | an operator, to know what to fill in — the name given, or the one rendered |

**No output names RustFS, and no output's *value* does either** — `fullnameOverride` is what
buys that, and it is the reason it is set. A consumer wired to these three is configured for S3
and would not notice the implementation changing underneath it
([REQ-09](../../requirements.md)).

**There is no external URL** because there is no route — see [Exposure](#exposure).

**`endpoint` is a host and port, not a URL**, because that is the shape every S3 client
configuration field takes. Whether it is reached over TLS is a separate field in each of those
clients, and in-cluster it is not: plain HTTP inside the cluster, on the same reasoning that the
OTLP receiver's in-cluster address is plain.

**There is no bucket output**, because there is no bucket input. What buckets exist is a fact
about what somebody created by hand, and publishing a list this module cannot verify would be
publishing a claim rather than an address.

## Acceptance criteria

`OBJ-04` and `OBJ-05` are retired and their numbers are not reused. Both were written against a
`gateway` input that no longer exists — one asserted that nothing was exposed *by default*, the
other that the console was never routed — and `OBJ-12` asserts something stronger than either.

```gherkin
Feature: One S3-compatible endpoint, per environment

  @cluster
  Scenario: [OBJ-01] One pod, one volume
    Given the module is applied
    When pods and PersistentVolumeClaims in the namespace are listed
    Then exactly one RustFS pod exists
     And exactly one PersistentVolumeClaim exists
     And no logs volume was created

  @cluster
  Scenario: [OBJ-02] The credential is never rendered
    Given the module is applied
    When the Application specs are read from the API server
    Then no access key or secret key appears in any rendered Helm values
     And the pod reads them from the named Secret

  @cluster
  Scenario: [OBJ-10] The placeholder arrives with its keys, and is never overwritten
    Given secret_name is null
    When the module is applied
    Then a Secret exists carrying access_key and secret_key, both empty
     And after an operator fills them in and anything is synced again
     Then the values are still the operator's

  @cluster
  Scenario: [OBJ-11] An existing Secret is read and never owned
    Given secret_name names a Secret this module did not create
    When the module is applied
    Then no placeholder Application exists
     And that Secret carries no Argo CD owner reference
     And destroying the module leaves it in place

  @plan
  Scenario: [OBJ-03] The published address names no product
    Given the module is applied
    When endpoint is read
    Then it is a host and port, and carries no scheme

  @cluster
  Scenario: [OBJ-12] Nothing is reachable from outside the cluster, in any configuration
    Given the module is applied
    When HTTPRoutes and Ingresses in the namespace are listed
    Then none exist
     And no input of this module would create one

  @cluster
  Scenario: [OBJ-06] The store's own telemetry does not depend on itself
    Given the module is applied
    When the RustFS configuration is read
    Then its OTLP exporter is disabled
     And no ServiceMonitor exists in the namespace

  @cluster
  Scenario: [OBJ-07] Its logs are readable by a collector
    Given the module is applied
    When the RustFS container's stdout is read
    Then its log lines are there

  @cluster
  Scenario: [OBJ-08] Placement is chosen, not inherited
    Given storage.node_selector names a node
    When the module is applied
    Then the RustFS pod runs on that node

  @cluster
  Scenario: [OBJ-09] A missing bucket is the consumer's error, not a broken store
    Given the module is applied and no bucket has been created
    When a consumer writes to a bucket that does not exist
    Then RustFS is healthy and serving
     And the write fails with a no-such-bucket error
```

## Open items

- **Nothing creates the buckets, and nothing notices they are missing.** RustFS starts healthy
  with no buckets at all, so the failure surfaces as an ingest error in whatever consumes it,
  hours later and in another module's logs. A rebuild that recreates every Application correctly
  still ends with a cluster that stores nothing. This is the single most likely way a fresh
  environment ends up quietly broken.
- **The version is `1.0.0-beta.12`.** Every store's data sits behind pre-1.0 software, and the
  format compatibility it offers between betas is undocumented. Read the release notes before
  bumping the pin, and expect the upgrade path to be "empty the buckets" at least once.
- **One pod is a single point of failure for every signal at once.** Metrics, logs and traces
  previously failed independently, each with its own volume; they now share a process. This is a
  known cost of the decision that put them here and not a defect to fix by adding replicas —
  replicas are the shape this cluster does not have.
- **Nothing sequences this module against its consumers.** A module declares what it needs and
  never when it is satisfied, so Argo CD may sync Mimir before RustFS is serving. The result is a
  crash loop that resolves itself, which is acceptable, and which looks identical to a
  misconfigured endpoint, which is not.
- **Pruning deletes the volume that holds everything.** The Application syncs with `prune` and
  `self_heal` like every other one here, so removing the module block removes the PVC and with it
  every stored signal — one delete rather than three. Decide whether the PVC carries a retain
  annotation before anyone reorganises the root module.
- **The disk has one number and three tenants' retention pointing at it.** `storage.size` is set
  here; what is allowed to fill it is set per tenant in the consuming module. Nothing compares
  them, and the failure is writes rejected across every signal at once.
- **One access key for every consumer, so the bucket boundary is a convention.** A store
  configured with the wrong bucket name reaches it, and a compromised one reaches all of them.
  Per-bucket keys with a policy each are what RustFS offers and this module does not use; the day
  the endpoint is routed, that trade should be re-made.
- **Pruning deletes the credential along with the store, when this module rendered it.** The
  placeholder is an Argo-CD-owned object, so removing the module block removes the access key an
  operator typed in; recreating it is a patch, and knowing what to type is somebody's memory.
  Naming an existing Secret is how an environment keeps the credential outside that lifecycle.
- **Backups are somebody else's problem, and now there is more to lose.** Nothing here backs up a
  bucket, exactly as nothing backs up the PVCs it replaced. What changed is that one volume now
  holds every signal, so the thing nobody backs up is bigger and easier to lose in one step.
- **Whether `local-path` is fast enough for Mimir's compactor is unmeasured.** Object storage over
  a local disk, over a network hop, on a two-node cluster, is a different profile from the
  filesystem backend it replaced. Measure before assuming it is an improvement rather than a
  rearrangement.
