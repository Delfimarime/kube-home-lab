# Documentation

Five layers, each answering a different question and each owning a different *kind* of statement.

| Layer | Answers | Where |
| --- | --- | --- |
| Requirements | What has to be true, regardless of implementation | [requirements.md](requirements.md) |
| Decisions | Why this way, what it cost, when to revisit | [adr/](#decisions), and each module's own `adr/` |
| Rules | What an implementer must not break | [CONSTITUTION.md](../CONSTITUTION.md) |
| Specifications | How it is solved, and how you tell it worked | [platform.md](platform.md), [modules/](#specifications) |
| Orientation | Where things are, and what is currently blocked | [AGENTS.md](../AGENTS.md) |

```
CONSTITUTION.md                the rules, each citing the decision behind it
AGENTS.md                      orientation and live state; holds no rules
docs/
  requirements.md              REQ-NN, the problem, and the traceability matrix
  platform.md                  the system: domain model, components, joints, contracts
  adr/NNN-*.md                 platform-wide decisions
  modules/<module>/
    README.md                  the module spec
    adr/LOCAL-NNN-*.md         decisions scoped to that module
```

Start at [requirements.md](requirements.md) if you are new. Start at a module's folder if you
are about to change that module — its spec, its decisions and its OpenTofu are all in the one
place.

## What may be repeated, and what may not

**One fact legitimately appears in more than one layer, because the layers make different kinds
of claim about it.** That one module renders one `ApplicationSet` is a *decision* in
[ADR 005](adr/005-modules-are-applicationsets.md), an *imperative* in
[§2.3](../CONSTITUTION.md#2-modules), and a *joint* in [platform.md](platform.md#domain-model) —
three sentences that would each be missing something if the other two were deleted.

What is bounded is which layer may hold which:

| Layer | Holds | Never holds |
| --- | --- | --- |
| ADR | the reasoning — the only place a *why* is argued | rules; how a module is configured |
| CONSTITUTION | one imperative sentence per rule, plus its citation | the argument for the rule; restated mechanism |
| platform.md | the joints — what meets what, through which value | the rule itself; anything about one module alone |
| spec | one module's design and its criteria | anything true of every module |

**The rule that follows: reasoning appears exactly once.** A second file may state a decision's
*consequence* imperatively or describe the *joint* it creates, and neither may re-argue it. When
you find yourself explaining *why* outside an ADR, the text belongs in the ADR and the link
belongs where you were writing.

There is deliberately no sixth "one page compiling the rest" document. Such a page restates
without owning anything, so it drifts by construction and then disagrees with the layer that is
actually correct.

## Specifications

| Spec | Covers |
| --- | --- |
| [platform](platform.md) | the domain model, the seven joints between modules, the contracts, environments |
| [certificate-management-cert-manager](modules/certificate-management-cert-manager/README.md) | the lab's certificate authorities, its wildcard, its client certificate, its trust bundle |
| [observability-storage-grafana-lgtm](modules/observability-storage-grafana-lgtm/README.md) | collecting metrics, logs and traces, storing them, and their tenants |
| [observability-console-grafana](modules/observability-console-grafana/README.md) | reading them — one Grafana, its roles and its alerting |
| [object-storage-rustfs](modules/object-storage-rustfs/README.md) | one S3-compatible endpoint, for workloads whose supported backend is an object store |
| [openid-connect-keycloak](modules/openid-connect-keycloak/README.md) | the OIDC issuer |
| [resource-authorization-ory-keto](modules/resource-authorization-ory-keto/README.md) | whether a subject may act on a particular resource, asked per decision |
| [access-proxy-ory-oathkeeper](modules/access-proxy-ory-oathkeeper/README.md) | authenticating a request before it reaches a workload that cannot |

## Decisions

**Platform-wide** — reversing one of these changes every module.

| ADR | Decision | Status |
| --- | --- | --- |
| [004](adr/004-scrape-config-via-prometheus-crds.md) | Scrape config through Prometheus operator CRDs | accepted |
| [005](adr/005-modules-are-applicationsets.md) | Modules are ApplicationSets, not Applications | accepted |
| [006](adr/006-shared-gateway-input.md) | One `gateway` input shape | superseded by 7 |
| [007](adr/007-modules-receive-credentials.md) | Module input contracts; providers publish addresses | accepted |
| [008](adr/008-postgresql-is-external.md) | PostgreSQL is external to this project | accepted |
| [010](adr/010-resources-delivered-via-chart.md) | Resources are chart-delivered; OpenTofu creates no bare manifests | accepted, the chart-location clause superseded by 28 |
| [011](adr/011-environments-are-clusters.md) | An environment is a cluster | accepted, layering superseded by 20 |
| [012](adr/012-state-is-per-environment.md) | State is per environment, and lives in PostgreSQL | accepted |
| [013](adr/013-roles-are-carried-in-the-token.md) | Roles are `<SLUG>_<ROLE>`, carried in the token | accepted |
| [014](adr/014-exposed-does-not-mean-authorized.md) | Exposed does not mean authorized | accepted |
| [015](adr/015-units-are-wired-by-hand.md) | Units are wired by hand; no unit reads another's state | superseded by 20 |
| [016](adr/016-metrics-is-the-fourth-input.md) | `metrics.enabled` is the fourth cross-module input | accepted, the root variable superseded by 24 and the one-field shape by 25 |
| [017](adr/017-stores-are-multi-tenant.md) | The stores are multi-tenant; the caller names its tenant | accepted |
| [018](adr/018-one-trust-bundle-for-the-cluster.md) | One trust bundle for the cluster, not a mount per workload | accepted |
| [019](adr/019-the-tool-is-opentofu.md) | The tool is OpenTofu; "Terraform" means the language | accepted |
| [020](adr/020-one-root-module.md) | There is one root module, and no Terragrunt | accepted |
| [021](adr/021-code-does-not-cite-documentation.md) | Code does not cite documentation | accepted |
| [022](adr/022-secrets-are-rendered-empty.md) | A module renders the Secret it needs, empty, unless it is given one | accepted |
| [023](adr/023-a-modules-opentofu-is-at-its-root.md) | A module's OpenTofu is at its root, not under `tofu/` | accepted, the chart's location superseded by 28 |
| [024](adr/024-the-metrics-fact-is-derived.md) | The metrics fact is derived at the root, not declared | accepted |
| [025](adr/025-a-workload-carries-its-tenant.md) | A workload carries its tenant in `opentelemetry.io/tenant` | accepted |
| [026](adr/026-roles-decide-the-operation-relationships-decide-the-resource.md) | Roles decide the operation, relationships decide the resource | accepted |
| [027](adr/027-a-machine-caller-is-authorized-by-scope.md) | A machine caller is authorized by scope, not by a role | accepted |
| [028](adr/028-charts-are-first-class-artifacts.md) | Charts are first-class artifacts, published from the repository root | accepted |

**Module-scoped** — reversing one changes nothing outside its module.

| ADR | Decision | Status |
| --- | --- | --- |
| [cert-manager LOCAL-001](modules/certificate-management-cert-manager/adr/LOCAL-001-certificates-from-an-internal-ca.md) | Certificates come from an internal CA, not a public one | accepted |
| [cert-manager LOCAL-002](modules/certificate-management-cert-manager/adr/LOCAL-002-one-certificate-per-authority.md) | One certificate per authority; no client list | accepted |
| [keycloak LOCAL-001](modules/openid-connect-keycloak/adr/LOCAL-001-oidc-provider-keycloak.md) | OIDC provider is Keycloak, deployed by its operator | accepted |
| [keycloak LOCAL-002](modules/openid-connect-keycloak/adr/LOCAL-002-the-operator-comes-from-upstream-manifests.md) | The operator comes from upstream's manifests, pinned by tag | accepted |
| [object-storage LOCAL-001](modules/object-storage-rustfs/adr/LOCAL-001-rustfs-standalone.md) | The object store is RustFS, running standalone | accepted |
| [observability-storage LOCAL-001](modules/observability-storage-grafana-lgtm/adr/LOCAL-001-grafana-lgtm-stack.md) | The Grafana stack, three single-binary components | accepted |
| [observability-storage LOCAL-002](modules/observability-storage-grafana-lgtm/adr/LOCAL-002-mimir-monolithic-chart.md) | Mimir runs monolithic, from a chart this repo authors | accepted |
| [observability-storage LOCAL-003](modules/observability-storage-grafana-lgtm/adr/LOCAL-003-scrape-first-one-otlp-address.md) | Scrape first; one neutral address for the rest | accepted |
| [observability-storage LOCAL-004](modules/observability-storage-grafana-lgtm/adr/LOCAL-004-storage-split-from-console.md) | Storage splits from the console; the receiver gets a route | accepted |
| [observability-storage LOCAL-006](modules/observability-storage-grafana-lgtm/adr/LOCAL-006-stores-keep-their-data-in-an-object-store.md) | The three stores keep their data in an object store | accepted |
| [observability-storage LOCAL-007](modules/observability-storage-grafana-lgtm/adr/LOCAL-007-a-signal-is-its-own-configuration.md) | A signal is its own configuration; its presence is the switch | accepted |
| [observability-storage LOCAL-008](modules/observability-storage-grafana-lgtm/adr/LOCAL-008-a-scraped-workload-names-its-own-tenant.md) | A scraped workload names its own tenant, in a label | accepted |
| [observability-console LOCAL-001](modules/observability-console-grafana/adr/LOCAL-001-two-grafana-roles-strict.md) | Applying the role convention to Grafana | accepted |
| [observability-console LOCAL-002](modules/observability-console-grafana/adr/LOCAL-002-no-alerting.md) | No alerting | superseded by its LOCAL-003 |
| [observability-console LOCAL-003](modules/observability-console-grafana/adr/LOCAL-003-alerting-lives-in-grafana.md) | Alerting lives in Grafana, and in its database | accepted |
| [resource-authorization LOCAL-001](modules/resource-authorization-ory-keto/adr/LOCAL-001-the-store-is-ory-keto.md) | The relationship store is Ory Keto | accepted |
| [resource-authorization LOCAL-002](modules/resource-authorization-ory-keto/adr/LOCAL-002-the-write-port-admits-only-its-caller.md) | The write port admits only the caller it is told to admit | accepted |
| [access-proxy LOCAL-001](modules/access-proxy-ory-oathkeeper/adr/LOCAL-001-the-proxy-is-ory-oathkeeper.md) | The access proxy is Ory Oathkeeper, and it protects a set it is told | accepted |

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
[the scope test](../CONSTITUTION.md#10-documentation) (§10.4), so the fix is to lift it rather
than to link across. `ADR 017` and `ADR 018` were both lifted for exactly this reason
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

### ADR shape

**Four sections, in this order, and the order is the point.**

| Section | Contains |
| --- | --- |
| *(lede)* | One sentence under the header, before any heading: what was decided |
| `Decision` | What was chosen, stated so it can be checked against code |
| `Context` | What was true that forced a choice. Not a history of the project — only what bears on this |
| `Rationale` | Why this one. The argument, not the options |
| `Alternatives` | Every serious option that was **not** chosen, and what each would have cost. "None" is an honest answer where it is true, and needs a sentence saying why |
| `Consequences` | What it costs, what it forecloses, what to watch, and **what would make it worth revisiting** |

**Decision comes first because the reader usually wants only that.** This follows the inverted
pyramid — the most important material at the top, detail below — so someone checking *what was
decided* stops after two paragraphs and someone asking *why* keeps reading. Context first, which
these files used until 2026-08-23, made every reader spend half a page before learning the answer.

**`Rationale` and `Alternatives` are different sections because they answer different questions**,
and conflating them is how the second one goes missing. Rationale argues for what was chosen;
Alternatives records what was not, and what it would have cost. The rejected options are the part
that decays fastest and is worth most later — they are what tells a future reader whether the
world has changed enough to reopen this. Where they have pros and cons worth tabulating, tabulate
them.

**Keep it near one page.** Where a decision needs more, the extra belongs in the spec it governs,
or in a linked note — not in the record of the choice.

**One file is deliberately not in this shape.** [ADR 006](adr/006-shared-gateway-input.md) is a
tombstone: its decision was absorbed into ADR 007 and the file survives only to record where it
went and why deleting it would delete the premise ADR 010 argues against. A superseded ADR whose
reasoning still stands keeps the four sections; one that has become a pointer does not need them.

### Status

**A decision and a design do not have the same statuses, because they are not the same kind of
claim.** An ADR records a choice, so its status says whether the choice still stands. A spec
describes a design, so its status says how far that design has got.

| Where | Value | Means |
| --- | --- | --- |
| ADR | `proposed` | written down but **not made**. No ADR currently holds it; ADR 012 did, until its backend was chosen |
| ADR | `accepted` | the decision stands |
| ADR | `superseded by <ref>` | another decision replaced it. The file stays; the reasoning is still the record of why the old answer looked right |
| Spec | `draft` | written, and nothing implements it yet |
| Spec | `implemented` | code exists and does what this describes |

**`accepted` never appears on a spec.** A spec is not agreed to, it is built — and a spec left at
`draft` while its module runs in a cluster is the drift this field exists to catch. Moving one to
`implemented` is part of finishing the module, not a later tidy-up.

### Module specs

**Every module spec has at least these sections, in this order.** A missing one is a gap, not
a style choice. Extra sections are fine where a module earns one, and the bar is that the
section carries something none of the standard ones can hold. No spec currently has one: the
last that did was dropped with its module, and what it had to say was the reason it went.

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

`Prerequisites` is the one optional section with a fixed name and position. It was made optional
when two modules needed it; every module has one now, and the fixed name is what stopped the
sixth from inventing its own. It is where the Secret examples live: a new `secret_name` without one
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

### Revising an ADR

**Changing what was decided means a new ADR that supersedes the old one**, once anything
implements it. The old file stays, because reasoning that turned out wrong is the record of what
the wrong answer looked like from the inside. [ADR 006](adr/006-shared-gateway-input.md) is the
worked example. While nothing implements a decision it may be revised in place instead — ADRs
005, 006 and 007 were, on 2026-08-09, when there was no code.

**Three edits are not "changing what was decided", and need no supersession.** They were split
out on 2026-08-23, after a cleanup made the distinction obvious by breaking the rule as it was
then written:

1. **Correcting a reference to something that no longer exists.** A decision naming a module that
   has since been retired is stating something false about today; removing the name and keeping
   the argument changes nothing about the choice. Do it in place — and where the reference was
   *load-bearing*, replace it with what it was an example of rather than deleting the sentence.
2. **Recording that the world moved.** A pre-1.0 dependency reaching 1.0, an upstream renumbering
   its charts: the consequence is revised in place with a **dated note saying what it used to say
   and why it changed**, because the old reading was correct when written and a reader who
   remembers it deserves to find out what happened.
3. **Restructuring.** Reordering sections or splitting a paragraph out under a heading is not an
   edit to the decision at all.

Everything else — a different choice, a different rule, a changed scope — is a new ADR.

## Making the criteria executable

They are prose today, checked by hand. The path to executable is a policy tool such as
conftest asserting against `tofu plan -json` for the `@plan` scenarios, and `kubectl`
assertions for the `@cluster` ones. The tags exist so that harness can select its half without
anyone re-reading every file first.

The harness is not worth building before the modules exist. Tagging them now costs nothing and
is the part that would otherwise have to be retrofitted.
