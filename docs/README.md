# Documentation

Four layers, each answering a different question. Nothing is restated across them; a fact
lives in exactly one and the others link to it.

| Layer | Answers | Where |
| --- | --- | --- |
| Requirements | What has to be true, regardless of implementation | [requirements.md](requirements.md) |
| Specifications | How it is solved, and how you tell it worked | [platform.md](platform.md), [modules/](#specifications) |
| Decisions | Why this way, what it cost, when to revisit | [adr/](#decisions), and each module's own `adr/` |
| Agent guidance | The rules an implementer must not violate | [AGENTS.md](../AGENTS.md) |

```
docs/
  requirements.md              REQ-NN, the problem, and the traceability matrix
  platform.md                  domain model, scope, contracts, cross-module criteria
  adr/NNNN-*.md                platform-wide decisions
  modules/<module>/
    README.md                  the module spec
    adr/LOCAL-NNN-*.md         decisions scoped to that module
```

Start at [requirements.md](requirements.md) if you are new. Start at a module's folder if you
are about to change that module — its spec, its decisions and (later) its Terraform are all
in the one place.

## Specifications

| Spec | Covers |
| --- | --- |
| [platform](platform.md) | domain model, assumptions, the `gateway`/`database`/`oidc` contracts, environments |
| [observability-grafana-lgtm](modules/observability-grafana-lgtm/README.md) | metrics, logs, traces, Grafana |
| [openid-connect-zitadel](modules/openid-connect-zitadel/README.md) | the OIDC issuer |
| [audit-management-auditum](modules/audit-management-auditum/README.md) | audit record API — blocked |

## Decisions

**Platform-wide** — reversing one of these changes every module.

| ADR | Decision | Status |
| --- | --- | --- |
| [004](adr/004-scrape-config-via-prometheus-crds.md) | Scrape config through Prometheus operator CRDs | accepted |
| [005](adr/005-modules-are-applicationsets.md) | Modules are ApplicationSets, not Applications | accepted |
| [006](adr/006-shared-gateway-input.md) | One `gateway` input shape | superseded by 7 |
| [007](adr/007-modules-receive-credentials.md) | Module input contracts; providers publish addresses | accepted |
| [008](adr/008-postgresql-is-external.md) | PostgreSQL is external to this project | accepted |
| [010](adr/010-resources-delivered-via-chart.md) | Resources are chart-delivered; Terraform creates no bare manifests | accepted |
| [011](adr/011-environments-are-clusters.md) | An environment is a cluster; Terragrunt layers them | accepted |
| [012](adr/012-state-is-per-environment.md) | State is per environment, and belongs in its own cluster | **proposed** |
| [013](adr/013-roles-are-carried-in-the-token.md) | Roles are `<SLUG>_<ROLE>`, carried in the token | accepted |

**Module-scoped** — reversing one changes nothing outside its module.

| ADR | Decision | Status |
| --- | --- | --- |
| [zitadel LOCAL-001](modules/openid-connect-zitadel/adr/LOCAL-001-oidc-provider-zitadel.md) | OIDC provider is Zitadel | accepted |
| [observability LOCAL-001](modules/observability-grafana-lgtm/adr/LOCAL-001-grafana-lgtm-stack.md) | The Grafana stack, three single-binary components | accepted |
| [observability LOCAL-002](modules/observability-grafana-lgtm/adr/LOCAL-002-mimir-monolithic-chart.md) | Mimir runs monolithic, from a chart this repo authors | accepted |
| [observability LOCAL-003](modules/observability-grafana-lgtm/adr/LOCAL-003-scrape-first-one-otlp-address.md) | Scrape first; one neutral address for the rest | accepted |
| [observability LOCAL-004](modules/observability-grafana-lgtm/adr/LOCAL-004-no-alerting.md) | No alerting | accepted |
| [observability LOCAL-005](modules/observability-grafana-lgtm/adr/LOCAL-005-two-grafana-roles-strict.md) | Applying the role convention to Grafana | accepted |

Which requirement each decision serves is in the
[traceability matrix](requirements.md#traceability).

## Conventions

### ADR numbering

**Numbers are always three digits, zero-padded** — `007`, not `7` — in filenames, titles and
citations alike. Padding is what keeps `ls` and any future sort in numeric order past ninety-
nine, and it makes an ADR reference recognisable on sight.

**Platform ADRs use a global sequence, unprefixed:** `ADR 007`, in `007-<slug>.md`. **Module
ADRs restart at 001 per module and carry the `LOCAL-` prefix:** `LOCAL-001`, in
`LOCAL-001-<slug>.md`. A module ADR is local to its module — no module cites another module's
ADR, and none should need to.

**Citation runs one way only: a module ADR may cite a platform ADR; a platform ADR never cites
a module one.** A platform decision that needed a module's reasoning to stand up would not be
platform-scoped — it would be a module decision with extra reach. Where a platform ADR wants to
name a consequence that lands in a module, it describes the consequence rather than linking to
where the module wrote it down.

**The traceability matrix is the one exception**, and the one place that cites across every
module. There, qualify a module ADR with its module name: `openid-connect-zitadel LOCAL-001`.

**The global sequence has gaps at 001, 002, 003 and 009.** Those decisions moved into module
folders on 2026-08-09 and were renumbered `LOCAL-NNN`. The gaps are not closed: renumbering the
survivors would churn every citation to them for cosmetics, and the gaps usefully mark
decisions that turned out to be module-local.

**Scope is in the header, not only in the path**, so a file read on its own still says what it
constrains:

```
**Status:** accepted · **Scope:** platform · **Date:** 2026-08-05
**Status:** accepted · **Scope:** module — `observability-grafana-lgtm` · **Date:** …
```

### Module specs

**Every module spec has at least these sections, in this order.** A missing one is a gap, not
a style choice. Extra sections are fine where a module earns one — Auditum has a *Blocking
question* and a *Security note*, and both are the most important things on the page.

| Section | Contains |
| --- | --- |
| Header | `Status`, `Satisfies` (REQ ids), `Decisions` (its `LOCAL-NNN` plus the platform ADRs it obeys) |
| Intent | What this module is for, in a few sentences |
| Provisions | What it creates: Applications, charts, resources |
| Inputs | The HCL a caller writes |
| Outputs | What consumers read from it — addresses, never credentials |
| Acceptance criteria | Gherkin, one `Feature`, IDed and tagged scenarios |
| Open items | What is unresolved, and what it would cost to resolve |

### Scenario IDs and tags

```gherkin
@plan
Scenario: [OBS-01] At least one component is required
```

The ID (`<MODULE>-<NN>`) is what the traceability matrix cites; it is never reused for a
different scenario. The tag says where the check can run:

- `@plan` — assertable against `terraform plan -json`, no cluster needed
- `@cluster` — needs the thing actually running

### Status

`draft` is being written and changes without ceremony. `proposed` means the decision is
written down but **not made** — see ADR 012. `accepted` is agreed; changing it means changing
its consequences too. `implemented` is matched by code. `superseded` links its replacement in
the header.

Every spec here is `draft`: no module's Terraform exists yet.

### Revising an ADR

**Revise in place only while nothing implements it.** ADRs 5, 6 and 7 were, on 2026-08-09,
because there is no code. Once a decision is implemented, changing it means a new ADR that
supersedes the old one — and the old one stays, because reasoning that turned out wrong is
worth keeping. ADR 006 is the worked example.

## Making the criteria executable

They are prose today, checked by hand. The path to executable is a policy tool such as
conftest asserting against `terraform plan -json` for the `@plan` scenarios, and `kubectl`
assertions for the `@cluster` ones. The tags exist so that harness can select its half without
anyone re-reading every file first.

The harness is not worth building before the modules exist. Tagging them now costs nothing and
is the part that would otherwise have to be retrofitted.
