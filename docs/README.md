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
  platform.md                  the system: domain model, components, mechanisms, contracts
  adr/NNNN-*.md                platform-wide decisions
  modules/<module>/
    README.md                  the module spec
    adr/LOCAL-NNN-*.md         decisions scoped to that module
```

Start at [requirements.md](requirements.md) if you are new. Start at a module's folder if you
are about to change that module — its spec, its decisions and (later) its OpenTofu are all
in the one place.

There is deliberately no fifth "one page compiling all four" document. Such a page restates,
which every file here is forbidden from doing, so it drifts by construction and then disagrees
with the layer that is actually correct.

## Specifications

| Spec | Covers |
| --- | --- |
| [platform](platform.md) | the domain model, the six mechanisms that span modules, the contracts, environments |
| [certificate-management-cert-manager](modules/certificate-management-cert-manager/README.md) | the lab's certificate authorities, its wildcard, its client certificate, its trust bundle |
| [observability-storage-grafana-lgtm](modules/observability-storage-grafana-lgtm/README.md) | collecting metrics, logs and traces, storing them, and their tenants |
| [observability-console-grafana](modules/observability-console-grafana/README.md) | reading them — one Grafana, its roles and its alerting |
| [object-storage-rustfs](modules/object-storage-rustfs/README.md) | one S3-compatible endpoint, for workloads whose supported backend is an object store |
| [openid-connect-keycloak](modules/openid-connect-keycloak/README.md) | the OIDC issuer |
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
| [010](adr/010-resources-delivered-via-chart.md) | Resources are chart-delivered; OpenTofu creates no bare manifests | accepted |
| [011](adr/011-environments-are-clusters.md) | An environment is a cluster | accepted, layering superseded by 20 |
| [012](adr/012-state-is-per-environment.md) | State is per environment, and lives in PostgreSQL | accepted |
| [013](adr/013-roles-are-carried-in-the-token.md) | Roles are `<SLUG>_<ROLE>`, carried in the token | accepted |
| [014](adr/014-exposed-does-not-mean-authorized.md) | Exposed does not mean authorized | accepted |
| [015](adr/015-units-are-wired-by-hand.md) | Units are wired by hand; no unit reads another's state | superseded by 20 |
| [016](adr/016-metrics-is-the-fourth-input.md) | `metrics.enabled` is the fourth cross-module input | accepted, the root variable superseded by 24 |
| [017](adr/017-stores-are-multi-tenant.md) | The stores are multi-tenant; the caller names its tenant | accepted |
| [018](adr/018-one-trust-bundle-for-the-cluster.md) | One trust bundle for the cluster, not a mount per workload | accepted |
| [019](adr/019-the-tool-is-opentofu.md) | The tool is OpenTofu; "Terraform" means the language | accepted |
| [020](adr/020-one-root-module.md) | There is one root module, and no Terragrunt | accepted |
| [021](adr/021-code-does-not-cite-documentation.md) | Code does not cite documentation | accepted |
| [022](adr/022-secrets-are-rendered-empty.md) | A module renders the Secret it needs, empty, unless it is given one | accepted |
| [023](adr/023-a-modules-opentofu-is-at-its-root.md) | A module's OpenTofu is at its root, not under `tofu/` | accepted |
| [024](adr/024-the-metrics-fact-is-derived.md) | The metrics fact is derived at the root, not declared | accepted |

**Module-scoped** — reversing one changes nothing outside its module.

| ADR | Decision | Status |
| --- | --- | --- |
| [cert-manager LOCAL-001](modules/certificate-management-cert-manager/adr/LOCAL-001-certificates-from-an-internal-ca.md) | Certificates come from an internal CA, not a public one | accepted |
| [cert-manager LOCAL-002](modules/certificate-management-cert-manager/adr/LOCAL-002-one-certificate-per-authority.md) | One certificate per authority; no client list | accepted |
| [keycloak LOCAL-001](modules/openid-connect-keycloak/adr/LOCAL-001-oidc-provider-keycloak.md) | OIDC provider is Keycloak, deployed by its operator | accepted |
| [object-storage LOCAL-001](modules/object-storage-rustfs/adr/LOCAL-001-rustfs-standalone.md) | The object store is RustFS, running standalone | accepted |
| [observability-storage LOCAL-001](modules/observability-storage-grafana-lgtm/adr/LOCAL-001-grafana-lgtm-stack.md) | The Grafana stack, three single-binary components | accepted |
| [observability-storage LOCAL-002](modules/observability-storage-grafana-lgtm/adr/LOCAL-002-mimir-monolithic-chart.md) | Mimir runs monolithic, from a chart this repo authors | accepted |
| [observability-storage LOCAL-003](modules/observability-storage-grafana-lgtm/adr/LOCAL-003-scrape-first-one-otlp-address.md) | Scrape first; one neutral address for the rest | accepted |
| [observability-storage LOCAL-004](modules/observability-storage-grafana-lgtm/adr/LOCAL-004-storage-split-from-console.md) | Storage splits from the console; the receiver gets a route | accepted |
| [observability-storage LOCAL-006](modules/observability-storage-grafana-lgtm/adr/LOCAL-006-stores-keep-their-data-in-an-object-store.md) | The three stores keep their data in an object store | accepted |
| [observability-storage LOCAL-007](modules/observability-storage-grafana-lgtm/adr/LOCAL-007-a-signal-is-its-own-configuration.md) | A signal is its own configuration; its presence is the switch | accepted |
| [observability-console LOCAL-001](modules/observability-console-grafana/adr/LOCAL-001-two-grafana-roles-strict.md) | Applying the role convention to Grafana | accepted |
| [observability-console LOCAL-002](modules/observability-console-grafana/adr/LOCAL-002-no-alerting.md) | No alerting | superseded by its LOCAL-003 |
| [observability-console LOCAL-003](modules/observability-console-grafana/adr/LOCAL-003-alerting-lives-in-grafana.md) | Alerting lives in Grafana, and in its database | accepted |

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

**A module ADR that wants to cite another module's is in the wrong place.** The citation is the
smell, not the offence: a decision whose reversal reaches a second module is platform-scoped by
[the scope test](../AGENTS.md#workflow-requirements--adrs--specs--code), so the fix is to lift
it rather than to link across. `ADR 017` and `ADR 018` were both lifted for exactly this reason
— tenancy was written as a storage decision and reaches the console; the trust bundle was
written as a certificate decision and reaches every consumer wired to `oidc`. Once lifted, the
modules that needed them cite a platform ADR, which was always allowed.

**One decision strains that**, and it is worth knowing where. `observability-storage-grafana-lgtm`
`LOCAL-001` argues for the Grafana stack *and* for Grafana as the query surface, so it covers
both observability modules. It is not lifted, because reversing it does not change the console —
it changes what the console *is*. It stays with the stores; the console spec restates the
pairing in prose rather than citing across. Splitting one coherent argument in half would have
cost more than the restatement does.

**Citation runs one way only: a module ADR may cite a platform ADR; a platform ADR never cites
a module one.** A platform decision that needed a module's reasoning to stand up would not be
platform-scoped — it would be a module decision with extra reach. Where a platform ADR wants to
name a consequence that lands in a module, it describes the consequence rather than linking to
where the module wrote it down.

**The traceability matrix is the one exception**, and the one place that cites across every
module. There, qualify a module ADR with its module name: `openid-connect-keycloak LOCAL-001`.

**Two module sequences have gaps too, for the opposite reason.**
`certificate-management-cert-manager` has no `LOCAL-003` and `observability-storage-grafana-lgtm`
has no `LOCAL-005`: both were lifted to the platform sequence as `ADR 018` and `ADR 017` on
2026-08-15. The numbers stay retired, so a citation to either in an older note resolves to
nothing rather than to the wrong decision.

**The global sequence has gaps at 001, 002, 003 and 009.** Those decisions moved into module
folders on 2026-08-09 and were renumbered `LOCAL-NNN`. The gaps are not closed: renumbering the
survivors would churn every citation to them for cosmetics, and the gaps usefully mark
decisions that turned out to be module-local.

**Scope is in the header, not only in the path**, so a file read on its own still says what it
constrains:

```
**Status:** accepted · **Scope:** platform · **Date:** 2026-08-05
**Status:** accepted · **Scope:** module — `observability-storage-grafana-lgtm` · **Date:** …
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
| *Prerequisites* | Optional. What must exist before it runs and who makes it — the `kubectl patch` filling each Secret, whether the module rendered it or was given one ([ADR 022](adr/022-secrets-are-rendered-empty.md)), the restart that follows, plus any Gateway configuration it references. Omit it only where there is nothing |
| Inputs | The HCL a caller writes |
| Outputs | What consumers read from it — addresses, never credentials |
| Acceptance criteria | Gherkin, one `Feature`, IDed and tagged scenarios |
| Open items | What is unresolved, and what it would cost to resolve |

