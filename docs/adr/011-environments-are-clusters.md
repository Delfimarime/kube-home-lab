# 011. An environment is a cluster

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-09 ·
revised 2026-08-15 (the layering half is superseded by
[ADR 020](020-one-root-module.md); the definition is not)

> **What survives.** An environment is a Kubernetes cluster with its own Argo CD, nothing is
> shared between them, and the consequences below still hold. **What does not:** environments
> are no longer directories, and there is no Terragrunt. The tree is one root module; the
> cluster is whichever one the shell's `ARGOCD_SERVER` names. The comparison table below is kept
> because its verdict on *one cluster, namespace per environment* is unchanged — but its verdict
> on workspaces rested on "no per-environment provider", which
> [ADR 020](020-one-root-module.md) shows to be false for a provider that reads its address from
> the environment.

## Context

This started as one cluster and is now several. They have to be configurable independently
and must not interfere with one another ([REQ-12](../requirements.md)). Terragrunt is
already the tool for the monorepo; the open question is what an environment *is*, and where
that dimension sits in the tree.

## Options

| | Isolation | Per-environment provider | Notes |
| --- | --- | --- | --- |
| **Directory layering** | separate clusters | yes, from `env.hcl` | Terragrunt's own recommended structure |
| OpenTofu workspaces | one state, one backend | no — one provider config | A workspace is not a cluster |
| One cluster, namespace per environment | none worth the name | n/a | One API server, one Argo CD, one failure domain |

## Decision

**An environment is a Kubernetes cluster with its own Argo CD.** Nothing is shared between two
of them: not the API server, not Argo CD, not the failure domain.

**An environment ships a module by having a `module` block for it** in the root module. There is
no enable flag and no inventory file — the root module is the list, and it cannot drift from
what is deployed because it *is* what is deployed ([ADR 020](020-one-root-module.md)).

## Rationale

- Separate clusters are the strongest isolation available and cost nothing to state.
  Namespaces in one cluster share an API server, an Argo CD and a failure domain, which
  would make REQ-12 a promise instead of a property.
- Workspaces share one backend and one provider configuration — which read as disqualifying
  when this was written, and does not any more: the provider takes its address from the
  environment, so a workspace is a viable second cluster ([ADR 020](020-one-root-module.md)).
- The composition *is* the inventory, so the recorded module list cannot drift from the
  deployed one.

## Consequences

- Every module an environment ships runs in that environment's cluster. N environments means
  N Keycloaks, N Grafanas — and N copies of any per-instance problem, operated N times by the
  same one person.
- **Identities are per environment.** Each cluster runs its own issuer, so an account in one
  is not an account in another. [REQ-01](../requirements.md) is scoped accordingly.
  Federating them is machinery this lab does not need.
- **Modules are not versioned per environment.** This is a monorepo, so the root module
  references `source = "./modules/<m>/tofu"` — a local path, not a versioned git ref. Every
  environment runs whatever the checkout holds, so there is no validating a change in one
  environment first. Accepted: few environments, one operator. The escape hatch is a git ref in
  `source`, which changes no module's contract.
- Argo CD, Traefik and PostgreSQL are per-environment prerequisites now rather than single
  ones. Each stays out of scope ([ADR 008](008-postgresql-is-external.md), platform spec).
- Hostnames are per environment and live in that environment's var file.
  [ADR 007](007-modules-receive-credentials.md)'s "defined once" consequence still holds —
  once *per environment*.
- REQ-12 covers everything this repo provisions. A PostgreSQL server shared between
  environments sits outside that guarantee, and nothing here prevents one.
