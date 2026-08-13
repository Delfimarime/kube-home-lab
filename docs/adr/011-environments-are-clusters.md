# 011. An environment is a cluster; Terragrunt layers them

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-09

## Context

This started as one cluster and is now several. They have to be configurable independently
and must not interfere with one another ([REQ-12](../requirements.md)). Terragrunt is
already the tool for the monorepo; the open question is what an environment *is*, and where
that dimension sits in the tree.

## Options

| | Isolation | Per-environment provider | Notes |
| --- | --- | --- | --- |
| **Directory layering** | separate clusters | yes, from `env.hcl` | Terragrunt's own recommended structure |
| Terraform workspaces | one state, one backend | no — one provider config | A workspace is not a cluster |
| One cluster, namespace per environment | none worth the name | n/a | One API server, one Argo CD, one failure domain |

## Decision

**An environment is a Kubernetes cluster with its own Argo CD.** Environments are
directories, following Terragrunt's standard layout with the region tier collapsed — each
environment is exactly one cluster, so there is nothing for that tier to distinguish.

```
root.hcl                      provider + remote_state generation, included by every unit
_envcommon/<module>.hcl       inputs shared by a module across environments
<env>/
  env.hcl                     cluster endpoint, hostnames, database host/port
  <unit>/terragrunt.hcl       includes root.hcl and _envcommon/<module>.hcl; holds the deltas
modules/<capability>-<impl>/  the Terraform
```

**An environment ships a module by having a unit directory for it.** There is no enable
flag and no inventory file: `ls <env>/` is the answer.

## Rationale

- Separate clusters are the strongest isolation available and cost nothing to state.
  Namespaces in one cluster share an API server, an Argo CD and a failure domain, which
  would make REQ-12 a promise instead of a property.
- Workspaces share one backend and one provider configuration — precisely what cannot be
  shared when the provider addresses a different cluster per environment.
- `_envcommon` keeps "identical everywhere" in one file while an environment's unit holds
  only what differs, so adding an environment is a directory plus its deltas.
- Directory-as-inventory means the recorded module list cannot drift from the deployed one,
  because there is no recorded list.

## Consequences

- Every module an environment ships runs in that environment's cluster. N environments means
  N Zitadels, N Grafanas — and N copies of any per-instance problem, operated N times by the
  same one person.
- **Identities are per environment.** Each cluster runs its own issuer, so an account in one
  is not an account in another. [REQ-01](../requirements.md) is scoped accordingly.
  Federating them is machinery this lab does not need.
- **Modules are not versioned per environment.** This is a monorepo, so units reference
  `source = "../../modules/<m>"` — a local path, not a versioned git ref. Every environment
  runs the same module code and a change reaches all of them at once; there is no validating
  it in one environment first. Accepted for now: few environments, one operator. The escape
  hatch is pinning `source` to a git ref per environment, which changes no module's contract.
- Argo CD, Traefik and PostgreSQL are per-environment prerequisites now rather than single
  ones. Each stays out of scope ([ADR 008](008-postgresql-is-external.md), platform spec).
- Hostnames are per environment and live in `env.hcl`.
  [ADR 007](007-modules-receive-credentials.md)'s "defined once" consequence still holds —
  once *per environment*.
- REQ-12 covers everything this repo provisions. A PostgreSQL server shared between
  environments sits outside that guarantee, and nothing here prevents one.
