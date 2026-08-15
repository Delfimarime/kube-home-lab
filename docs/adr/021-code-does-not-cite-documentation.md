# 021. Code does not cite documentation

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-15

## Context

Until now the convention was the opposite one, stated in the agent guidance as *"code implements
the spec and cites the ADRs it follows"*. It was followed: twenty-two citations across nine files
— `(ADR 010)`, `[ADR 007]`, `REQ-09`, `CERT-05`, `LOCAL-001`, `§3.4` — in `.tf` comments, Helm
template headers, `values.yaml` and a `Chart.yaml`.

Four ID schemes reached into code, and none of them was checked by anything. Two weeks of
editing showed what that costs: ADR 015 was superseded by ADR 020, ADR 011 lost half its
decision, ADR 006 was absorbed into 007, and LOCAL-002 was rewritten to mean nearly the opposite
of its title. Every citation of those in code was, at the moment of the edit, either wrong or
pointing at something that no longer said what the comment implied — and nothing failed, because
a citation in a comment is a link with no referent check.

There is a second cost, quieter. A comment reading `# ADR 018` explains nothing to a reader who
does not have the document open. It is a promise that the reason exists elsewhere, which is
strictly worse than the reason.

## Decision

**No file under `modules/`, no root `.tf`, and no chart file cites a document.** Not an ADR
number, not a `REQ-NN`, not a Gherkin scenario ID, not a constitution section.

**A comment states the reason itself**, in enough words to stand alone.

**Traceability runs one way: documentation → code.** A spec names the module it specifies and an
ADR describes what it affects. Nothing points back.

## Rationale

- **A citation is an unchecked link, and this repository renumbers.** Superseding, absorbing and
  rewriting ADRs are all normal here — three happened in one week. Every one silently invalidated
  citations that no tool could find and no test could fail.
- **The reason is what a reader needs; the citation is what an author remembered.** *"A listener
  trusts a CA and not a purpose, so two authorities are what stop a server certificate
  authenticating as a client"* is useful at the point of edit. `(CERT-05)` is a lookup.
- **It is the same rule the documentation already lives by.** Nothing is restated between the
  requirement, specification, decision and guidance layers. A citation in code made code a fifth
  place an ID appeared, and the only one outside the system that maintains them.
- **Removing them found stale prose.** Rewriting each citation into its reason forced a reading
  of what the comment actually claimed. Several no longer described the code around them.
- **The reasons compress well.** Every citation removed here became one or two clauses. A reason
  that genuinely cannot be stated in a line or two is a signal the code needs its spec read —
  and the spec is where a reader should be sent, by the module's own documentation, not by a
  parenthesis in a comment.

## Consequences

- **`grep 'ADR 010'` no longer finds the code an ADR governs.** That reverse index is gone, and
  it was the one real argument for citations. What replaces it is the specification: a module's
  `README.md` lists the decisions it obeys, and the module is one directory.
- **Comments are longer**, by roughly a clause each. This is the cost, paid once per comment, and
  it buys a file that explains itself with nothing open beside it.
- **A comment can now drift from its ADR without either being wrong-looking.** Nothing links
  them, so nothing shows the divergence. The mitigation is the same one the doc layers already
  use — the ADR's Consequences section is what a reader checks before changing a rule — and it is
  weaker here. Accepted: a citation that silently rots is not better than prose that silently
  ages.
- **The guidance that said the opposite is withdrawn.** *"Code implements the spec and cites the
  ADRs it follows"* becomes *"code implements the spec and carries its reasons"*.
- **This says nothing about code referencing code.** The `lab-pki` chart's `_helpers.tpl` notes
  that `locals.tf` restates its naming formulas, and that stays: both are files in this
  repository, both fail visibly when they disagree, and the round-trip check exists to prove it.
