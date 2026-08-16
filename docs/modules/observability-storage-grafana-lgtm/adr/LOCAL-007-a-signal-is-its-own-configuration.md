# LOCAL-007. A signal is its own configuration, and its presence is the switch

**Status:** accepted · **Scope:** module — `observability-storage-grafana-lgtm` ·
**Date:** 2026-08-16

## Context

[LOCAL-001](LOCAL-001-grafana-lgtm-stack.md) gave each signal a boolean —
`enable_metrics_support` and its two siblings — and everything else about that signal went
somewhere else. Its bucket was a key in `object_storage.buckets`
([LOCAL-006](LOCAL-006-stores-keep-their-data-in-an-object-store.md)), its retention a key under
each tenant in `var.tenants`, and its store's own settings a key in a values override map. Four
inputs, each holding one third of three signals, and no input holding one signal.

That shape has a defect the module already argues against elsewhere. The console module refused
to take three booleans describing the stores and takes three addresses instead, because *"a flag
and the store it claims to describe are two truths that could disagree"*. The same sentence is
true one module earlier: `enable_traces_support = true` with no `buckets.traces` is a state
nothing prevents, and it plans clean, syncs clean, and fails on the first write.

Two further requirements arrive at the same time and point the same way. **A store must be able
to write to a different endpoint from its siblings** — the module was written assuming one object
store because there was one, not because one is required. And **a bucket must not be settable
globally**: two stores sharing a bucket is not a configuration anyone wants, and the surest way
to prevent it is for there to be no place to say it.

## Decision

**Each signal is one optional block, and the block's presence is what ships the store.** The
three `enable_*_support` booleans are removed.

```hcl
object_storage = {                    # the default every store inherits whole
  endpoint       = "s3-svc.object-storage.svc.cluster.local:9000"
  region         = "af-south-1"
  secret_name    = null               # null: rendered here — ADR 022
  access_key_key = "RUSTFS_ACCESS_KEY"
  secret_key_key = "RUSTFS_SECRET_KEY"
  insecure       = true               # host:port carries no scheme; this picks one
}

retention = {                         # the defaults every component inherits
  default      = "168h"
  unattributed = "24h"                # the tenant a forgotten header lands in
}

components = {
  metrics = { bucket = "mimir" }
  logs    = { bucket = "loki", retention = "72h" }
  traces  = null                      # not shipped
}
```

**`bucket` is required in every component and exists nowhere else.** It is not a field of
`object_storage`, in either position. A signal that is shipped names its own bucket, no two
components may name the same one, and there is no global default to inherit or forget.

**`retention` has three levels, and the top one is the only new place.** `retention.default` is a
cross-signal default; `components.<signal>.retention` is each store's own configuration; and
`tenants.<tenant>.<signal>.limits.retention` is that store's per-tenant override, unchanged from
[ADR 017](../../../adr/017-stores-are-multi-tenant.md). The lower two are the two levels every
store already has — Mimir's `compactor_blocks_retention_period`, Loki's
`limits_config.retention_period` and Tempo's `compaction.block_retention`, each with per-tenant
overrides above it. Only the top level is this module's invention, and it exists so an
environment writes its number once. `retention.unattributed` sits beside it because the tenant a
forgotten header lands in exists to be noticed and emptied, so inheriting a component's number
would be the wrong answer in every case.

**A component may carry its own `object_storage`, and it replaces the default outright.** The
same object type in both positions, with the same field-level defaults; when a component sets
one, the top-level block is not consulted at all. `endpoint` is required inside an override, and
`insecure` is uniform across both — a field meaning two things depending on where it is written
would be worse than a default that has to be overridden.

## Rationale

- **One input holds one signal.** Reading `components.logs` tells you whether logs are shipped,
  where they land, and how long they are kept. Nothing about logs is anywhere else except the
  per-tenant ceilings, which are per *tenant* and belong with them.
- **The disagreeing pair is gone by construction, not by validation.** There is no flag to be
  true while the configuration it describes is absent, because the configuration *is* the flag.
  A validation would have caught the same error later and needed maintaining.
- **A bucket cannot be shared by accident**, because sharing one is not expressible in fewer
  words than not sharing one. This is the same reasoning that gave each store its own bucket in
  [LOCAL-006](LOCAL-006-stores-keep-their-data-in-an-object-store.md), applied to the input
  surface rather than the backend configuration.
- **Replacing rather than merging, because a merged storage block is read wrong.** A partial
  override reads as "this store is like the others, but over there", and the fields it did not
  mention — the credential especially — are then inherited invisibly. Pointing a store at a
  foreign endpoint while silently handing it this cluster's access key is a configuration that
  plans clean and returns `403` on first write. Replacement makes a component that writes
  elsewhere state everything about writing elsewhere.
- **The default block stays**, because the common case is genuinely one object store and stating
  it three times would be worse than the sharp edge below.

## Consequences

- **A component overriding only its endpoint does not inherit the top-level region or
  credential.** It gets the field-level defaults instead. `region = "af-south-1"` at the top with
  a bare `endpoint` override below yields `us-east-1`, silently, and the symptom is
  `SignatureDoesNotMatch` rather than anything naming a region. Requiring `endpoint` inside an
  override prevents only the emptiest version of this. It is the price of replacement and it is
  paid at the one place someone is already thinking about where a store writes.
- **There can now be up to three placeholder Secrets rather than one.** The top-level block with
  `secret_name` null renders `object-storage-credentials`; a component whose own block leaves it
  null renders `<signal>-object-storage-credentials`; identical names deduplicate to one
  Application. Every one of them is a value somebody fills in by hand
  ([ADR 022](../../../adr/022-secrets-are-rendered-empty.md)), so the count is a real cost.
- **Two of [LOCAL-006](LOCAL-006-stores-keep-their-data-in-an-object-store.md)'s consequences
  become conditional.** *"Every signal now fails together"* and *"bounded by one disk with one
  size"* were both true of a module that could name one endpoint. They hold whenever no component
  overrides, which is the expected configuration, and they are what an override gives up.
- **One acceptance scenario is retired rather than reworded** — `OBS-01`, which asserted that all
  three flags being false fails and names them. Its replacement asserts something about an input
  that did not exist, so it takes a new ID. Every other scenario naming a flag asserts exactly
  what it always did and only says *given* differently, so those keep their numbers.
- **[LOCAL-001](LOCAL-001-grafana-lgtm-stack.md)'s flag column no longer describes anything**, and
  is revised to name the component key. The decision that ADR records — the Grafana stack, three
  single-binary components, each independently present — is untouched; only how an environment
  says so has changed.
- **Nothing checks that two components pointed at different endpoints are pointed at endpoints
  that exist**, and the second one is not this repository's to create. A missing bucket was
  already silent until the first write; a missing *endpoint* now is too, once per component.
