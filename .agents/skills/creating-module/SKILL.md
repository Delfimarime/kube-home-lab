---
name: creating-module
description: The order in which a new module in this repository is created — admission, requirement, decisions, spec, registration, implementation, close. Use when adding a capability, proposing a module, or asked whether something should become one.
---

# Creating a module

**This file holds order, gates and the set of files that must change together. It holds no
rules.** Every rule is in [CONSTITUTION.md](../../../CONSTITUTION.md), each citing the decision
behind it, and copying one here would create a second copy to disagree with — which is the
failure [§10.1](../../../CONSTITUTION.md#10-documentation) exists to prevent. Cited sections are
links; follow them rather than assuming what they say.

Seven phases, in order. Two of them end by **stopping and asking**, because getting them wrong
is not something the later phases can recover from.

---

## 0. Admission — **gate**

Before anything is written down. Four questions, answered in the conversation, not in a file:

1. **Is this a capability, or a prerequisite?** This repository provisions platform capabilities
   and never a prerequisite ([§1.1](../../../CONSTITUTION.md#1-boundaries)). A module that would
   run k3s, Argo CD, a Gateway or a PostgreSQL is a different project sharing a checkout.
2. **Which requirement does it serve?** Name it from
   [requirements.md](../../../docs/requirements.md). If none covers it, phase 1 applies — and
   that is a thing to decide with the user, never to assume.
3. **Does the name survive the product?** Modules are `<capability>-<implementation>`
   ([§2.1](../../../CONSTITUTION.md#2-modules)). Say out loud what the capability half would be
   if the product were swapped tomorrow; if that sentence is hard to write, the capability is not
   understood yet.
4. **What does it cost, standing, on a tiny cluster?** RAM is the budget and it is spent daily,
   per environment ([§1.4](../../../CONSTITUTION.md#1-boundaries),
   [REQ-10](../../../docs/requirements.md)). An answer of "a few hundred megabytes, idle" is a
   finding, not a footnote.

**Stop here.** Put the four answers to the user and get agreement before writing a file. This is
the phase where a module gets admitted that should not exist, or gets named after its vendor —
and both are expensive later, because the spec, the ADRs and the outputs all inherit the mistake.

## 1. Requirement — only if none covers it

A requirement states what must be true independent of implementation. **If it names a product it
is a decision and belongs in an ADR**, not here.

- A row in the table in [requirements.md](../../../docs/requirements.md), with its `Because`.
- A row in the traceability matrix in the same file.
- The next free `REQ-NN`. **Numbers 04 and 07 are retired and are not reused** — the file says
  why, and the same rule applies to any number retired later.

## 2. Decisions

Every module has at least one: which product, and why that one. Use
[writing-adr](../writing-adr/SKILL.md) — it holds the scope test, the numbering and the shape.

**Write the `Alternatives` section while you still remember them.** It is the section a later
reader needs most and the one that is impossible to reconstruct afterwards: what else was on the
table, and what each would have cost. `make docs` fails without it.

What matters at this phase is only that the decisions exist **before** the spec is written, since
the spec's header cites them.

**Stop here.** A decision is the user's to make. Put the options and what each costs; do not pick
a product and present the spec as the first sight of the choice.

## 3. Spec

`docs/modules/<capability>-<implementation>/README.md`, written before any OpenTofu
([§10.2](../../../CONSTITUTION.md#10-documentation)).

- **Status is `draft`.** It stays `draft` until phase 6.
- **Sections, in order:** the table in
  [docs/README.md](../../../docs/README.md#module-specs) is the definition. A missing one is a
  gap, not a style choice.
- **The worked example is
  [openid-connect-keycloak](../../../docs/modules/openid-connect-keycloak/README.md)** — the
  smallest complete spec here. Read its header, its `Prerequisites` and its Gherkin before
  writing yours. It is used instead of a template so that the example cannot drift from reality.
- **`Prerequisites` is where the `kubectl patch` for each Secret goes**, plus the rollout restart
  that follows ([§5.2](../../../CONSTITUTION.md#5-secrets)). A credential input without one is an
  incomplete spec — the object declares the shape, and this is the only record of what the value
  has to be.
- **Acceptance criteria** are Gherkin, one `Feature`, every scenario IDed and tagged. The
  conventions are in [docs/README.md](../../../docs/README.md#scenario-ids-and-tags). Pick a
  prefix no spec is using — `CERT`, `OBJ`, `CON`, `OBS`, `OIDC` and `PLAT` are taken — and start
  at `01`.

## 4. Registration

A new module is referenced from six places. **This set is the thing that gets missed**, in both
directions: it took two passes to remove the last module because leftovers described it without
naming it.

| File | What to add |
| --- | --- |
| [docs/README.md](../../../docs/README.md#specifications) | a row in the specifications index |
| [docs/README.md](../../../docs/README.md#decisions) | a row per ADR, in the right table |
| [docs/requirements.md](../../../docs/requirements.md#traceability) | the spec and its scenario IDs, against each requirement it serves |
| [docs/platform.md](../../../docs/platform.md) | the module table, and the scope line if the capability is new |
| [README.md](../../../README.md) | the module table |
| [AGENTS.md](../../../AGENTS.md) | only if something about it is blocked or undecided |

Then run `make docs`, which checks the mechanical half of this
([resync-doc-to-code](../resync-doc-to-code/SKILL.md)).

## 5. Implementation

Only now, and only against the spec as written. If implementing reveals the spec is wrong, change
the spec first — that is the order, not a formality.

**In `modules/<capability>-<implementation>/`**, `.tf` files and nothing else
([§2.2](../../../CONSTITUTION.md#2-modules), [§2.3](../../../CONSTITUTION.md#2-modules)). The file
names the existing modules use, which are convention rather than rule: `main.tf`, `variables.tf`,
`locals.tf`, `outputs.tf`, `res_argocd_application_set_<capability>.tf`, and
`module_credentials.tf` where it imports `secret-template`.

**A chart goes in `helm/<chart-name>/` at the repository root, not in the module.** It is
something this repository publishes, so check first whether an existing one already does the
job — that is now allowed, and it is the point ([§2.2.1](../../../CONSTITUTION.md#2-modules)).

**A new chart needs `helm/<chart>/ci/*-values.yaml`.** This is not optional and not documented
anywhere else: `make helm-lint` and `make helm-template` loop over `ci/*.yaml` under `set -e`, so
a chart with no values file there fails the build rather than being skipped. **One file per
configuration the chart supports** — not per way this module calls it — because a configuration
nobody renders is one nobody promised ([§2.2.1](../../../CONSTITUTION.md#2-modules)).

**Changing an existing chart's values schema is a `Chart.yaml` version bump**, and the chart may
have consumers other than yours. `grep` the `chart_path` locals before you edit one.

**At the root**, four or five files:

- `module_<capability>.tf` — the `module` block. Having one **is** how an environment ships it
  ([§4.4](../../../CONSTITUTION.md#4-composition)); there is no enable flag.
- `variables.tf` — the block describing what the cluster decides.
  **Do not restate the module's defaults here** ([§4.5](../../../CONSTITUTION.md#4-composition)):
  a version pin written at the root silently wins over the module's own, which makes the module's
  pin dead code that still reads as authoritative.
- `locals.tf` — whatever the root derives before passing it down.
- `outputs.tf` — only if something outside actually reads it.
- **`.deploy-values/<env>.tfvars` — and this one is gitignored.** No check will tell you it was
  skipped: the module plans clean and ships nothing, per environment, silently.

Nothing else needs registering. `TF_DIRS` and `CHARTS` in the [Makefile](../../../Makefile) are
globs, so the new directory is picked up on its own.

## 6. Close

- `make ci` — the same targets the pipeline calls.
- `make docs` — the cross-file checks from phase 4.
- **Move the spec's status from `draft` to `implemented`.** This is part of finishing the module,
  not a later tidy-up, and `make docs` fails while a built module's spec still says `draft`.
- Run the `@cluster` criteria against a real cluster, or say plainly which ones have not been
  run. An unverified criterion reported as passing is worse than one reported as pending.

---

## What this skill is not

**Not a substitute for reading the CONSTITUTION.** It names the rules that bear on the order of
work; it is not the set of rules a module must satisfy. Read
[CONSTITUTION.md](../../../CONSTITUTION.md) in full before phase 5.

**Not for changing an existing module.** That is
[§10.6](../../../CONSTITUTION.md#10-documentation): read the module's spec and every ADR it
links, first.

**Not for retiring one.** That is [resync-doc-to-code](../resync-doc-to-code/SKILL.md), which
runs the registration set in reverse.
