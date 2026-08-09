# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex, etc.) when working with
code in this repository.

## What this repo is

Terragrunt/Terraform that provisions the *platform* layer of a homelab k3s cluster by
rendering Argo CD `Application` resources. Terraform never talks to a workload directly —
Argo CD installs and reconciles everything. Cluster bootstrap, Argo CD itself, Traefik/Gateway,
and PostgreSQL are all assumed to pre-exist and are out of scope.

## Current state

Only `docs/` exists. No `root.hcl`, no `modules/`, no `platform/` yet — see the layout section
in README.md. Work here today is mostly writing/refining specs (`docs/spec/`) and ADRs
(`docs/adr/`) ahead of code.

## Workflow: specs → ADRs → code

- `docs/spec/platform.md` — overall intent, scope, shared contracts.
- `docs/spec/modules/*.md` — one per module: inputs, outputs, Gherkin acceptance criteria.
- `docs/adr/NNNN-*.md` — one decision each, with consequences. A new significant decision gets
  a new ADR, not a rewrite of an old one.
- Code implements the specs and cites the ADRs it follows. Read a module's spec and its linked
  ADRs before writing or changing that module.

## Commands

No Terraform code exists yet, so there is nothing to build/lint/test today. Once units exist
under `platform/`:

```sh
export KUBECONFIG=~/.kube/config
terragrunt run --all plan               # plan everything
cd platform/<unit> && terragrunt apply  # apply one unit
```

Terraform >= 1.9 is required (variable `validation` blocks reference other variables). State is
a local file under `.tfstate/` (gitignored), holding nothing but Application specs.

## Architecture — conventions every module follows

These are load-bearing decisions from the ADRs; violating one is a regression, not a style
choice.

- **Modules are named `<capability>-<implementation>`** (e.g. `openid-connect-zitadel`), and
  their outputs stay implementation-neutral (`issuer_url`, not `zitadel_org_id`) so swapping
  the implementation doesn't touch consumers. [ADR 1]
- **Each module renders its own Argo CD `Application`** — there is no shared `argocd-app`
  module. ~25 lines of boilerplate repeated per module is the accepted cost of avoiding
  indirection. [ADR 5]
- **Every consumer module takes the same three optional inputs**, each defaulting to `null`
  (meaning "not wired", never "disabled by a flag"): `gateway`, `database`, `oidc`.
  [platform spec]
- **Each module emits its own `HTTPRoute`** as a `kubernetes_manifest` when `gateway` is set,
  using one variable shape everywhere (`name`, `namespace`, `hostname`, `section_name`). This
  route sits outside Argo CD's resource tree and is not self-healed by it. [ADR 6]
- **Credentials are passed by reference, never by value**: `var.database` and `var.oidc` carry
  a Secret name plus a key, never a password or client secret. Nothing sensitive reaches a
  values.yaml or the rendered Helm values inside an `Application` spec in etcd. [ADR 7]
- **Providers publish addresses; they don't know their consumers.**
  `openid-connect-zitadel` outputs only `issuer_url`/`discovery_url` — it registers no OIDC
  clients and holds no client secrets. Client registration happens by hand in Zitadel's console
  until roughly fifteen clients. [ADR 7]
- **PostgreSQL is external** — never provisioned by this repo. A consumer needing a database
  just gets `var.database` pointing at one that already exists. [ADR 8]
- **Scrape config goes through Prometheus-operator CRDs** (`ServiceMonitor`/`PodMonitor`),
  converted by the VictoriaMetrics operator — not hand-written `VMServiceScrape`, except for
  chartless workloads like Auditum, which need one written by hand. [ADR 4]
- **Secret delivery is OpenBao + External Secrets Operator**: OpenBao stores, ESO materializes
  a real Secret via a `ClusterSecretStore`/`ExternalSecret`. Bootstrap order is always
  secrets → identity → everything else. [ADR 9, platform spec]

## Rationale that shapes trade-offs

One replica of everything, short retention, upstream Helm defaults over tuning, no service
mesh — this is a one-node, one-tenant homelab, not a production HA design (see README.md
Rationale). Don't propose HA/multi-replica/tuning changes unless asked; they cut against the
repo's stated intent.

## Module reference

| Module | Provides | Consumes | Spec | Key ADRs |
| --- | --- | --- | --- | --- |
| `secret-manager-openbao` | OpenBao + ESO | — | [spec](docs/spec/modules/secret-manager-openbao.md) | 9 |
| `openid-connect-zitadel` | `issuer_url`, `discovery_url` | `database`, `gateway` | [spec](docs/spec/modules/openid-connect-zitadel.md) | 1, 7 |
| `observability-victoria-metrics` | metrics/logs/traces + Grafana | `gateway`, `oidc` | [spec](docs/spec/modules/observability-victoria-metrics.md) | 2, 3, 4 |
| `audit-management-auditum` | audit record API | `database`, `gateway` | [spec](docs/spec/modules/audit-management-auditum.md) | 8 |

`audit-management-auditum` is blocked on an open question (application audit trails vs.
Kubernetes API audit logs — see its spec's "Blocking question" section) — don't build it out
further without resolving that first.
