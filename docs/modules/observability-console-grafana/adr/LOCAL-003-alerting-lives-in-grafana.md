# LOCAL-003. Alerting lives in Grafana, and in the database Grafana already needs

**Status:** accepted · **Scope:** module — `observability-console-grafana` ·
**Date:** 2026-08-15 · supersedes [LOCAL-002](LOCAL-002-no-alerting.md)

**Alerting is Grafana's Unified Alerting and nothing beside it, stored in the PostgreSQL this
module already requires.**

## Decision

**Grafana's Unified Alerting, and nothing beside it.** Rules, contact points, notification
policies and silences are authored in Grafana's UI and stored in the PostgreSQL this module
already requires.

**No Alertmanager is deployed.** Grafana embeds one; a second would be a second place a rule
could be authored, and neither would be authoritative.

**Nothing is provisioned.** No `alerting:` values, no rule files, no contact points in git. The
capability is present and unconfigured — which is what LOCAL-002 delivered too, so the outcome
on day one is unchanged. What changed is the stance: alerting stops being *declined* and becomes
*available and unused*.

**The storage module is unaffected.** It gains no `alertmanager_url`, no ruler storage
configuration, and no rules. Mimir's ruler remains part of `-target=all` and remains unused.

## Context

[LOCAL-002](LOCAL-002-no-alerting.md) declined alerting and said why: nothing here is on call,
nothing had hurt yet, and the two real options differed on an axis it could not settle — whether
alerting must survive Grafana being down, and whether log-based alerting is wanted. It also
wrote down a reversal path costing zero pods: append `,alertmanager` to Mimir's target, point
`ruler_storage.backend` at `local` over a ConfigMap of rule files, and let Grafana view the
result.

Two things then changed.

**The module split.** Mimir now lives in the storage module. The zero-pod reversal path lands
on the other side of that line, so "the console provides alerting" would mean deploying a
standalone Alertmanager here — a pod LOCAL-002 had costed at nothing — and giving the storage
module an `alertmanager_url` input plus a ruler configuration it otherwise has no use for.

**Rules in git stopped being wanted.** LOCAL-002's preferred shape put rule files in a ConfigMap,
reviewed and reconciled. The requirement now is that a rule can be written without a commit.
That eliminates the `local` ruler backend outright — it is read-only through the ruler API by
design, which is exactly why LOCAL-002 liked it.

So the question became narrow: **where can alerting configuration live, if not git?** There are
four candidate homes and three of them fail.

| Home | Authorable without a commit | Why it fails, or does not |
| --- | --- | --- |
| a ConfigMap, from chart values | no | this is git, restated |
| Mimir's ruler, `filesystem` backend on a PVC | yes | LOCAL-002 ruled it out on sight — reconciled from nothing, on the node-pinned volume that is the storage module's weakest point. Splitting the modules did not improve the volume |
| an object store | yes | means running one. The metrics store already declined an object store for its blocks backend; standing one up for alert rules inverts that trade for a smaller prize |
| **Grafana's PostgreSQL**, via Unified Alerting | yes | already required, already holds this module's only irreplaceable state, already in whatever backs that up |

A fifth shape was considered and is not a home at all: a standalone Alertmanager whose
configuration is not in git. **Alertmanager has no configuration API** — its API creates
silences and receives alerts, and never writes its own config. "Not in git" would mean
hand-editing a ConfigMap that Argo CD reverts on the next sync.

## Rationale

- **PostgreSQL is the only non-git home that costs nothing new.** It is already mandatory, it
  already holds the users, preferences and annotations that cannot be regenerated, and it is
  already the thing whose loss is unrecoverable. Alerting state adds a row, not a dependency.
- **The split priced the alternative honestly, and the price went up.** LOCAL-002 could say the
  ruler-and-Alertmanager path was free because both were already running in one process. Across
  two modules it is a new chart, a new pod, a new input on a module that has no other use for
  it, and a routing tree in git after all.
- **One place to author a rule.** Running a standalone Alertmanager alongside Grafana's embedded
  one means two Alertmanagers unless the built-in is explicitly disabled, and two ways to write
  a notification policy. LOCAL-002 worried about configuration that rots silently; two of them
  rot faster than one.
- **The unsettled axis is settled by the same reasoning that made Grafana acceptable.** Whether
  alerting must survive Grafana being down is answered *no* by a cluster where Grafana being
  down is already how you find out something is wrong.
- **Log-based alerting comes free, which the other path could not offer.** Grafana evaluates
  against any datasource, so alerting on logs needs no Loki ruler and no second Alertmanager
  URL. LOCAL-002 listed that as an open question; this answers it by construction.
- **It does not close the git path.** Grafana exports Unified Alerting rules as provisioning
  YAML. If alerting ever becomes load-bearing enough to want reviewing, the export is the
  starting point rather than a rewrite.

## Alternatives

- **Mimir's Alertmanager**, the zero-pod reversal path [LOCAL-002](LOCAL-002-no-alerting.md)
  wrote down. It now lands in the *other* module, so taking it would put alerting in the storage
  module and its viewing surface here — and it alerts on metrics only, leaving logs uncovered.
- **Both**, each authoring rules in its own place. Two places a rule could exist and no way to see
  them together, which is the failure a single query surface exists to prevent
  ([REQ-03](../../../requirements.md)).
- **Continue to ship none.** Still defensible on cost and no longer on need.

## Consequences

- **No rule is reviewable.** A rule cannot be diffed, cannot be code-reviewed, and arrives in no
  pull request. That is the cost, and it is the direct inverse of what LOCAL-002 valued.
- **[REQ-08](../../../requirements.md) is not dented, and it is worth being precise about why.**
  It claims reconciliation over what this repo *provisions*. This repo provisions no alert rule.
  One created in the UI is in the same category as the Secrets somebody creates by hand — real,
  necessary, and outside the claim rather than in violation of it.
- **Losing the PostgreSQL now loses alerting too.** It already held the only non-regenerable
  state; the blast radius of not backing it up just got wider, and nothing in this repo backs it
  up.
- **Nothing evaluates while Grafana is down.** The console being unavailable and the alerting
  being unavailable are one outage, not two.
- **CON-10 asserts nothing is provisioned, and CON-11 asserts the database is the home.** The
  first guards against a chart default arriving in a version bump; the second is the claim this
  decision actually rests on, so it is checked rather than assumed.
- **Reversible, precisely:** deploy a standalone Alertmanager here, point Grafana's Unified
  Alerting at it as an external Alertmanager and disable the built-in, and — if rule evaluation
  must also leave Grafana — give the storage module an `alertmanager_url` and a `local` ruler
  backend over a ConfigMap. Each of those three steps is independently useful, and none of them
  needs this decision undone first.
