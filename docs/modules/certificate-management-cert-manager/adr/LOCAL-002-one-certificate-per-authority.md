# LOCAL-002. One certificate per authority

**Status:** accepted · **Scope:** module — `certificate-management-cert-manager` ·
**Date:** 2026-08-15

## Context

[LOCAL-001](LOCAL-001-certificates-from-an-internal-ca.md) settles where certificates come from.
It settles nothing about how many there are.

The obvious shape is a list of named clients — `clients = ["laptop", "nas"]` — each getting its
own certificate, so that the mTLS listener can tell one pusher from another. That is what
[ADR 014](../../../adr/014-exposed-does-not-mean-authorized.md) priced when it examined and
rejected an `ingress-gateway-api` module, and it named the rotation problem in passing: a
certificate renewed in-cluster does not renew the copy on the laptop.

There is a second problem with it, and it is the one that decides this.

## Decision

**Each authority issues exactly one certificate.** There is no client list. The `server`
authority issues the wildcard the Gateway serves; the `client` authority issues the single
certificate every external pusher presents.

The invariant is in the type rather than in prose — an authority declares the one certificate it
signs, so a second one cannot be added without adding an authority:

```hcl
certificate_authorities = {
  server = {
    common_name = "lab server CA"
    certificate = { dns_names = ["*.lab.internal"], usages = ["server auth"] }
  }
  client = {
    common_name = "lab client CA"
    certificate = { common_name = "lab client",     usages = ["client auth"] }
  }
}
```

Two authorities is the default and not the limit. A third is one map entry.

## Rationale

- **Per-client certificates would produce a distinction nothing here can consume.** The stores
  run with multitenancy on, but the tenant a write lands in comes from `X-Scope-OrgID`, not from
  the certificate that carried it — deliberately, so the two stay orthogonal. The Gateway
  validates the certificate and applies no per-client policy. There is one operator. A distinct
  identity per pusher would be a fact the whole stack is arranged not to read.
- **A distinction nothing reads is an invention, not a design.** The same test refuses three
  hostnames resolving to one socket, or a per-signal address where one endpoint serves all
  three: if no consumer can act on the difference, encoding it costs maintenance and buys a
  label. Per-client certificates fail that test here.
- **Two authorities, not one, is where the real separation belongs.** A single root signing both
  halves would let the wildcard server certificate authenticate as a client, since the mTLS
  listener trusts a CA and not a purpose. Whether that is caught depends on the Gateway
  enforcing Extended Key Usage, which is implementation-specific and not something a boundary
  should rest on. Splitting the authorities makes it structural.
- **The rotation problem shrinks rather than being solved.** ADR 014 named it correctly: renewal
  in-cluster does not renew the copy outside. With one certificate there is one copy to refresh
  and one calendar entry, instead of a per-pusher schedule nobody keeps.
- **Configurable, because the shape of the answer should not depend on the number.** Two is what
  this lab has. The map means a third authority — a second lab, a separate purpose — is an
  entry, not a redesign.

## Consequences

- **Revocation is all or nothing.** Losing the laptop means reissuing the client certificate,
  and every other pusher stops working at that moment until it is refreshed. On two or three
  pushers that is an afternoon; it is stated here so it is not discovered during one.
- **There is no per-sender attribution**, which is unchanged from
  [ADR 014](../../../adr/014-exposed-does-not-mean-authorized.md) rather than newly given up.
  What replaces it is tenancy: a pusher that sets its own `X-Scope-OrgID` is distinguishable in
  the stores, by cooperation rather than by proof.
- **The client certificate is a shared credential**, and shared credentials are the thing this
  repo otherwise avoids. It is defensible because it authorizes writing telemetry into a store
  and nothing else — the stores are never routed, so holding it grants no read path.
- **Adding a genuinely separate pusher means adding an authority**, not a certificate. That is
  more ceremony than a list entry, and it is the right amount: a second authority is a claim
  that the two really are different, which is exactly the claim a per-client certificate was
  making without evidence.
- **Reversible cheaply.** Going back to per-client certificates means a `clients` map under one
  authority and a loop; nothing about the authority chain changes. The reasoning above is what
  would have to stop being true first.
