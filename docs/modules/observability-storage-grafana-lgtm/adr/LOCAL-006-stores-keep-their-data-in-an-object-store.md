# LOCAL-006. The three stores keep their data in an object store

**Status:** accepted · **Scope:** module — `observability-storage-grafana-lgtm` ·
**Date:** 2026-08-16 ·
revised 2026-08-16 (the bucket and the endpoint moved to the component —
[LOCAL-007](LOCAL-007-a-signal-is-its-own-configuration.md))

**The three stores keep their data in S3-compatible object storage, one bucket each, and no store
owns a volume.**

## Decision

Mimir, Loki and Tempo are configured against **S3-compatible object storage**, one bucket each.
No store owns a PersistentVolumeClaim any more.

The endpoint arrives as an **ordinary module input**, `object_storage`, wired at the root from
whichever module provides it — see
[`object-storage-silo`](../../object-storage-silo/README.md) for the one that does today. It
carries an address, a region, and a Secret name plus its two keys, so the credential passes by
reference and never by value
([ADR 007](../../../adr/007-modules-receive-credentials.md)). **The bucket is not among them**:
a bucket belongs to exactly one store, so it is named in that store's own block and nowhere else,
and a component may carry an `object_storage` of its own that replaces this one outright — both
[LOCAL-007](LOCAL-007-a-signal-is-its-own-configuration.md)'s subject rather than this one's.

**It is not one of the shared contracts and does not become one.** `gateway`, `database` and
`oidc` are the three, and a fourth is added when a second module needs it, not in anticipation.
Until then this is an input like any other, and the root wires it like any other
([ADR 020](../../../adr/020-one-root-module.md)).

**It is required, not optional.** There is no filesystem fallback and no `null` meaning "use a
volume instead".

## Context

All three stores were specified on filesystem backends, one PVC each:
[LOCAL-001](LOCAL-001-grafana-lgtm-stack.md) picked the single-binary shapes, and
[LOCAL-002](LOCAL-002-mimir-monolithic-chart.md) put Mimir's blocks on a volume rather than
accept "the cost of the metrics store includes a second storage system that exists only to serve
it".

That sentence is the one that has to be re-examined, because it is now wrong in one respect and
still right in another.

**Right:** an object store is a second storage system, and it does exist only to serve these
three. Nobody wants it.

**Wrong:** its cost was estimated as MinIO in a distributed topology, and the shape actually
available is one pod on one PVC — roughly what one of the three volumes it replaces already
costs. The premise the earlier decision rejected was a bigger thing than the one being offered.

Meanwhile the filesystem backend is documented by all three vendors as unsuitable for anything
but development, and for Mimir specifically the concern is concrete rather than boilerplate:
compactor and store-gateway run inside the same `-target=all` process and share the volume,
which is a configuration Grafana does not test. That was already recorded as an open item on the
spec — untested here, across restarts — and it was never going to become tested by waiting.

The decision that is *not* being re-examined: the stores stay single-binary, one pod each.
Nothing about the topology in [LOCAL-001](LOCAL-001-grafana-lgtm-stack.md) or
[LOCAL-002](LOCAL-002-mimir-monolithic-chart.md) changes. Only where the bytes land.

## Rationale

- **The alternative to a supported backend is not "a simpler backend", it is an unsupported
  one.** Filesystem mode was chosen to avoid a dependency, and what it bought was three
  deployments in configurations their vendors decline to stand behind. The dependency is one pod.
- **Required, because an optional backend means the unsupported path is what you get by
  forgetting an input.** Two backends is also two sets of values, two failure modes and two
  things to reason about at three in the morning, in a module whose whole design is about
  degrading cleanly along one axis — which signals are switched on — and not two.
- **One bucket per store rather than one shared bucket with prefixes.** Prefixes work, and they
  make "delete everything Loki wrote" a filtered delete instead of a bucket drop. Three names
  cost three lines.
- **Retention becomes enforceable against a number somebody chose.** Per-tenant retention was
  always expressed three ways; it was bounded by three volumes whose sizes were decided
  separately. It is now bounded by one disk with one size, which is not less risky but is at
  least a single number to compare against — for as long as every store writes to the same
  endpoint, which is the expected configuration and no longer the only expressible one
  ([LOCAL-007](LOCAL-007-a-signal-is-its-own-configuration.md)).
- **It removes the one PVC per store that pinned each store to a node.** It does not remove the
  pin — the object store's own volume is pinned exactly as they were — but it moves three pins
  into one, and the thing that survives a store's pod being rescheduled is now its data.

## Alternatives

- **A PVC per store**, which is what all three had. One node's disk holds every signal, resizing
  is a manual operation per store, and the volume is the thing that does not survive the node.
- **One shared PVC.** Cheaper in objects and it makes three stores contend for one disk with no
  per-signal ceiling — the failure [REQ-15](../../../requirements.md) names.
- **A managed S3 endpoint.** No component to run, and every signal leaves the environment for a
  network this repository does not assume exists.

## Consequences

- **This module does not start without the object store**, and nothing sequences the two. A
  module declares what it needs and never when it is satisfied
  ([ADR 007](../../../adr/007-modules-receive-credentials.md)), so Argo CD may sync Mimir before
  the endpoint is serving. That resolves itself in a crash loop, and looks exactly like a
  misconfigured address, which does not.
- **The buckets are created by hand**, per environment and again after a rebuild — and unlike a
  credential, nothing here declares even the empty shape of one
  ([ADR 022](../../../adr/022-secrets-are-rendered-empty.md) covers Secrets and not this). A
  bucket that does not exist is not a sync failure: every store comes up healthy
  and the error appears on the first write, in this module's logs, about a resource another
  module's spec documents.
- **Every signal now fails together**, unless one is deliberately pointed elsewhere. Three
  volumes failing independently became one process holding all three. The independence
  [REQ-02](../../../requirements.md) asks for is about what an environment *ships* — a signal
  switched off costs nothing — and this does not touch that; what it costs is availability
  independence between signals that are all switched on. Buying that independence back is what a
  per-component endpoint is for, and it costs a second object store to point at
  ([LOCAL-007](LOCAL-007-a-signal-is-its-own-configuration.md)).
- **`storage_node_selector` loses its meaning here** and moves to the module that owns the
  volume. Nothing in this module owns a PVC any more, so there is nothing left to place.
- **The unmeasured question changed rather than went away.** Mimir's compactor now runs against
  its documented backend, over a network hop, onto the same class of local disk as before.
  Whether that is faster, slower or merely more supportable is unmeasured, and the honest claim
  is only the last of the three.
- **Reversing this is a values change plus a data copy**, in either direction, because every
  store reads a bucket and a key rather than anything about what serves them.
