# 026. Roles decide the operation, relationships decide the resource

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-23

## Context

[ADR 013](013-roles-are-carried-in-the-token.md) settled how a person's permissions arrive:
`<SLUG>_<ROLE>` at `resource_access.<slug>.roles`, mapped by each consumer to its own native
roles, and a principal carrying none is refused. That answers one question completely — *may this
person use this service, and at what level* — and it is the right answer to it.

It cannot answer a second one. **May this person act on this particular object?** A token cannot
carry that: the claim would grow with the data rather than with the person, and a grant made after
the token was issued would not be in it. Every product that needs per-object decisions therefore
keeps its own table of them — which is precisely the failure
[REQ-13](../requirements.md) names, arriving one layer below where ADR 013 stopped it.

Applications deployed into these environments need that second answer. Nothing here provides it,
so each of them would answer it privately, in its own schema, with its own vocabulary and its own
idea of what absence means.

## Decision

**Roles decide whether a person may perform an operation at all. Relationships decide whether
they may perform it on a particular resource.**

[ADR 013](013-roles-are-carried-in-the-token.md) keeps the first half unchanged and is not
superseded — it was never wrong, only narrower than the problem turned out to be.

The second half is a **relationship store**: a service holding tuples of the form *subject —
relation — object*, queried at decision time rather than carried in a token.

Three rules follow:

1. **The role is checked first, and a failure there is a denial.** A principal with no recognised
   role never reaches a relationship check. The two are `AND`, never `OR`, and never a fallback
   for one another.
2. **Relationships are never in the token.** They are read from the store per decision. A token
   that appears to carry one is a token being used for something this decision says it is not for.
3. **The relationship store is not an identity source.** It holds no users and no credentials —
   only subject identifiers minted by the environment's issuer. Who someone *is* stays
   [REQ-01](../requirements.md)'s question.

## Rationale

- **A token has a size and a lifetime; per-object grants have neither.** This is the whole reason
  the split exists rather than being an extension of ADR 013. Sharing an object with someone at
  11am must take effect before their token expires at noon, and a claim listing every object they
  can reach is a claim that grows without bound.
- **Two mechanisms with two failure modes beats one mechanism with a vague one.** "Denied because
  you have no role" and "denied because you have no relationship to this object" are different
  facts, and a consumer that can only say "denied" is a consumer nobody can debug.
- **It keeps ADR 013 intact.** Superseding it would have meant re-answering a question that was
  answered correctly, and would have put every existing consumer's login behaviour back in play
  for a change none of them needs.
- **The store is swappable because consumers receive an address**, which is
  [REQ-09](../requirements.md) applied here exactly as
  [ADR 007](007-modules-receive-credentials.md) applies it to issuers. What is *not* swappable is
  the model written into it, and that is stated where the store is chosen.
- **A consumer that needs only coarse access ignores this entirely** and is unchanged. Most of
  what runs here is in that category and stays there.

## Consequences

- **Authorization can now be unavailable.** A role check reads a token the caller already holds
  and works offline; a relationship check is a network call to a service that can be down, slow or
  wrong. Every consumer that adopts this gains a runtime dependency on the answer to "may I", and
  must decide what it does when there is no answer. **Failing closed is the only defensible
  default**, and it means the store being down denies rather than admits.
- **There are now two places to look when somebody is denied**, and only the consumer knows which
  applied. A consumer that does not distinguish the two in its own logs makes this worse rather
  than better.
- **Relationship data is a third kind of state.** It is not in git, not in a token, and not
  regenerable from either — it accumulates as people use the system. Where it lives is the
  concern of whatever module provides the store, and that module owes an account of what losing
  it costs.
- **Nothing in this repository consumes this today.** The platform modules here authorize coarse
  access to their own UIs and nothing more; the consumers are applications deployed alongside
  them. That is a deliberate difference from the shape of a capability with no consumer at
  all — the decision is being made because a consumer is coming, and if none arrives this is a
  service running for nobody.
- **A relationship model is not portable between stores.** The tuple shapes and the modelling
  languages differ, so the swappability above is real at the address and expensive in substance.
