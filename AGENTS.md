# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, etc.) working in this repository.

This file holds only what an implementer must not get wrong. Everything else is documented
once, elsewhere, and linked — do not restate it here.

| For | Read |
| --- | --- |
| What has to be true, and why | [docs/requirements.md](docs/requirements.md) |
| The domain model and shared contracts | [docs/platform.md](docs/platform.md) |
| A specific module | `docs/modules/<module>/README.md` and its `adr/` |
| Why a platform-wide choice was made | [docs/adr/](docs/README.md#decisions) |
| Doc conventions, ID schemes, statuses | [docs/README.md](docs/README.md#conventions) |
| How to run anything | [README.md](README.md#layout) |

## Repository structure

```
root.hcl                       provider + remote_state generation, included by every unit
_envcommon/<module>.hcl        inputs shared by a module across environments
<env>/
  env.hcl                      cluster endpoint, hostnames, database host/port
  <unit>/terragrunt.hcl        includes root.hcl and _envcommon; holds only the deltas
modules/<capability>-<impl>/   the Terraform, plus helm/<chart>/ for any chart it authors
dependencies/<name>/           not part of the platform — see below
docs/                          requirements, specs, decisions
```

Specs come first. `docs/` is the only part with substance today and no module's Terraform
exists yet, so work here is writing and refining requirements, specs and ADRs ahead of code.

**`dependencies/` is not part of the platform, and deliberately has no ADR.** It holds what the
stack needs but does not own — `dependencies/postgresql` today. Each is one directory with its
own `.iac/`, its own values, and a `helm/` where this repo had to author a chart; applied with
plain OpenTofu, with no Terragrunt, no `_envcommon` and no per-environment unit. Nothing in
there is a capability, none of it appears in the module catalogue, and none of it is named
`<capability>-<implementation>`. It exists because these things had to run somewhere and there
was already a cluster. **Don't apply module conventions to it, don't give it an ADR, and don't
promote it into a module.**

## Workflow: requirements → ADRs → specs → code

1. A requirement (`REQ-NN`) says what must be true, independent of implementation. New ones go
   in [docs/requirements.md](docs/requirements.md), with a row in its traceability matrix.
2. An ADR resolves how, and records what it cost. One decision per ADR. Platform-wide ADRs go
   in `docs/adr/` with a global number; module-scoped ones go in
   `docs/modules/<module>/adr/` as `LOCAL-NNN`.
3. A spec designs it and states acceptance criteria as tagged, IDed Gherkin scenarios.
4. Code implements the spec and cites the ADRs it follows.

**Before changing a module, read its `README.md` and every ADR it links** — its own `LOCAL-`
ones and the platform ADRs it obeys. Before changing a convention below, read the ADR that
established it; the consequences section is usually why the convention looks odd.

**Scope test for a new ADR:** if reversing this decision would change code outside the module,
it is platform-wide. ADR 004 is the trap — it reads like an observability decision and is
platform-wide, because it is why every module declares scraping through its chart.

## Conventions every module follows

Load-bearing decisions from the ADRs. Violating one is a regression, not a style choice.

- **Modules are named `<capability>-<implementation>`** (e.g. `openid-connect-zitadel`), and
  their outputs stay implementation-neutral (`issuer_url`, not `zitadel_org_id`) so swapping
  the implementation doesn't touch consumers. [zitadel LOCAL-001]
- **Every module renders its own Argo CD `ApplicationSet`** — a `List` generator with one
  static entry per chart the module needs, even when that's a single entry. There is no shared
  `ApplicationSet` module, and no module ever creates a bare `Application` directly. [ADR 005]
- **Every consumer module takes the same three optional inputs**, each defaulting to `null`
  (meaning "not wired", never "disabled by a flag"): `gateway`, `database`, `oidc`. [ADR 007]
- **Each chart's generated Argo CD `Application` owns every resource it needs, including its
  route — Terraform never creates a bare Kubernetes object.** Prefer the workload's own chart
  when it already renders what's needed (native, e.g. Grafana's `route.main`, Zitadel's
  `gateway.httpRoute`); wrap it with a local chart that adds a Helm dependency plus one
  template when it doesn't (wrapped); author a local chart from scratch when there's no
  upstream chart at all (custom — e.g. Auditum). [ADR 010]
- **Credentials are passed by reference, never by value**: `var.database` and `var.oidc` carry
  a Secret name plus a key, never a password or client secret. Nothing sensitive reaches a
  values.yaml or the rendered Helm values inside an `Application` spec in etcd. [ADR 007]
- **Providers publish addresses; they don't know their consumers.**
  `openid-connect-zitadel` outputs only `issuer_url`/`discovery_url` — it registers no OIDC
  clients and holds no client secrets. Client registration happens by hand in Zitadel's
  console until roughly fifteen clients. [ADR 007]
- **A module declares what it needs, not when it is satisfied.** A `secret_name` or a
  `host_port` names something this repo may not provision. Who creates it, and in what order,
  is operational — do not encode ordering or dependency-checking into a module. [ADR 007]
- **PostgreSQL is external** — never provisioned by this repo. A consumer needing a database
  just gets `var.database` pointing at one that already exists, described per environment.
  [ADR 008]
- **Scrape config goes through Prometheus-operator CRDs** (`ServiceMonitor`/`PodMonitor`), read
  directly by the collector — a workload declares scraping through its own chart's
  `serviceMonitor.enabled`, never through hand-written scrape config or a vendor-specific
  equivalent. Chartless workloads like Auditum are the exception and need a `ServiceMonitor`
  written by hand. The observability module installs the CRD bundle. [ADR 004]
- **What a person may do comes from the token.** A consumer wired to `oidc` reads roles named
  `<SLUG>_ADMIN`/`<SLUG>_VIEWER` from `resource_access.<slug>.roles`, maps them to its own
  native roles, and **refuses anyone carrying none** — never falls back to a default role.
  [ADR 013]
- **A chart this repo authors lives at `helm/<chart-name>/` inside the module that owns it.**
  Wrapped or custom, same place. [ADR 010]
- **Chart versions are pinned exactly.** An upgrade is a deliberate edit, which is what keeps
  a native chart's values schema from changing underneath a module silently. [ADR 010]
- **Nothing in this repo creates the Secrets that `var.database` and `var.oidc` reference.**
  They are made by hand, per environment. Don't write a module that assumes otherwise, and
  don't add ordering or existence checks to compensate. [ADR 007]

## Environments

- **An environment is a cluster with its own Argo CD.** Nothing is shared between them, and
  configuration is per environment. [ADR 011]
- **An environment ships a module by having a unit directory for it** — no enable flags, no
  inventory file. Don't add one.
- **Shared inputs live in `_envcommon/<module>.hcl`; only deltas go in the environment's
  unit.** Don't copy a full config into each environment.
- **Never widen a module's blast radius past its environment.** A module addresses its own
  cluster; nothing reaches across. [REQ-12]
- **State is per environment**, generated by Terragrunt in `root.hcl` from `env.hcl`. The
  backend is not settled — treat `.tfstate/` as provisional. [ADR 012]

## Trade-offs to respect

A tiny k3s cluster per environment, one operator across all of them, weeks of neglect. See
[README § Rationale](README.md#rationale).

**Don't propose HA, multi-replica or tuning changes unless asked** — they cut against the
repo's stated intent, and the cost is paid every day, in every environment, on nodes with a
finite amount of RAM.

## Blocked and undecided

- `audit-management-auditum` is **blocked** on an open question — application audit trails vs.
  Kubernetes API audit logs. See
  [its Blocking question](docs/modules/audit-management-auditum/README.md#blocking-question).
  Don't build it out further without resolving that; if the answer is the second one, the
  module should not exist.
- One ADR is **`proposed`, meaning the decision has not been made**:
  [ADR 012](docs/adr/012-state-is-per-environment.md) — per-environment state is settled, the
  backend is not. Don't implement it as though it were settled, and don't quietly pick one.
- **There is no secret manager.** REQ-04 was dropped along with the module that satisfied it,
  so every `secret_name` in the repo names something created by hand. Don't reintroduce one
  without a requirement above it.
