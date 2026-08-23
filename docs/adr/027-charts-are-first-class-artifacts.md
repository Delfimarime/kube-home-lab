# 028. Charts are first-class artifacts, published from the repository root

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-23 ·
supersedes the chart-location clause of [ADR 010](010-resources-delivered-via-chart.md) and its
restatement in [ADR 023](023-a-modules-opentofu-is-at-its-root.md)

**A chart this repository authors lives at `helm/<chart>/` at the root, owns its values interface,
and carries a version that is bumped — it is something this repository publishes, not a module's
private detail.**

## Decision

**Charts live at `helm/<chart-name>/`, at the repository root.** `modules/` holds OpenTofu and
nothing else.

Three obligations come with that, and they are the decision — the directory move on its own is
not:

1. **A chart's `values.yaml` is its published interface**, owned by the chart. A module supplies
   values against that schema; it does not reach past it, and it does not get to change the schema
   as a side effect of changing itself.
2. **`Chart.yaml`'s `version` is meaningful and is bumped.** A change to the values schema is a
   version change, by semver: additive is minor, breaking is major. Today all five charts read
   `0.1.0` and nothing has ever bumped one, which is the habit this ends.
3. **`ci/*-values.yaml` describes the configurations the chart supports**, not the way one module
   happens to call it. Each file is a claim: *this configuration renders*. A configuration nobody
   rendered is a configuration nobody promised.

A module references a chart by path. **Sharing a chart between modules is allowed and deliberate**
— it means the second consumer renders against the published schema, and a schema change is a
version bump that both consumers can see.

**Unchanged:** [ADR 010](010-resources-delivered-via-chart.md)'s native/wrapped/custom ordering,
and its rule that a generated `Application` owns every resource its chart needs.
[ADR 023](023-a-modules-opentofu-is-at-its-root.md)'s `.tf`-at-the-module-root is also unchanged;
only its sentence about `helm/` staying inside the module goes.

## Context

[ADR 010](010-resources-delivered-via-chart.md) placed a chart *inside* the module that owns it,
and gave a reason: *"What a module **is** and what it **deploys** stay one level apart and never
interleaved, and no chart is shared between modules by accident."*
[ADR 023](023-a-modules-opentofu-is-at-its-root.md) restated it while moving `.tf` up out of
`tofu/`.

Five charts exist now, and two things about them were not true when that clause was written.

**One chart already has four consumers.** `secret-template` is rendered on behalf of
`object-storage-rustfs`, `observability-console-grafana`,
`observability-storage-grafana-lgtm` and `openid-connect-keycloak` — six call sites. The layout
offered no way to share a chart, so it is shared by wrapping it in an OpenTofu module that every
consumer imports. That works, and it means the thing holding the chart's contract is a
`variables.tf` in a directory beside it rather than the chart's own schema.

**The coupling to the module is already nominal.** Every chart path is a repository-relative
string in a `locals.tf` — `"modules/<module>/helm/<chart>"` — not a `path.module` derivation. Argo
CD reads charts from a git path; it has never known which module rendered the `ApplicationSet`
pointing at it.

So the clause bought its guarantee by removing an option, and the option turned out to be wanted.

## Rationale

- **A chart and a module are two artifacts with two lifecycles.** The chart is what Argo CD
  consumes; the module is what computes its values. Keeping them in one directory implies one
  lifecycle, and the version field that should express the chart's own has sat at `0.1.0` since
  the beginning — which is what happens to a version nobody can act on.
- **Deliberate sharing beats impossible sharing.** The superseded clause prevented accidental
  coupling by preventing coupling. What replaces it is a version and a values contract, so a
  second consumer is a choice somebody made and a schema change is visible to both.
- **`secret-template` is the worked example, and it shows the contract in the wrong place.**
  Wrapping a chart in an OpenTofu module to give it an interface is the right instinct — an
  interface — applied one level out. The interface belongs to the chart.
- **One tree is the only place a reader can see what this repository publishes.** Today that
  answer requires walking five module directories, and nothing distinguishes a chart with one
  consumer from a chart with four.

## Alternatives

- **Leave the charts inside their modules.** The status quo. It keeps the blast radius of a chart
  edit at one module by construction, and keeps every chart's interface implicit — which is free
  while a chart has one consumer and is exactly what breaks the first time one has two.
  `secret-template` already has four.
- **Move the charts and change nothing else.** A tidier tree, and four single-consumer charts that
  *look* shared while their schemas are still owned by one caller each. This is relocation sold as
  reuse: it takes the wider blast radius without the versioning and `ci/` discipline that earns
  it, and it was rejected on exactly that.
- **Publish charts to a registry** — OCI, or a chart repository — and have `Application`s consume
  them by version rather than by git path. This is the complete version of first-class, and it is
  what this decision leaves room for rather than rules out. It costs a publish step, a registry
  reachable from every environment, and the property that *what merges to `main` is what Argo CD
  reads* — which is currently the only gate this repository has. Deferred.
- **Formalise `secret-template` alone** and leave the other four where they are. The least change,
  and it makes the layout a special case that has to be explained at every reading, for a rule
  that would then have one exception and four instances.

## Consequences

- **A chart edit now reaches every consumer, and nothing at a call site names them.** This is
  precisely the coupling the superseded clause forbade, and it is the price. What stands in for
  the old guarantee is the version bump and the `ci/` set — neither of which is enforced by
  anything today, so **this decision is only as good as the discipline it asks for**.
- **`§2.2` is rewritten and `§2.2.1` is new**, carrying the interface, version and `ci/`
  obligations as a rule rather than only as reasoning. The layout blocks in
  [AGENTS.md](../../AGENTS.md) and [README.md](../../README.md), the chart paragraphs in the
  `creating-module` skill, and `CHARTS` in the [Makefile](../../Makefile) all moved with it.
- **Applying the move has an ordering hazard.** Every generated `Application`'s `source.path`
  changed. The chart must exist at the revision Argo CD tracks *before* the `ApplicationSet`
  points at the new path: push, then `tofu apply`. The reverse leaves every `Application` in
  `ComparisonError` — recoverable in a minute, and worth a runbook line rather than a discovery.
  **This has not yet been applied to any cluster.**
- **A version nobody bumps is worse than no version**, because it reads as a promise. All five
  charts start at `0.1.0`; the first schema change after the move is the one that establishes
  whether this obligation is real.
- **A module can no longer be read as one directory.** [§10.6](../../CONSTITUTION.md#10-documentation)
  says read a module's spec and its ADRs before changing it, and the chart it renders now lives
  elsewhere. Each spec's `Provisions` section has to name the chart it consumes and its version.
- **`make helm-lint` and `make trivy` scan whatever `ci/` holds**, so broadening those files from
  one module's usage to a chart's supported configurations costs render time and catches more.
  That is the trade being bought, and it is the only automated part of it.
- **Revisit when a chart earns a consumer outside this repository.** At that point the git path
  stops being adequate and the registry alternative above becomes the next decision, not this one
  again.
