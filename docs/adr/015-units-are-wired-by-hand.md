# 015. Units are wired by hand

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-15

## Context

[ADR 007](007-modules-receive-credentials.md) says a provider publishes its address and a
consumer receives a fully-formed reference. It never says how the value gets from one to the
other, and by now several do: the console reads three store addresses, every consumer reads an
issuer URL, a Gateway listener references two Secret names, and three modules read
`metrics.enabled` ([ADR 016](016-metrics-is-the-fourth-input.md)).

Terragrunt answers this with `dependency` blocks — a unit reads another unit's outputs from its
state. The alternative is that the environment writes the value down once and both sides read it
from there.

## Decision

**No unit reads another unit's state.** There are no `dependency` blocks.

**A value two units share is declared once in the environment**, in `env.hcl` or in
`_envcommon/<module>.hcl`, and both units read it from there.

## Rationale

- **These values are derivable, not discoverable.** `mimir.<namespace>.svc.cluster.local` is a
  function of a namespace and a release name, both of which the environment already declares. A
  `dependency` block would read back, through a state file, a string the environment could have
  written directly. That is machinery standing between two facts that were never apart.
- **`dependency` blocks make every consumer carry a fiction.** A unit must be plannable before
  the unit it depends on has ever run, so each one needs `mock_outputs` — a fake address, in the
  repository, that is correct in exactly the case where nothing has been applied. It is the kind
  of value that stops being noticed and then stops being right.
- **It keeps a statement in the README true.** *An environment ships a module by having a unit
  directory for it* — with a state dependency, the console's directory cannot plan until the
  storage unit's state exists, so the tree and reality disagree in a way nothing records.
- **It does not inherit [ADR 012](012-state-is-per-environment.md)'s open question.** A
  `dependency` block reads a state file, so the wiring mechanism would acquire whatever the
  backend decision turns out to be, including its locking and reachability behaviour. Wiring
  that reads no state is unaffected by where state lives.
- **One operator, a handful of values, changed approximately never.** The same argument
  [ADR 007](007-modules-receive-credentials.md) makes for registering OIDC clients by hand
  applies here, for the same reason and at the same scale.

## Consequences

- **A hand-written address can disagree with reality**, and this weakens an argument made
  elsewhere. The observability split chose to hand the console three *addresses* rather than
  three booleans, on the grounds that a flag and the store it claims to describe are two truths
  that can disagree once they live in different units. Without automated wiring, so can an
  address. The choice still stands — an address says more than a boolean, and a wrong address
  fails visibly where a wrong boolean fails silently — but its reasoning is now weaker than when
  it was written.
- **Derive both sides from one value to keep that narrow.** A namespace declared once in
  `env.hcl`, read by the module that creates the Service and by the module that addresses it, is
  a single fact rather than two agreeing strings.
- **[ADR 007](007-modules-receive-credentials.md)'s dependency-cycle warning no longer describes
  anything.** It says deriving a redirect URI from a consumer's output while the consumer takes
  `client_id` from the provider "is a dependency cycle Terragrunt will refuse". With no
  dependency graph there is nothing to refuse — the two values are simply written down once, in
  the environment, which is what that consequence recommended anyway.
- **Ordering is operational and unenforced.** Applying the console before the storage module
  produces a Grafana pointing at addresses that do not resolve yet. Nothing warns; it starts
  working when the other unit is applied. That is the same posture
  [ADR 007](007-modules-receive-credentials.md) already takes toward Secrets that do not exist
  yet — a module declares what it needs, not when it is satisfied.
- **Renaming a namespace is a two-place edit**, and a missed one produces a consumer addressing
  nothing. Acceptance criteria assert the addresses resolve; nothing asserts they were derived
  from the same source.
- **Reversible per value, not per repository.** Introducing one `dependency` block later is a
  local change to one unit, not a redesign — which is why this decision is cheap to hold and
  cheap to abandon in the one place that eventually earns it.
