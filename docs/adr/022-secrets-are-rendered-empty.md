# 022. A module renders the Secret it needs, empty, unless it is given one

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-16

## Context

Every `secret_name` in this repository names an object that nothing creates.
[ADR 007](007-modules-receive-credentials.md) settled that a credential passes by reference, and
[REQ-05](../requirements.md) forbids its value reaching git, state or a rendered `Application`.
Neither says who makes the object, and the answer has been "a person, by hand, per environment,
and again after every rebuild" — recorded as an open question rather than as a design.

What that costs is only visible at a rebuild. Every Application syncs correctly, every workload
comes up, and nothing works: each pod is waiting on a Secret whose name is written down in a
spec nobody has open. The failure is per-workload, at pod start, and it reads as a broken module
rather than as a missing credential.

It also leaves [REQ-08](../requirements.md) with an exception nobody chose. Everything this repo
provisions is reconciled from a declared source, except the one class of object that decides
whether any of it functions.

The obstacle was always taken to be REQ-05 — and it is real, but it is narrower than it looked.
REQ-05 governs a credential's **value**. An empty Secret has none.

## Decision

**A module always reads its credential from a named Secret. Whether that Secret is one the module
also declares is the caller's choice, expressed by naming one or not.**

| `secret_name` | The module | Argo CD |
| --- | --- | --- |
| **set** | references it and renders nothing | never creates, owns or prunes it |
| **null** | renders a placeholder — its keys present, their values empty — and publishes the name it chose | creates it, and ignores `.data` from then on |

An operator fills the values in place, once per environment. Both modes satisfy
[ADR 007](007-modules-receive-credentials.md) identically, because in both the module holds a name
and a key and never a value.

- **A placeholder carries its keys, not just its name.** The key names come from the same inputs
  the workload's configuration is built from — `username_key`, `access_key_key` and their
  siblings — so the object always has exactly the keys the pod will look for. A Secret with the
  right name and the wrong keys is the failure this removes, and it is the one that reads as a
  broken module.
- The Secret is rendered by a chart like every other resource
  ([ADR 010](010-resources-delivered-via-chart.md)); OpenTofu still creates no bare Kubernetes
  object. One chart serves every module, and it is delivered as **`modules/secret-template`, a
  module other modules import** — the one directory under `modules/` that is not a capability.
  **It renders nothing itself**: it returns one List-generator element, which the caller
  concatenates into its own `charts`, so a consumer still renders exactly one `ApplicationSet`
  ([ADR 005](005-modules-are-applicationsets.md)) and still owns everything in it. Given every
  name, a caller sets `count = 0` on the import and there is no element, no Application and
  nothing owned.
- The generated `Application` carries `ignoreDifferences` on `v1/Secret` for `.data`, together
  with `RespectIgnoreDifferences=true`. Both are required: alone, the first only hides the field
  from a diff, and the next sync of anything pushes the empty value back over the real one.
- **A module renders only its own, in its own namespace, and never adopts.** A provider never
  renders a Secret into a consumer's namespace, because a provider knows nothing about its
  consumers ([ADR 007](007-modules-receive-credentials.md)). Where two modules need the same
  credential, each renders its own placeholder and an operator fills both. Nothing here ever puts
  an Argo CD owner reference on an object it did not create.
- **The effective name is an output**, in both modes, so what to fill in is discoverable without
  knowing which mode is in play.

## Rationale

- **REQ-05 is about values, and this decision never handles one.** What is declared is the shape
  of a credential — its name, its namespace, its keys — which is exactly the part that is
  currently written in prose in a spec and nowhere else.
- **The failure mode improves twice over.** "The object does not exist" becomes "the value is
  empty", which is what it actually is; and what remains to be done after a rebuild becomes
  discoverable by listing Secrets, instead of by reading five specs looking for `secret_name`.
- **A rebuild costs the same number of human actions and fewer decisions.** `kubectl patch`
  against an object that already has the right name, namespace and key names, rather than
  `kubectl create secret` with all four to get right from memory.
- **`ignoreDifferences` is the right mechanism and this is its second legitimate use.** It has
  the same shape as the first: a field whose content is owned by something other than the chart —
  a controller there, a person here — that Argo CD must not push back. Reaching for it to protect
  a credential a chart *generated* would still mean the chart is wrong; nothing here generates
  one.
- **One shared chart, because the resource has no per-module content.** A Secret with a name, a
  namespace and a list of empty keys is the same object everywhere, and four copies of it would
  drift.
- **Shared as a module rather than as a path every caller repeats.** The chart's git coordinates,
  the sync wave and the shape of the element are one thing each consumer would otherwise declare
  for itself — five variables and a `local` per module, all of which have to agree. Importing a
  module that returns the element makes that contract a signature instead of a convention.
- **Upstream escape hatches were the alternative and were rejected for uniformity.** RustFS's
  chart has `extraManifests` and Grafana's has `extraObjects`; the next chart has neither, or
  spells it a third way. One mechanism that works everywhere beats a per-chart lookup.
- **Naming an existing Secret has to stay available, because this is not a secret manager.** An
  environment that grows one — External Secrets, a CSI driver, a Secret restored from a backup —
  already has the object, and a module that insisted on rendering its own would either fight that
  controller over `.data` or refuse to use what is there. Absence of a name is the honest trigger:
  the module renders one precisely when nobody else has.
- **Two modes, and no flag** ([§4.4](../../CONSTITUTION.md)). Naming a Secret and asking for one
  are the same input in two states, so there is no second knob that can disagree with the first —
  and no configuration in which a module both renders a placeholder and points somewhere else.

## Consequences

- **Pruning now deletes credentials — in the rendered mode only.** Removing a module block removes
  the Secret it declared, where a hand-created one used to survive. Every environment's values are
  recoverable only from wherever the operator keeps them, which is nowhere this repository knows
  about. Naming an existing Secret is the way to keep a credential outside that lifecycle, and it
  is worth knowing that before the first `destroy`, not after.
- **Two paths through every credential, and the difference is invisible in the cluster.** A filled
  placeholder and a hand-made Secret are the same object; only its owner references differ. What
  says which is in play is the module's input, so a spec that shows only one path is incomplete.
- **Self-heal repairs a missing object and never a wrong value.** A typo authenticates as nobody,
  forever, and nothing reconciles it. The reconciliation guarantee stops precisely at the field
  that was ignored.
- **An empty Secret starts a workload that cannot work.** Between the sync and the fill, pods
  crash-loop or fail to authenticate; afterwards they need a rollout restart, because an
  environment variable read from a Secret does not reload. First run is sync, fill, restart, and
  a spec that does not say so is incomplete.
- **This does not solve secret storage and does not reopen [REQ-04](../requirements.md).** The
  value still lives in etcd, unencrypted at rest under k3s defaults, and in the operator's head.
  Nothing backs it up and nothing rotates it. What changed is that the *object* is declared, not
  that the secret is managed.
- **A directory under `modules/` is not a capability**, which weakens §2.1's naming rule by
  exactly one exception. `secret-template` has no spec, because it designs nothing and decides
  nothing; what it is, is here.
- **A module now imports a module.** Nesting is one level and stays there: a module that imported
  something rendering resources would render two `ApplicationSet`s, which is why this one renders
  none.
- **This repository becomes a source Argo CD must read** in any environment shipping any module
  with a credential — previously true only where the certificate module shipped. The chart is
  read from git at the caller's `git_revision`, so a branch that has not been pushed is an
  Application pointing at a path that does not exist.
- **The open question is half answered.** What creates the Secrets: this does, whenever nobody
  else has. What supplies their contents: still nothing, still a person, still unrecorded.
