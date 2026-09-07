# Module: object-storage-silo

**Status:** implemented ·
**Satisfies:** [REQ-05, REQ-09, REQ-10](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-silo-single-node.md),
[ADR 005](../../adr/005-modules-are-applicationsets.md),
[ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 008](../../adr/008-postgresql-is-external.md),
[ADR 010](../../adr/010-resources-delivered-via-chart.md),
[ADR 014](../../adr/014-exposed-does-not-mean-authorized.md),
[ADR 016](../../adr/016-metrics-is-the-fourth-input.md),
[ADR 022](../../adr/022-secrets-are-rendered-empty.md),
[ADR 027](../../adr/027-charts-are-first-class-artifacts.md)

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

**The product behind it is Silo, and no consumer can tell.** That is not a courtesy — it is the
whole reason the module exists, and it is what makes changing the product an image tag and a copy
rather than a reconfiguration of everything downstream
([LOCAL-001](adr/LOCAL-001-silo-single-node.md), [REQ-09](../../requirements.md)).

## Provisions

One Argo CD `ApplicationSet` ([ADR 005](../../adr/005-modules-are-applicationsets.md)), whose
`List` generator produces one Application — one static entry, as that ADR requires even at one:

| Wave | Application | Chart | Condition |
| --- | --- | --- | --- |
| 0 | `silo-credentials` | `secret-template` — imported, see [ADR 022](../../adr/022-secrets-are-rendered-empty.md) | `secret_name` is null |
| 1 | `silo` | `silo-standalone` — authored by this repo | always |

**Charts this repository publishes are at `helm/<chart>/`, not in this module's directory**
([ADR 027](../../adr/027-charts-are-first-class-artifacts.md)) — here that is
`helm/silo-standalone`. A module renders against a chart's published values schema, and the
chart's `Chart.yaml` version is what moves when that schema does, so it may have consumers other
than this one. Check before editing it.

**The custom case** of [ADR 010](../../adr/010-resources-delivered-via-chart.md): Silo publishes
no chart, and the path its own documentation recommends is the MinIO Operator's Tenant chart with
the image overridden — an Operator to run one pod, plus a pinned chart rendered against an image
it was not released with ([LOCAL-001](adr/LOCAL-001-silo-single-node.md)). So the chart is
authored here and the Application owns every object it needs, route included.

**The waves are load-bearing.** Silo refuses to start without a root credential, so the Secret has
to exist first — empty is enough for the pod to be scheduled, and filling it is the operator's
step below. Where `secret_name` names an existing Secret there is no first Application at all:
this module reads that object and never owns it.

