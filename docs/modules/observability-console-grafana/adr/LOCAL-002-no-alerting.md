# LOCAL-002. No alerting

**Status:** superseded by [LOCAL-003](LOCAL-003-alerting-lives-in-grafana.md) ·
**Scope:** module — `observability-console-grafana` ·
**Date:** 2026-08-12 · superseded 2026-08-15

Written while the storage components and Grafana were one module, and numbered `LOCAL-004`
there. Both the number and the folder changed when that module split; the argument did not.

**Ship no alerting: Mimir's Alertmanager is never started and Grafana's Unified Alerting is left unprovisioned. **Superseded by [LOCAL-003](LOCAL-003-alerting-lives-in-grafana.md).****

## Decision

**Ship no alerting.** Mimir's Alertmanager is never started; the ruler runs as part of
`-target=all` but is given no rules. Grafana's Unified Alerting is left unprovisioned — no alert
rules, no contact points, no notification policies.

This module delivers observability. It does not deliver notification.

## Context

Alerting is not a component this module has to install. It is already present twice over, in
things being installed for other reasons, which is what makes the question worth an ADR rather
than an omission.

Mimir's `-target=all` **already runs the
ruler**, and its Alertmanager joins the same process with `-target=all,alertmanager`. Grafana
ships Unified Alerting, which evaluates rules against any datasource and routes notifications
itself. Both are free in pod count. Neither is free in maintenance.

So the decision could not be settled on resource cost, which is the axis most decisions in this
repo are settled on. Three options were real:

- **Mimir's ruler and Alertmanager.** Rules provisioned as a ConfigMap through
  `ruler_storage.backend: local` — a read-only backend whose documented purpose is exactly
  this, so rules would be git-declared and Argo-reconciled, satisfying
  [REQ-08](../../../requirements.md) properly. It would also make the roughly hundred curated
  Kubernetes alert rules usable, since they are plain PromQL. The costs: local ruler storage
  cannot be listed through the ruler API, so Grafana's UI can neither view nor edit those
  rules, and the ruler alerts on metrics only.
- **Grafana Unified Alerting.** Alerts across any datasource including Loki, rules
  provisionable through the chart's `alerting:` values and authorable in the UI. Dies with
  Grafana.
- **Neither.**

A fourth option — `ruler_storage.backend: filesystem`, which *is* writable and would let Grafana
edit rules through the ruler API — was ruled out immediately: the rules would then live only on
a PVC, reconciled from nothing, which violates [REQ-08](../../../requirements.md) outright.

## Rationale

- Nothing here is on call. Two machines, one operator, and stretches of weeks where nobody
  touches the cluster — the state this repo was written for. An alert that fires into a contact
  point nobody configured is worse than no alert, because it looks like coverage.
- The repo's own rule: *a knob is only turned once something actually hurts*. Nothing has hurt
  yet. Alerting configured before the first incident is configured against an imagined incident,
  and it is the imagined one that gets the rules.
- Both real options were free in pods and neither was free in maintenance. Rules, routing trees
  and contact points are configuration that rots silently — it is only ever exercised when
  something is already wrong, which is the worst moment to discover it was wrong too.
- The two options differ on an axis that cannot be settled yet: whether alerting must survive
  Grafana being down, and whether log-based alerting is wanted. Both questions have obvious
  answers once there has been one incident, and no honest answer before.
- Declining is cheap to reverse and cheap to defer. Choosing wrongly between the two now would
  be neither.

## Alternatives

- **Mimir's Alertmanager**, joined to the same process with `-target=all,alertmanager`. Free in
  pod count, and it puts rules in a ConfigMap of rule files.
- **Grafana's Unified Alerting**, which evaluates against any datasource and routes notifications
  itself. Also free in pod count, and its rules live in Grafana's database.

Neither is free in maintenance, so the decision could not be settled on resource cost — the axis
most decisions here are settled on. It was deferred instead, and
[LOCAL-003](LOCAL-003-alerting-lives-in-grafana.md) later chose the second.

## Consequences

- **Nothing tells anyone anything.** Failures are found by a person opening Grafana. On this
  cluster that is honest rather than negligent, but it is the consequence and it is the whole
  consequence.
- **The curated Kubernetes alert rules are declined, not lost.** They remain plain PromQL, and
  the path to using them stays open.
- The spec asserted the absence in an acceptance scenario, because a chart value flipping
  alerting back on by default is exactly the kind of thing that arrives unnoticed in a version
  bump.
- **Reversible, precisely:** append `,alertmanager` to Mimir's target, point
  `ruler_storage.backend` at `local` over a mounted ConfigMap of rule files, and set
  `-ruler.alertmanager-url` at the local instance. One pod, unchanged. Grafana can then be
  pointed at that Alertmanager to view alerts and create silences, keeping the operational half
  of the UI even though rules stay in git.
- If log-based alerting is ever wanted, Loki's own ruler notifies the same Alertmanager. That
  path is open too, and it is the reason the reversal above is worth writing down rather than
  rediscovering.
