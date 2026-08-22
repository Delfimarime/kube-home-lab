---
name: writing-adr
description: How to place, number, shape and register an architecture decision record in this repository — the platform-vs-module scope test, the numbering with its retired gaps, and revising versus superseding. Use when recording any decision, with or without a new module.
---

# Writing an ADR

**This file holds procedure. The rules are in
[CONSTITUTION.md §10](../../../CONSTITUTION.md#10-documentation) and the conventions in
[docs/README.md](../../../docs/README.md#conventions)** — follow the links rather than assuming
what they say.

Order: **scope → number → write → register**. Scope first, because getting it wrong means the
file is in the wrong directory with the wrong number and every citation to it has to move.

---

## 1. Scope

**The test:** if reversing this decision would change code outside one module, it is
platform-wide → `docs/adr/NNN-slug.md`. Otherwise it is module-scoped →
`docs/modules/<module>/adr/LOCAL-NNN-slug.md`
([§10.4](../../../CONSTITUTION.md#10-documentation)).

**The tell:** if while writing you want to cite another module's ADR, the test has already
failed. Lift the decision to the platform sequence instead of linking across
([§10.5](../../../CONSTITUTION.md#10-documentation)). ADRs
[017](../../../docs/adr/017-stores-are-multi-tenant.md) and
[018](../../../docs/adr/018-one-trust-bundle-for-the-cluster.md) were both written as module ADRs
and lifted for exactly this reason.

**Citation runs one way only.** A module ADR may cite a platform ADR; a platform ADR never cites
a module one. A platform decision that needed a module's reasoning to stand up would not be
platform-scoped. The traceability matrix is the single exception, and there a module ADR is
qualified by its module name.

**The trap is a decision that reads local and is not.**
[ADR 004](../../../docs/adr/004-scrape-config-via-prometheus-crds.md) looks like an observability
decision and is platform-wide, because it is why every module declares scraping through its own
chart.

## 2. Number

**Three digits, zero-padded, everywhere** — `007`, not `7`, in the filename, the title and every
citation.

**Platform ADRs** use one global sequence, unprefixed. **Module ADRs** restart at `001` per
module and carry the `LOCAL-` prefix.

**Take the next number after the highest that exists — never fill a gap.** The gaps are
deliberate and each one marks something:

| Sequence | Gaps | Why they stay open |
| --- | --- | --- |
| platform | 001, 002, 003, 009 | moved into module folders and renumbered `LOCAL-NNN` |
| `certificate-management-cert-manager` | LOCAL-003 | lifted to platform `ADR 018` |
| `observability-storage-grafana-lgtm` | LOCAL-005 | lifted to platform `ADR 017` |

Reusing one of these makes an old citation resolve to the wrong decision instead of to nothing,
which is the failure the gaps exist to prevent. The same applies to any number retired later.

## 3. Write

Four sections, in this order — every ADR here has exactly these:

```
## Context      what was true, and what forced a choice
## Decision     what was chosen, stated so it can be checked
## Rationale    why this one, and what the alternatives cost
## Consequences what it costs, what it forecloses, what to watch
```

**The header states the scope**, so a file read on its own still says what it constrains:

```
**Status:** accepted · **Scope:** platform · **Date:** 2026-08-05
**Status:** accepted · **Scope:** module — `observability-storage-grafana-lgtm` · **Date:** …
```

Statuses are in [docs/README.md](../../../docs/README.md#status). `accepted` and `superseded by
<ref>` are the ones in use; `proposed` means written down but not made, and nothing currently
holds it.

**Consequences is the section that earns the file.** Six months on, the reason anyone opens an
ADR is to find out what breaks if they change it —
[REQ-11](../../../docs/requirements.md) is the requirement this whole layer serves. An ADR whose
Consequences say only "we will use X" has recorded the decision and lost the reason.

**A worked example:** [ADR 025](../../../docs/adr/025-a-workload-carries-its-tenant.md) for a
platform decision that supersedes half of an earlier one, and
[object-storage LOCAL-001](../../../docs/modules/object-storage-rustfs/adr/LOCAL-001-rustfs-standalone.md)
for a product choice with a candidates table.

## 4. Register

- A row in the right table in [docs/README.md](../../../docs/README.md#decisions) — platform and
  module-scoped are separate tables.
- The `Decided in` column of the [traceability matrix](../../../docs/requirements.md#traceability),
  against each requirement it serves. Qualify a module ADR with its module: `keycloak LOCAL-001`.
- The `Decisions:` line in the header of any spec that now obeys it.
- `make docs` — it fails on a decision that exists on disk and is in no table.

---

## Revising versus superseding

**Revise in place only while nothing implements it.** Once code exists, changing a decision means
a *new* ADR that supersedes the old one, and **the old file stays** — reasoning that turned out
wrong is the most useful thing in the folder, because it records what the wrong answer looked
like from the inside.

[ADR 006](../../../docs/adr/006-shared-gateway-input.md) is the worked example of being
superseded; ADRs 005, 006 and 007 were all revised in place on 2026-08-09, when there was no
code.

A supersession is not always total. Mark what was actually replaced —
[ADR 016](../../../docs/adr/016-metrics-is-the-fourth-input.md) is listed as *"accepted, the root
variable superseded by 24 and the one-field shape by 25"*, because the rest of it still stands.

## Where a decision does not go

**Not into a code comment as a citation** ([§10.3](../../../CONSTITUTION.md#10-documentation)).
Traceability runs documentation → code and never back, because a citation in a comment is a link
nothing checks in a repository that renumbers. Write the reason itself into the comment, in
enough words to stand alone. `make docs` checks this.

**Not into [requirements.md](../../../docs/requirements.md).** A requirement that names a product
is a decision in the wrong file.
