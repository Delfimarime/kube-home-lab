# 027. A machine caller is authorized by scope, not by a role

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-23

## Context

[ADR 013](013-roles-are-carried-in-the-token.md) is written about people. Its own words are *"what
a person may do comes from the token"*; its vocabulary is `ADMIN` and `VIEWER`; and its second
rule — a principal carrying no recognised role is refused rather than admitted at a reduced
level — exists to stop a product's default-viewer behaviour letting somebody in at a login screen.

[ADR 026](026-roles-decide-the-operation-relationships-decide-the-resource.md) introduces a
relationship store whose contents have to be configured from outside the cluster, by a pipeline.
That caller has no browser, performs no login, and is not a person. `VIEWER` means nothing to it:
it either writes relationship data or it does not.

**It could still have been given a role.** A service account in the issuer can hold
`resource_access.<slug>.roles` exactly as a human can, and doing so would have kept one vocabulary
across the platform. Two things argue against it, and they are not equally weighted.

The binding one is mechanical. The proxy that fronts a write path validates a JWT against its
issuer, its audience and the scope claims — `scp`, `scope`, `scopes` — and **cannot match a nested
claim** such as `resource_access.<slug>.roles`. Reaching a role would mean adding an authorizer
that calls out to a second service written for the purpose, to answer a question the issuer has
already answered.

## Decision

**A machine caller is authorized by OAuth2 scope and audience. Roles are for people.**

Granting a pipeline access to a protected surface means two things in the issuer, and nothing
anywhere else:

1. a **client scope** on its client, named for what it may do — `keto:write`;
2. an **audience** naming the service it is calling, so a token minted for one service is not
   accepted by another.

The proxy checks both, per route. [ADR 013](013-roles-are-carried-in-the-token.md) is unchanged
and continues to govern every human principal.

## Rationale

- **The proxy can check a scope and cannot check a role.** This is the reason that actually
  binds, and stating it plainly is better than dressing the decision as pure principle: uniformity
  with ADR 013 was achievable and was rejected on cost, not on doctrine.
- **Scope is the standard answer for a client credentials grant.** A scope bounds how much of a
  subject's authority a particular grant carries. Where there is no user to delegate from, subject
  and client are one thing, nothing is left to bound, and the client's own scopes are the whole of
  its authority. Using them is what every OAuth2 implementation expects.
- **The vocabulary genuinely does not fit.** `ADMIN`/`VIEWER` describes what somebody sees in a
  UI. A pipeline has no reduced mode worth naming, and ADR 013's rule 2 protects against a login
  behaviour that does not occur here.
- **Audience does work that a role would not.** A role says what a subject is anywhere; an
  audience says which service a token was minted for. For a credential that will sit in a
  pipeline's configuration and be used unattended, narrowing *where it is accepted* is worth more
  than narrowing what it is called.

## Consequences

- **There are two vocabularies now, and a reader has to know which one they are looking at.** The
  tell is the principal: a person carries `<SLUG>_<ROLE>`, a machine carries a scope and an
  audience. A module that authorizes both says which applies to which.
- **Revisit this if the proxy gains nested-claim matching.** At that point the mechanical argument
  disappears and only the vocabulary argument remains, which is the weaker of the two. This is the
  condition under which one vocabulary becomes worth the change, and it is worth checking rather
  than assuming it never happens.
- **Nothing compares a scope name to what the service behind it enforces.** `keto:write` grants
  whatever the route it unlocks grants, and the two agree only because somebody wrote both. A
  scope that is not the one a route requires produces a refusal, which is safe; a route requiring
  a scope broader than intended produces access nobody notices.
- **Granting a pipeline is a change in the issuer**, not in this repository — the same consequence
  ADR 013 records for people, and it means machine access is no more visible in a `git log` here
  than human access is.
- **A machine caller has no partial grant.** There is no `VIEWER` equivalent, so a pipeline that
  should only read is given no scope for writing rather than a lesser one. Where a surface needs
  both, that is two scopes and two routes, not one scope with a level.
