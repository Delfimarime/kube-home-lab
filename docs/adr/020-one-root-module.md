# 020. There is one root module, and no Terragrunt

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-15 ·
supersedes the layering half of [ADR 011](011-environments-are-clusters.md) and all of
[ADR 015](015-units-are-wired-by-hand.md)

## Context

[ADR 011](011-environments-are-clusters.md) put Terragrunt between the operator and OpenTofu:
`root.hcl` generating a provider and a backend, `_envcommon/<module>.hcl` composing a module's
inputs, `env.hcl` per cluster, and a `terragrunt.hcl` per unit. Built out, that was four files
of scaffolding for one cluster and one module, and it carried semantics of its own — an
`include` merges inputs shallowly, per top-level key, so a unit overriding one field of an
object silently drops the rest.

Two of the three things it bought turned out to be paid for elsewhere.

**The provider was never per-directory.** It reads `ARGOCD_SERVER` and `ARGOCD_AUTH_TOKEN` from
the operator's environment, so it addresses whichever cluster the shell names — the directory
tree was describing a choice the shell was already making. ADR 011 rejected OpenTofu workspaces
partly on the grounds that they offer "no per-environment provider configuration"; that reason
does not survive contact with a provider that takes its address from the environment.

**`_envcommon` existed to work around the merge.** Composing a module's whole input from
`env.hcl`, so no unit ever needed a partial override, was the mitigation for a hazard Terragrunt
introduced and plain OpenTofu does not have.

The third — one state per unit, so a plan touches one module — is real, and is the cost below.

## Decision

**No Terragrunt.** A root module at the repository root composes the cluster: one `module` block
per capability, `source = "./modules/<capability>-<impl>"`.

**The environment is the shell, not the tree.** `ARGOCD_SERVER` and `ARGOCD_AUTH_TOKEN` select
the cluster, `-backend-config` selects its state, `-var-file` supplies its values. There is no
per-environment directory, no `env.hcl` and no unit.

**Modules are wired by reference.** A value one module publishes and another consumes is
`module.<a>.<output>` in the root module — resolved at plan time, in one graph.

## Rationale

- **It removes a layer without removing a capability.** Four scaffolding files, a generated
  `provider.tf`, a generated `backend.tf`, `.terragrunt-cache`, and include-merge semantics
  become five `.tf` files at the root that say the same thing in the language everything else
  here is already written in.
- **It makes wiring correct rather than careful.**
  [ADR 015](015-units-are-wired-by-hand.md) settled for addresses written down by hand and
  admitted the cost in its own consequences: *"A hand-written address can disagree with
  reality… its reasoning is now weaker than when it was written."* A direct module reference
  cannot disagree with reality, needs no `mock_outputs`, and reads no state file. This is the
  decision's largest gain and it is a correctness gain, not a convenience one.
- **One plan describes the cluster.** `tofu plan` shows every module at once instead of
  `run --all` across units, which is what an operator returning after weeks actually wants to
  read.
- **The scale never justified the machinery.** One cluster, five modules, one operator. The
  layering was sized for a fleet.

## Consequences

- **[REQ-12](../requirements.md) stops being structural and becomes operational.** Terragrunt's
  per-directory backend made "a plan cannot see another environment" a property of the tree.
  Now a shell holding one cluster's `ARGOCD_SERVER` and another's `PG_CONN_STR` will plan
  something incoherent, and nothing warns. **Export all three together, per environment, or not
  at all.** This is the price of the decision and it is not mitigated anywhere in the repo.
- **A second environment is a workspace, not a directory.** `tofu workspace new <env>` plus its
  own var file; the `pg` backend keys state by workspace name, so the states stay apart with no
  re-`init`. Untested — there is one cluster — and it is the escape hatch, not the current
  design.
- **One state, one blast radius.** A plan touches every module the cluster ships, so a
  cert-manager change is applied in the same breath as everything else. `-target` narrows it and
  is a smell every time. Per-unit state was the one thing Terragrunt genuinely provided here.
- **Losing state loses all of it**, rather than one unit's. Unchanged in kind from
  [ADR 012](012-state-is-per-environment.md) — state describes `ApplicationSet`s and nothing
  unique, so re-applying regenerates it — but larger in degree.
- **`.terraform.lock.hcl` belongs in git now.** Terragrunt regenerated it inside a cache
  directory, so ignoring it cost nothing; for a root module it is what pins provider versions
  across machines, and ignoring it would quietly undo
  [ADR 010](010-resources-delivered-via-chart.md)'s "pinned exactly" for providers.
- **The root module is a place for logic, and should not become one.** It composes and wires.
  Anything that renders a resource belongs in a module — the rule that a module is the only
  thing that creates an `ApplicationSet` ([ADR 005](005-modules-are-applicationsets.md)) is now
  the only thing keeping the root from growing into the platform.
- **Modules stay independently plannable.** Each still declares its own `required_providers` and
  no `provider` block, so `tofu init -backend=false` in a module's directory validates it and
  exercises its `validation` blocks with no cluster and no database. That is the offline check,
  and it did not depend on Terragrunt.