**One StatefulSet, one replica, one drive.** No erasure coding, no pools, no rebalancing, no site
replication — those belong to a topology of four or more nodes, and the arithmetic of why two
would not help is in [LOCAL-001](adr/LOCAL-001-silo-single-node.md). The volume comes from the
StatefulSet's `volumeClaimTemplates`, which is a claim that outlives the object that made it; see
[Open items](#open-items), because that changes what pruning this module does.

**Everything is renamed to `s3-svc`** through `fullnameOverride`, so the address consumers are
configured with names the protocol rather than the product: the Service is `s3-svc`, the volume
`s3-data`. The `-svc` suffix used to be an upstream chart's habit and is now a name this
repository chose deliberately — keeping it is what makes `endpoint` byte-identical across the
change of product, and the next implementation has to keep it too.

**The console stays on, and whether it is reachable is a separate question.** It is how a person
lists a bucket or confirms a write landed, and this module's buckets are created by hand, which
makes "nothing was stored and nobody noticed" a likely failure rather than a theoretical one.
Unrouted, `kubectl port-forward` reaches it; see [Exposure](#exposure) for what routing it costs.

**Nothing here creates a bucket.** The chart provisions none, and no consumer creates its own —
see [Prerequisites](#prerequisites). This is the module's sharpest edge and it is not hidden in
an open item.

**This module takes no `metrics` input, and the reason is a cycle rather than an absent endpoint.**
Silo inherits MinIO's `/minio/v2/metrics/*` surface, so unlike the store this replaces there *is*
something a `ServiceMonitor` could name. It still cannot be scraped into the collector that stores
telemetry in these buckets: that module consumes this one's address, so pointing a scrape config
back at it is a cycle OpenTofu refuses at plan time, not a configuration choice
([ADR 016](../../adr/016-metrics-is-the-fourth-input.md) is what a module with a metrics endpoint
would otherwise take). The chart renders no `ServiceMonitor` and the endpoints are left alone —
see [Open items](#open-items), because "there is an endpoint and nothing reads it" is a weaker
position than the one this paragraph replaced.

### Resources

**The container carries limits, and three settings that make the limits mean something.** Both
halves ship together; neither is a tuning exercise and neither is optional
([LOCAL-001](adr/LOCAL-001-silo-single-node.md), [REQ-10](../../requirements.md)):

| Setting | Value | What it is for |
| --- | --- | --- |
| requests | `cpu 200m`, `memory 512Mi` | what an idle store actually holds, so the scheduler places it honestly |
| limits | `cpu 2000m`, `memory 2Gi` | the ceiling the operator is willing to spend on this pod |
| `GOMEMLIMIT` | `1700MiB` | ≈83% of the memory limit — a soft ceiling the Go collector acts on before the kernel does |
| `GOMAXPROCS` | `2` | matches the CPU limit, so the runtime is not sized for cores the pod cannot use |
| `MINIO_API_REQUESTS_MAX` | `128` | the concurrency ceiling, stated rather than inferred |

**Two things auto-size themselves from the wrong number, which is why the last three exist.** The
server derives its own request-concurrency ceiling from the RAM it observes — roughly
`(0.75 × total RAM) / 2MiB` — and under a cgroup limit what it observes is the node's memory, not
the container's. The Go runtime does the same one level down: with no `GOMEMLIMIT` it grows the
heap past the container limit until the kernel kills the process, and an OOM kill here is every
signal at once. Neither failure looks like a memory setting when it happens; both look like a
storage bug.

**So the chart refuses to render a memory limit with no `GOMEMLIMIT`.** A values file carrying one
without the other is the slow crash loop above, and a chart that renders it would be handing that
out silently. Refusing is the only place that combination can be caught cheaply, because the
symptom arrives days later under load.

### Exposure

**Two surfaces, exposed independently, and neither by default.** This workload serves the S3 API
and a management console on two ports of one Service, and they are not the same kind of thing —
so each takes its own `port`, its own `hostname` and its own Gateway:

| Surface | Default port | Routed when | Route |
| --- | --- | --- | --- |
| `api` | 9000 | it has a hostname | `HTTPRoute` `s3-svc-api` → `s3-svc:<api port>` |
| `management_console` | 9001 | it has a hostname | `HTTPRoute` `s3-svc-console` → `s3-svc:<console port>` |

**Separate listeners is the point.** The API is a read *and* write surface over every stored
object; the console is an admin UI over the same objects behind the same root credential. Putting
them on one `section_name` would mean whichever posture is right for one is imposed on the other,
and they are not the same question. A surface with no hostname produces no route at all — that,
and nothing else, is what "not exposed" means here.

**Each `port` is one input driving the whole path.** The Service port, its `targetPort`, the
`containerPort`, the address the process binds and the port both probes address all come from the
one value. The chart owning that is the difference from the arrangement this replaces, where the
Service port and the process's bind address were separate upstream values and setting one without
the other yielded a Service pointing at a port nothing was listening on.

**One hostname cannot name two surfaces**, so giving the API and the console the same one is
refused at plan time rather than producing two `HTTPRoute`s that fight over a host. It is the same
rule as two surfaces sharing a port and it is worth stating separately, because a single hostname
across both is what a reader coming from a one-surface module would naturally write.

**What may reach it is the listener's, and nothing here narrows it**
([ADR 014](../../adr/014-exposed-does-not-mean-authorized.md)). This surface is read *and* write
over every stored signal, so unlike the OTLP ingest endpoint there is no argument that it is
write-only: pointing `section_name` at the mTLS listener is the only posture that makes sense,
and the module cannot enforce that choice. Routing the console should come with a listener that
demands a client certificate; `management_console.hostname` is null until somebody decides
otherwise, which is the module leaving that judgement where the environment can make it.

### Credentials

**One root credential, by reference** ([ADR 007](../../adr/007-modules-receive-credentials.md),
[REQ-05](../../requirements.md)). The chart names a Secret and reads two keys out of it with
`secretKeyRef`, so no credential reaches a values.yaml, a rendered `Application` spec or state.

**The keys are `ACCESS_KEY` and `SECRET_KEY`, and they name no product.** The chart maps them onto
the process's `MINIO_ROOT_USER` and `MINIO_ROOT_PASSWORD` itself. Reading two keys by reference
rather than mounting a whole Secret as environment is what buys that: the variable names the
process wants stay inside the chart, where they belong to the implementation, and the Secret's
schema stays something the next implementation can also satisfy. The store this replaces had the
opposite arrangement and its Secret's key names were its product's environment variables.

**The pair is shared, and the buckets are what keep the stores apart.** Every consumer
authenticates as the same identity; what stops one store touching another's data is that each
writes to its own bucket and is configured with no other. That is a convention this module
enforces nothing about: the credential can reach every bucket, so a misconfigured bucket name is
a store writing into a neighbour's data rather than an access denial. Per-bucket keys with a
policy each are on offer and this module does not use them — one operator, one cluster and no
adversary that partitioning would stop. Revisit it the day the endpoint is routed.

## Prerequisites

**The root credential, filled in.** With `secret_name` left null this module renders the Secret
itself — empty, with `ACCESS_KEY` and `SECRET_KEY` present — and its contents are ignored on
every sync ([ADR 022](../../adr/022-secrets-are-rendered-empty.md)), so what an environment owes
is a value and not an object. Naming an existing Secret instead is the other half of that
decision: this module then only reads it, and creating it is somebody else's job.

```sh
kubectl patch secret object-storage-credentials -n object-storage \
  --type merge -p "$(jq -n --arg a "$(printf %s "$ACCESS_KEY" | base64)" \
                          --arg s "$(printf %s "$SECRET_KEY" | base64)" \
                          '{data:{ACCESS_KEY:$a,SECRET_KEY:$s}}')"

kubectl rollout restart statefulset/s3-svc -n object-storage
```

**Expect a crash loop until that patch lands, and it is not a misconfiguration.** Silo will not
start against an *empty* root credential — it exits, and the pod restarts, and it exits again.
The store this replaces came up and served 403s instead, so a reader who remembers that behaviour
will read this one as broken. It is self-resolving: patch the Secret, restart, and it comes up.
**What it looks like in the logs is indistinguishable from the wrong key names**, which is the
reason to check the Secret's keys before debugging anything else.

The restart is not optional either: the values are read at start, so a pod that came up against
the empty Secret keeps the empty values until it is replaced.

**The same value, again, wherever a consumer runs.** A Secret is namespaced, so each consuming
module renders its own placeholder in its own namespace and an operator fills that one too —
**under whatever key names that workload reads, which are not these two.** Same secret, different
keys, because the keys belong to whoever consumes them. Two copies of one credential, and nothing
detects them disagreeing: the symptom is a store that starts cleanly and gets `403` on every
write.

**Every bucket a consumer names, created by hand once the store is running.** Nothing creates
them: not the chart, and not Mimir, Loki or Tempo, each of which requires its bucket to already
exist and reports its absence as an ingest error rather than a startup one. Using any S3 client
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
  size  = "20Gi"
  class = "local-path"
}

placement = {                         # which machine this runs on, and so which one holds the data
  node_selector = null                # e.g. { "kubernetes.io/hostname" = "k3s-01" }
  affinity      = null                # the API's own shape, passed through as given
  tolerations   = null                # e.g. [{ key = "node-role.kubernetes.io/control-plane",
}                                     #         operator = "Exists", effect = "NoSchedule" }]

region = "us-east-1"                  # what consumers must be configured with

resources = {
  requests         = { cpu = "200m",  memory = "512Mi" }
  limits           = { cpu = "2000m", memory = "2Gi" }
  go_memory_limit  = "1700MiB"        # required whenever limits.memory is set
  go_max_procs     = 2
  api_requests_max = 128
}

services = {
  api = {
    port     = 9000
    hostname = "s3.lab.internal"      # null is not routed
    gateway = {                       # anything omitted comes from the cluster's gateway
      name         = "traefik-gateway"
      namespace    = "traefik"
      section_name = "otlp-mtls"      # this listener is who may read and delete
    }
  }
  management_console = {
    port     = 9001
    hostname = null                   # not routed, and the right setting unless somebody asks
  }
}
```

Plus `silo.image_tag`, and `git_repository` — this repository and the revision Argo CD reads its
charts at, which every module rendering one of them takes. This module always renders one, so it
is always consulted.

**`services` stands in for the `gateway` contract**, because this module has two routable surfaces
and that contract describes one ([ADR 007](../../adr/007-modules-receive-credentials.md)). The
Gateway reference inside each service is that same object minus `hostname`, which moved up beside
`port` because it belongs to the surface rather than to the Gateway.

Four things are refused at plan time rather than at sync: **two surfaces sharing a port** — they
are two ports on one Service and one number cannot name both; **two surfaces sharing a hostname**,
for the same reason one level up; **a hostname with no `gateway.name`/`namespace`** — `null` is a
valid value of every type, so the shape alone would let a caller render a route attached to
nothing; and **a port outside 1–65535**.

`database` and `oidc` would be meaningless: this is the thing other workloads store state *in*,
and its one credential is an access key rather than a person. `metrics` is absent for the reason
in [Provisions](#provisions) — the endpoint exists and the only collector that could scrape it is
downstream of this module.

**`region` is an input rather than a constant** because S3 clients send it and compare it, and
because an environment migrating buckets in from somewhere else has a name to match. It is
otherwise arbitrary — there are no regions here.

**`storage.size` has no sensible default and 20Gi is a guess.** It is the whole disk budget for
every signal this cluster stores, and the retention set per tenant in the consuming module is
what has to fit inside it. Those two numbers are set in different files by different reasoning
and nothing compares them.

**`placement` names the machine that holds the data**, and it is one object because its three
fields are one subject ([§3.3](../../../CONSTITUTION.md#3-module-inputs)). A StorageClass that
binds on first use creates the claim against whichever node the pod was scheduled onto and leaves
it there, so every later scheduling decision is already made — the pod returns to the node holding
its volume or it does not start. This is the one chance to choose that machine rather than let the
scheduler choose it on the day.

`node_selector` is the flat form: labels that must all match, with no alternatives and no
negation. `affinity` is the same question with the expressiveness the flat form lacks — a set of
acceptable nodes, or a preference that degrades instead of failing — and is passed through in the
Kubernetes API's own shape rather than restated here, because a second copy of that schema is a
second thing to drift. Both may be set; both then apply.

`tolerations` is what makes either reachable, and it is here rather than assumed away because of
how small clusters actually look: the machine somebody wants this on is frequently the one that
is set apart, and on k3s that is a control-plane node carrying a taint that refuses ordinary
pods. Naming it without tolerating its taint gives a pod that is Pending forever behind a
manifest that reads as correct.

It stays a deliberate choice rather than a spreading one: this is still one pod against one
volume, and nothing here is a step toward replicas.

**`resources` is one object because its five fields are one subject** ([§3.3](../../../CONSTITUTION.md#3-module-inputs)).
Raising `limits.memory` without raising `go_memory_limit` gives the Go runtime permission to grow
into headroom the collector does not know about; raising `limits.cpu` without `go_max_procs`
leaves the scheduler sized for the old ceiling. They are set together or the change is only half
made, which is the argument for one object rather than a `resources` block and a `tuning` block
beside it.

**`silo.image_tag` is the pin, and it is the only place this version is written.** What gets
pinned here is an *image* rather than a chart version, because the chart is this repository's —
[§2.5](../../../CONSTITUTION.md#2-modules) pins upstream charts so a values schema cannot move
underneath a module, and a chart owned here moves only when somebody in this repository moves it.
A value set at the root would not add a second opinion, it would replace this one silently. Plus
`argocd.namespace`, where the `ApplicationSet` object goes; no environment normally writes it.

## Outputs

| Output | Used by |
| --- | --- |
| `endpoint` | any workload configured with an S3 backend — `s3-svc.<namespace>.svc.cluster.local:9000` |
| `region` | the same, as the region its client sends |
| `credentials_secret_name` | an operator, to know what to fill in — the name given, or the one rendered |
| `api_url` | the S3 API from outside the cluster — `null` unless it was given a hostname |
| `console_url` | the management console from outside — `null` unless it was given a hostname |

**No output names the product, and no output's *value* does either** — `fullnameOverride` is what
buys that, and it is the reason it is set. A consumer wired to these is configured for S3 and
would not notice the implementation changing underneath it ([REQ-09](../../requirements.md)).
**This module changed product and not one of these strings moved**, which is that claim being
tested rather than asserted.

**`url` is for a person, not for a store.** Everything that writes here does so over `endpoint`,
in-cluster; the external address exists so a bucket can be created, or a write inspected, without
a port-forward.

**`endpoint` is a host and port, not a URL**, because that is the shape every S3 client
configuration field takes. Whether it is reached over TLS is a separate field in each of those
clients, and in-cluster it is not: plain HTTP inside the cluster, on the same reasoning that the
OTLP receiver's in-cluster address is plain.

**There is no bucket output**, because there is no bucket input. What buckets exist is a fact
about what somebody created by hand, and publishing a list this module cannot verify would be
publishing a claim rather than an address.

## Acceptance criteria

`OBJ-04`, `OBJ-05`, `OBJ-12` and `OBJ-14` are retired and their numbers are not reused. The first
two were written against an earlier `gateway` input; `OBJ-12` replaced them by asserting nothing
was reachable from outside in *any* configuration, which stopped being true when this capability
gained a route; and `OBJ-14` asserted that the only route addressed the API, which stopped being
true when the console became routable. `OBJ-16` through `OBJ-19` are what those claims became.
`OBJ-15` names no scenario either, and is not reused.

**The numbers that survive do so because the scenarios did.** Changing the product behind this
capability changed almost none of what is checked — which is the point, and is why the
traceability matrix needs no edit. `OBJ-20` onwards is the genuinely new behaviour.

```gherkin
Feature: One S3-compatible endpoint, per environment

  @cluster
  Scenario: [OBJ-01] One pod, one volume
    Given the module is applied
    When pods and PersistentVolumeClaims in the namespace are listed
    Then exactly one Silo pod exists
     And exactly one PersistentVolumeClaim exists, from the StatefulSet's volumeClaimTemplate
     And no second volume was created for logs or for a config file

  @cluster
  Scenario: [OBJ-02] The credential is never rendered
    Given the module is applied
    When the Application specs are read from the API server
    Then no access key or secret key appears in any rendered Helm values
     And the container reads MINIO_ROOT_USER and MINIO_ROOT_PASSWORD through secretKeyRef
     And the Secret those refer to is the one credentials_secret_name names

  @cluster
  Scenario: [OBJ-10] The placeholder arrives with its keys, and is never overwritten
    Given secret_name is null
    When the module is applied
    Then a Secret exists carrying ACCESS_KEY and SECRET_KEY, both empty
     And neither key name mentions the product
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
     And its host is s3-svc in this module's namespace

  @cluster
  Scenario: [OBJ-13] Nothing is exposed without a hostname
    Given neither service has a hostname
    When HTTPRoutes and Ingresses in the namespace are listed
    Then none exist
     And api_url and console_url are both null
     And no Gateway was created by this module

  @cluster
  Scenario Outline: [OBJ-16] Each surface is exposed on its own, or not at all
    Given only <service> has a hostname
    When HTTPRoutes in the namespace are listed
    Then exactly one exists, addressing <port>
     And <other>_url is null

    Examples:
      | service            | port | other              |
      | api                | 9000 | console            |
      | management_console | 9001 | api                |

  @cluster
  Scenario: [OBJ-17] The two surfaces can sit on different listeners
    Given both services have hostnames and different section_names
    When the two HTTPRoutes are read
    Then each attaches to the listener its own service named
     And each addresses its own service's port

  @cluster
  Scenario: [OBJ-18] A port is one number everywhere
    Given services.api.port is 9100
    When the Service, the container and the process arguments are read
    Then the Service port, its targetPort and the containerPort are all 9100
     And the process is configured to listen on 9100
     And both probes address 9100

  @plan
  Scenario Outline: [OBJ-19] What cannot work is refused before it is applied
    Given <configuration>
    When tofu plan runs
    Then it fails, naming the input

    Examples:
      | configuration                                     |
      | both services given the same port                 |
      | a service with a hostname and no gateway.name     |
      | a port outside 1-65535                            |

  @plan
  Scenario: [OBJ-22] The console and the API cannot share a hostname
    Given both services are given the same hostname
    When tofu plan runs
    Then it fails, naming both services
     And no HTTPRoute is planned

  @cluster
  Scenario: [OBJ-20] The ceiling and the settings that respect it ship together
    Given the module is applied with the default resources
    When the container spec is read
    Then its requests are cpu 200m and memory 512Mi
     And its limits are cpu 2000m and memory 2Gi
     And GOMEMLIMIT is 1700MiB
     And GOMAXPROCS is 2
     And MINIO_API_REQUESTS_MAX is 128

  @plan
  Scenario: [OBJ-21] A memory limit with no GOMEMLIMIT does not render
    Given resources.limits.memory is set and resources.go_memory_limit is null
    When the chart is rendered
    Then it fails, naming GOMEMLIMIT
     And no StatefulSet is produced

  @cluster
  Scenario: [OBJ-06] The store's own telemetry does not depend on itself
    Given the module is applied
    When the namespace is inspected
    Then no ServiceMonitor exists
     And nothing configures the store to send telemetry to a collector that stores it here

  @cluster
  Scenario: [OBJ-07] Its logs are readable by a collector
    Given the module is applied
    When the Silo container's stdout is read
    Then its log lines are there
     And no log file was written to the data volume

  @cluster
  Scenario Outline: [OBJ-08] Placement is chosen, not inherited
    Given <input> selects a node
    When the module is applied
    Then the Silo pod runs on that node
     And its claim was created against that node

    Examples:
      | input                  |
      | placement.node_selector |
      | placement.affinity      |

  @cluster
  Scenario: [OBJ-23] A tainted node is reachable, and only deliberately
    Given placement selects a node carrying a taint that refuses ordinary pods
     And placement.tolerations does not tolerate it
    When the module is applied
    Then the pod stays Pending rather than landing somewhere else
     And adding the matching toleration is what schedules it

  @plan
  Scenario: [OBJ-24] An affinity key the API server would reject is refused first
    Given placement.affinity carries a key other than nodeAffinity, podAffinity or podAntiAffinity
    When tofu plan runs
    Then it fails, naming the input

  @cluster
  Scenario: [OBJ-09] A missing bucket is the consumer's error, not a broken store
    Given the module is applied and no bucket has been created
    When a consumer writes to a bucket that does not exist
    Then the store is healthy and serving
     And the write fails with a no-such-bucket error
```

## Open items


- **The console reaches the S3 API on the in-cluster Service, and share links carry that address.**
  Signing in to the console is a call this pod makes to the API, and it is deliberately not routed
  through the Gateway: doing that would make signing in depend on cluster DNS resolving a name that
  exists only on the network outside, on the ingress answering traffic that arrives from behind it,
  and on this container trusting the certificate that ingress presents. None of those is implied by
  the console being reachable from a browser, and each one fails as the same unexplained network
  error with nothing in the pod log to distinguish them. The cost is that a presigned or shared URL
  minted by the console comes back as `s3-svc.object-storage.svc.cluster.local`, which nobody
  outside the cluster can open. Making those external means setting the chart's `serverUrl` **and**
  satisfying all three conditions — a DNS answer inside the cluster for the external name, an
  ingress that hairpins, and the lab authority in this container's trust store, which this
  repository already distributes as a bundle to every namespace. That is the day to add the input;
  there is none today because there would be no correct value for it.
- **Nothing creates the buckets, and nothing notices they are missing.** The store starts healthy
  with no buckets at all, so the failure surfaces as an ingest error in whatever consumes it,
  hours later and in another module's logs. A rebuild that recreates every Application correctly
  still ends with a cluster that stores nothing. This is the single most likely way a fresh
  environment ends up quietly broken.
- **One pod is a single point of failure for every signal at once.** Metrics, logs and traces
  previously failed independently, each with its own volume; they now share a process. This is a
  known cost of the decision that put them here and not a defect to fix by adding replicas —
  replicas are the shape this cluster does not have, and two nodes would buy reads through a node
  failure and not writes ([LOCAL-001](adr/LOCAL-001-silo-single-node.md)).
- **Nothing sequences this module against its consumers.** A module declares what it needs and
  never when it is satisfied, so Argo CD may sync Mimir before the store is serving. The result is
  a crash loop that resolves itself, which is acceptable, and which looks identical to a
  misconfigured endpoint, which is not.
- **`MINIO_API_REQUESTS_MAX: 128` is a first guess.** It is a number chosen to be stated rather
  than inferred from a memory reading that would be wrong; nothing here has measured what this
  cluster's write path actually needs. It moves with `limits.memory` and `GOMEMLIMIT` — all three
  express one budget in three units, and changing one alone is how the ceiling stops meaning what
  the other two assume. Measure under a compaction before moving any of them.
- **`readOnlyRootFilesystem` against the distroless image is unverified.** The hardened posture is
  the one to want and nothing here has confirmed the process does not write outside its data
  volume — a temporary directory, a lock file, a cache. It stays off until it has been run with it
  on, because a store that will not start is a worse outcome than a writable root.
- **There is a metrics endpoint and nothing reads it.** `/minio/v2/metrics/*` exists on this
  implementation, and the collector that could scrape it is downstream of this module, so wiring
  it is a dependency cycle rather than a configuration. An environment that wants the store's own
  metrics needs a scrape config written outside this module's graph, pointing at a literal
  address, and accepting that it is telemetry about the store being written into the store.
- **The disk has one number and three tenants' retention pointing at it.** `storage.size` is set
  here; what is allowed to fill it is set per tenant in the consuming module. Nothing compares
  them, and the failure is writes rejected across every signal at once.
- **One access key for every consumer, so the bucket boundary is a convention.** A store
  configured with the wrong bucket name reaches it, and a compromised one reaches all of them.
  Per-bucket keys with a policy each are on offer and this module does not use them; the day the
  endpoint is routed, that trade should be re-made.
- **The data now survives a prune, and the claim it leaves behind is nobody's.** A
  `volumeClaimTemplates` claim is not garbage-collected with its StatefulSet, so removing the
  module block no longer deletes every stored signal — the opposite of the arrangement this
  replaces, where the PVC went with the Deployment. That is the safer direction and it is not
  free: the claim outlives the Application that made it, holds the disk, and will be adopted by
  the next StatefulSet of the same name whether or not that is what anybody meant. Decide who
  deletes one before anyone reorganises the root module.
- **Pruning deletes the credential along with the store, when this module rendered it.** The
  placeholder is an Argo-CD-owned object, so removing the module block removes the access key an
  operator typed in — while, now, leaving the volume it unlocked. Recreating it is a patch, and
  knowing what to type is somebody's memory. Naming an existing Secret is how an environment keeps
  the credential outside that lifecycle.
- **Backups are somebody else's problem, and there is a lot to lose.** Nothing here backs up a
  bucket, exactly as nothing backs up the PVCs it replaced. One volume holds every signal, so the
  thing nobody backs up is bigger and easier to lose in one step.
- **Whether `local-path` is fast enough for Mimir's compactor is unmeasured.** Object storage over
  a local disk, over a network hop, on a two-node cluster, is a different profile from the
  filesystem backend it replaced. Measure before assuming it is an improvement rather than a
  rearrangement.
