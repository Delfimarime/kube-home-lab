# 014. Exposed does not mean authorized

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-15 ·
revised 2026-08-15 (certificate material is now provisioned; the decision is unchanged)

**Exposing a workload does not oblige this repository to authorize it; where the workload cannot,
that job is the Gateway's.**

## Decision

**Exposing a workload does not oblige this repo to authorize it.** A module authorizes where
its workload can natively do so. Where the workload cannot, authorization belongs to the
Gateway — and this repo does not provision Gateways.

**No environment configured by this repo adds authorization to an exposed endpoint today.** The
OTLP ingest endpoint is open to anything that can reach it. That is a decision, taken for a
home lab of two nodes and one operator, and not an omission.

**Nothing here forbids it.** A Gateway that supports authentication may enforce it on the
listener an endpoint attaches to, with no change to any module and no new input: `section_name`
in the `gateway` contract ([ADR 007](007-modules-receive-credentials.md)) already names the
listener, so pointing an endpoint at a protected one is a call-site edit.

## Context

[REQ-06](../requirements.md) says a workload is unreachable from outside its cluster unless it
has been deliberately exposed. It says nothing about what happens to a request once it arrives,
and until now nothing had to: every exposed surface in this repo was a UI that authorizes
itself. Grafana delegates to an issuer and refuses anyone carrying no role
([ADR 013](013-roles-are-carried-in-the-token.md)). Keycloak *is* the issuer. In both cases the
question was answered by the workload, and the Gateway only had to deliver the request.

The observability storage module is the first exposed surface that cannot answer it. It
publishes an OTLP ingest endpoint so that something outside the cluster — a VM, a laptop, a
device — can push telemetry that cannot be scraped out of it. That endpoint has no notion of a
person, a session or a role, and nothing in this repo gives it one.

Authorization could live in exactly three places, and two of them turn out to be the same
place:

| Where | Mechanism | Owned by |
| --- | --- | --- |
| the workload | receiver-side authentication, hand-authored into the collector's configuration | the module — but only by hand-writing configuration it otherwise drives entirely through feature flags |
| the route | a middleware attached to the `HTTPRoute` through an `ExtensionRef` filter | the Gateway's implementation |
| the listener | client certificates, or whatever else that Gateway supports | the Gateway |

The second and third are the Gateway's, and [the Gateway is out of scope](../platform.md#scope)
— a per-environment prerequisite this repo never provisions.

A module was sketched to close that gap and then dropped: `ingress-gateway-api`, shipping
cert-manager, owning the `Gateway` resource, and minting a per-listener client CA plus server
and client certificates for every mTLS listener. It is recorded in the rejected alternatives
below rather than left as an unexamined "we could add auth later", because it was examined and
it was not small.

## Rationale

- **The endpoint is write-only, and that is the whole argument.** OTLP accepts telemetry and
  returns nothing; there is no query path through it. An unauthenticated *read* surface would
  disclose everything the stores hold and this decision would be indefensible. An
  unauthenticated *write* surface costs disk and data quality, both of which are visible,
  bounded and recoverable.
- **The failure mode is a full volume, not a leak.** Garbage series and a filled `local-path`
  PVC, on the volume that is already the storage module's weakest point. Bad, and bad in a way
  that shows up in Grafana rather than in somebody else's hands.
- **The guards that would actually help are not in this repo and never were.** Not publishing
  the hostname in a public zone, and a router that does not forward the port, are both free and
  both outside every boundary drawn here. Adding a bearer token inside the cluster while the
  name resolves publicly would be theatre with a maintenance cost.
- **mTLS was priced properly and it was a module.** cert-manager, a `Gateway` resource this repo
  would then own, a dedicated listener because a browser cannot present a client certificate,
  one client CA per listener so that "one listener, one client" is enforced rather than merely
  documented — and a rotation story that breaks the one client it exists for, because
  cert-manager renews the Secret in-cluster and the copy on the laptop does not change. That is
  a lot of moving parts standing between an operator and their own telemetry.
- **A bearer token is cheaper and buys less than it looks.** It is a static credential nobody
  rotates, shared by every pusher, and it defends against exactly what an unpublished hostname
  already defends against. The repo's own rule applies: a knob is turned once something hurts.