`Prerequisites` is the one optional section with a fixed name and position, because two modules
already needed it and a third naming it something else would be the start of the drift this
table exists to prevent. It is where the Secret examples live: a new `secret_name` without one
is an incomplete change.

### Scenario IDs and tags

```gherkin
@plan
Scenario: [OBS-01] At least one component is required
```

The ID (`<MODULE>-<NN>`) is what the traceability matrix cites; it is never reused for a
different scenario. The tag says where the check can run:

- `@plan` — assertable against `tofu plan -json`, no cluster needed
- `@cluster` — needs the thing actually running

### Status

`draft` is being written and changes without ceremony. `proposed` means the decision is
written down but **not made** — no ADR currently holds it; ADR 012 did, until its backend was
chosen. `accepted` is agreed; changing it means changing its consequences too. `implemented` is
matched by code. `superseded` links its replacement in the header.

Every spec here is `draft` until its module is built and its `@cluster` criteria have run.

### Revising an ADR

**Revise in place only while nothing implements it.** ADRs 5, 6 and 7 were, on 2026-08-09,
because there is no code. Once a decision is implemented, changing it means a new ADR that
supersedes the old one — and the old one stays, because reasoning that turned out wrong is
worth keeping. ADR 006 is the worked example.

## Making the criteria executable

They are prose today, checked by hand. The path to executable is a policy tool such as
conftest asserting against `tofu plan -json` for the `@plan` scenarios, and `kubectl`
assertions for the `@cluster` ones. The tags exist so that harness can select its half without
anyone re-reading every file first.

The harness is not worth building before the modules exist. Tagging them now costs nothing and
is the part that would otherwise have to be retrofitted.
