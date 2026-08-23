---
name: resync-doc-to-code
description: Bring this repository's documentation back into agreement with the code and with itself — the mechanical checks behind `make docs`, the judgement half a script cannot do, and the registration set run in reverse when a module or requirement is retired.
---

# Resyncing documentation to code

Two audits, run at the same moment because they share one map of which file carries which claim:

- **Docs against the code** — a version in prose against the pin in `.tf`, a spec's `Inputs`
  against its `variables.tf`, a spec at `draft` while its module runs.
- **Docs against each other** — every table listing the same set, cross-references resolving,
  retired numbers not reused.

Both matter. The second is the one that actually breaks: the last module removal left two
descriptions of the departed thing behind, because they said what it did without naming it.

---

## The mechanical half — `make docs`

`make docs` runs [check-docs.py](check-docs.py) beside this file. Everything it checks is
deterministic — a link resolves or it does not:

| Check | Catches |
| --- | --- |
| Links resolve | a moved or deleted file still linked |
| Anchors resolve | a renamed heading, which no file-existence check sees |
| No duplicate headings | two `### Status` sections, where a link reaches whichever came first |
| Spec index ↔ folders | a spec listed with no folder, or a folder listed nowhere |
| Every decision is in a table | an ADR written and never indexed |
| Every module is named in `README.md` and `platform.md` | the leftovers a removal produces |
| Spec status ↔ `modules/<name>/` | `draft` while the module runs, `implemented` while it does not, or a status that is neither |
| Every built module has a spec | code with no spec, which is [§10.2](../../../CONSTITUTION.md#10-documentation) in reverse |
| Scenario IDs are unique, and every cited one exists | an ID reused for a second scenario, or a matrix row citing one that is gone |
| Every ADR has a lede and the five sections in order | a decision written in the old Context-first shape, or with no `Alternatives` |
| No code file cites a document | [§10.3](../../../CONSTITUTION.md#10-documentation) |
| Chart READMEs are generated | a `helm/<chart>/README.md` somebody typed, which is a second copy of the values schema and free to disagree with it |

**Run it first.** It is free and it narrows what is left to read.

**`make ci` adds one more that `make docs` cannot.** `make helm-docs-check` regenerates every
chart README from its `values.yaml` comments into a temporary directory and fails on any
difference, which is how a generated file that lives in git stays worth reading. It is not part of
`make docs` because it needs `helm-docs` installed, and skips itself when the tool is absent —
`make docs` deliberately needs nothing but the python already on the machine.

**Its false negatives are the point of the rest of this file.** It reads structure, never
meaning: a spec can pass every check above while describing a module that no longer behaves that
way.

## The judgement half

Nothing below can be checked by a script. Work module by module; for each, read its spec, its
`variables.tf` and its `outputs.tf` together.

**Inputs against `variables.tf`.** Every documented field still exists with that name, type and
default; every field a caller must set is documented. The failure is silent in both directions —
an undocumented input is one nobody sets, and a documented one that was renamed is a caller's
plan error.

**Outputs against `outputs.tf`.** Named for the capability and not the product
([§2.1](../../../CONSTITUTION.md#2-modules)), and carrying addresses, never credentials.

**Versions.** Numbers live in code, and the documentation deliberately holds very few of them —
so any version in prose is either an upstream fact worth stating or drift. Check each against its
pin. A pin appearing twice is its own bug: a root default silently overrides a module's, which
makes the module's dead code that still reads as authoritative
([§4.5](../../../CONSTITUTION.md#4-composition)).

**Acceptance criteria.** Does each scenario still describe what the code does? A criterion that
quietly stopped being true is worse than a missing one, because it reads as verified.

**ADR consequences.** The `Consequences` section is what someone reads six months later to find
out what breaks if they change it. When the world moves — a pre-1.0 dependency reaches 1.0, an
upstream renumbers — revise the consequence **in place with a dated note saying what it used to
say and why it changed**, rather than deleting it. The old reasoning is the record of why the old
answer looked right.

**ADR alternatives.** `make docs` checks that the section *exists*; only a reader can tell whether
it is still true. This is the section that decays fastest and matters most: an option rejected on
a fact that has since changed — a project that was unmaintained and now is not, a chart that did
not exist and now does — is a decision worth reopening, and nothing else in the file will say so.

**Prerequisites.** Every credential input has its `kubectl patch` and its restart
([§5.2](../../../CONSTITUTION.md#5-secrets)).

**A spec's `Decisions:` header, against what those decisions now say.** `make docs` checks that
every ADR is *indexed*, never that a spec citing one also cites what replaced it — so a partial
supersession leaves every spec pointing at the clause that moved. When ADR 027 took the
chart-location clause out of ADR 010, all five specs kept citing 010 alone and none gained 028;
that was fixed on 2026-08-23. **After any supersession, read the citing specs**, which
`grep -l` finds from the superseded ADR's number.

**Open items and `AGENTS.md`.** Both hold live state, which is the fastest-rotting kind. An open
question that has since been answered, or a "blocked" entry whose blocker is gone, actively
misleads.

**And check `AGENTS.md` is not quietly holding facts.** It says of itself that no entry restates
something a file already holds — a version, a count, a list of modules — because that copy is the
one that goes stale while nothing checks it. Two crept in and were removed on 2026-08-23; one of
them had gone stale within hours of being written. A number in that file is the thing to look for.

## Retiring — the registration set, in reverse

Removing a module or a requirement touches the same files as adding one, plus several things that
are easy to miss.

1. **`git rm -r docs/modules/<module>` leaves empty directories behind**, because git tracks
   files and not folders. Remove them.
2. **Grep for what the thing *did*, not only for its name, and do it case-insensitively.** The
   description that survives a removal is the one that never named the product — a module for
   audit trails leaves the word "audit" behind in a scope line and a domain model. Search for the
   capability, the product, the requirement ID and the scenario prefix, separately. The last
   removal here left the product name in four ADRs and a case-sensitive `grep` found none of
   them, because every one of them was a capitalised sentence opener.
3. **An ADR that names it in *Context* or *Rationale* is history and the argument stays** — but
   the name goes, replaced by what it was an example of. An ADR that names it in *Consequences*,
   in the present tense, is stating something now false and is the one that actually misleads.
4. **Requirements:** drop the row and the matrix row, and drop its scenario IDs from any *other*
   requirement's `Verified by` list.
5. **Retire the number, do not reuse it** — as [REQ-04 and REQ-07
   were](../../../docs/requirements.md), with a paragraph saying what it required and why it went.
   A future reader finding a gap should find the reason, not a different requirement.
6. **`AGENTS.md`** gets the live-state entry: what was dropped, when, and that it is not to be
   reinstated without a new requirement.
7. **The ADRs stay.** A decision behind something that was removed is still the record of why it
   looked right, and the numbers stay retired too.

Then `make docs`, which will now fail on anything still pointing at what is gone.

## Reporting

Say what was checked, what changed, and **what could not be verified** — a `@cluster` criterion
with no reachable cluster is pending, not passing. A resync that reports everything as agreeing
is only worth anything if the things that did not agree would have been reported.