- **Authorizing in the workload would undo a decision already made.** The collector is driven by
  feature flags, not by hand-authored configuration; reaching in to add receiver authentication
  means owning a configuration file that the chart otherwise generates, and inheriting every
  future schema change in it.
- **REQ-06 was never a claim about authorization**, and reading it as one is the mistake this
  ADR exists to prevent. It asks that exposure be an act. Exposure here *is* an act — the OTLP
  route exists only when a `gateway` is supplied, and no backend is ever routed.

## Alternatives

- **Provision a Gateway here**, and with it the authorization an exposed endpoint needs. That was
  the shape of closing the gap when this was written, and it means owning a per-environment
  prerequisite — [§1.1](../../CONSTITUTION.md#1-boundaries) — for one endpoint's benefit.
- **Put authentication in front of the ingest endpoint** with a component of this repository's
  own. Rejected as disproportionate for two nodes and one operator: it is a service to run, keep
  patched and debug at 3am, in front of a surface whose whole risk is that somebody writes
  telemetry nobody asked for.
- **Do not expose the endpoint at all.** Honest, and it removes the capability the module exists
  to provide — pushing telemetry from something that cannot be scraped.

## Consequences

- **Anything that reaches the OTLP endpoint can write into the stores.** The stores are
  multi-tenant, and the tenant comes from the caller's own `X-Scope-OrgID` with nothing
  validating it — so a writer is distinguishable by cooperation, not by proof, and per-tenant
  limits cap the volume rather than the sender. That is a better answer to "the failure mode is
  a full volume" than this ADR had when it was written, and it is not attribution.
- **REQ-06 gains a boundary paragraph** in [requirements.md](../requirements.md), stating that
  it claims reachability and not what happens to a request that arrives. The other requirements
  with boundaries got them for the same reason: to stop a reader inferring a stronger claim
  than the text makes.
- **Grafana is unaffected.** Its route is the case where the workload does authorize itself, and
  this decision changes nothing about it. The asymmetry between the two exposed surfaces is
  intended: one carries a person and everything the stores hold, the other carries writes and
  returns nothing.
- **The absence is asserted, not assumed.** The storage module's acceptance criteria check that
  an unauthenticated push is accepted *and* that nothing can be read back through the same host
  — the second being the claim this decision actually rests on.
- **Reversible, and at two different prices.** At the listener: free, a call-site edit naming a
  different `section_name`, no module changes at all. At the route: one optional input carrying
  `ExtensionRef` filters, and one template line in the chart that renders the `HTTPRoute`.
  Neither is a redesign, which is why neither is being built now.
- Any future module exposing a workload with no authentication of its own inherits this
  decision rather than re-arguing it. One that exposes a *read* surface does not — that would
  be a new decision, and this ADR's rationale is where it would have to start.
- **The material for the reversal now exists, and the decision still stands.** The rejected
  `ingress-gateway-api` alternative above was priced as one module doing two jobs: minting
  certificates *and* owning the `Gateway`.
  [`certificate-management-cert-manager`](../modules/certificate-management-cert-manager/README.md)
  takes only the first half — it provisions a client authority and one shared client
  certificate ([REQ-14](../requirements.md)) and provisions no `Gateway` at all. The listener
  that demands them is still configured per environment, outside this repository, so *this
  repo* still adds no authorization to an exposed endpoint. What changed is that an environment
  choosing to is now a listener edit rather than a module that has to be built.
- **`OBS-21` is now environment-dependent.** It asserted that an unauthenticated push is
  accepted; where an environment points the OTLP route at an mTLS listener, it is not. The half
  this decision actually rests on — that nothing can be read back through that host — is
  unconditional and is what the scenario now asserts.
- **One client certificate, not one per pusher.** The rationale above named "one client CA per
  listener so that *one listener, one client* is enforced rather than merely documented" as part
  of the price. That is not what was built: the certificate module issues a single shared client
  certificate, on the grounds that per-client identity is a distinction nothing downstream
  reads. The rotation problem this ADR named is unchanged in
  kind and smaller in reach: one copy to refresh instead of one per pusher.
