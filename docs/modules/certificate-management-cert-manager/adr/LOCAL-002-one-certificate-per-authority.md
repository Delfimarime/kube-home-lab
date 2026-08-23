# LOCAL-002. Two authorities; certificates are named, and mTLS is a pair

**Status:** accepted · **Scope:** module — `certificate-management-cert-manager` ·
**Date:** 2026-08-15 · revised 2026-08-15 (the 1:1 rule is dropped; the split is kept)

> **What changed.** This ADR originally read *One certificate per authority*, enforced in the
> input type: an authority declared the single certificate it signed, so a second certificate
> required a second authority. That rule is gone — an environment needs more than one hostname
> and inventing an authority per hostname was ceremony without a claim behind it. **The
> two-authority split is kept**, because it is what CERT-05 rests on, and it is the half of this
> decision that was load-bearing.

**There are exactly two authorities, `server` and `client`, and no list of clients.**

## Decision

**There are exactly two authorities.** `server` signs what serves TLS; `client` signs what
authenticates to a listener. Neither is configurable, and there is no map of authorities.

**Certificates are named entries, and there may be any number.** One is always issued —
`default`, the wildcard `*.<domain>` and the shared client identity paired with it. The rest come
from `certificates`, keyed by name.

**An entry's `mode` decides how many certificates it produces, not what usages one carries.**

| `mode` | Produces | Secrets |
| --- | --- | --- |
| `tls` | a server certificate, from the `server` authority | `<release>-<name>-tls` |
| `mtls` | **a pair** — that certificate *and* a client certificate from the `client` authority | `<release>-<name>-tls`, `<release>-<name>-client` |

## Context

[LOCAL-001](LOCAL-001-certificates-from-an-internal-ca.md) settles where certificates come from.
It settles nothing about how many there are, or how a caller asks for one that needs a client
counterpart.

The obvious shape is a list of named clients — `clients = ["laptop", "nas"]` — each getting its
own certificate, so the mTLS listener can tell one pusher from another. That is what
[ADR 014](../../../adr/014-exposed-does-not-mean-authorized.md) priced when it examined and
rejected an `ingress-gateway-api` module, and it named the rotation problem in passing: a
certificate renewed in-cluster does not renew the copy on the laptop.

## Rationale

- **mTLS is a pair, not a usage, and this is the whole point.** The simpler rendering — add
  `client auth` to the server certificate's `usages` — would defeat the two authorities. The
  listener trusts a CA, not a purpose; a certificate signed by the `server` authority carrying
  `client auth` is a certificate that can authenticate as a client, which is exactly what
  `CERT-05` asserts cannot happen. Two authorities make that structural rather than dependent on
  the Gateway enforcing Extended Key Usage, which is implementation-specific and not something a
  boundary should rest on.
- **The 1:1 rule bought nothing once there was a second hostname.** It made "a second certificate
  is a claim the two are genuinely different" true by construction — but every hostname in a
  cluster is genuinely different, and none of them is a different *authority*. The rule was
  measuring the wrong thing.
- **Two authorities is not an implementation detail that happened to be two.** It is one per
  direction of the handshake, which is the number the protocol has. A third would be a third
  direction.
- **The shared client identity survives as the default.** `default`'s client half is the one
  every external pusher presents unless something needs its own. Per-client certificates remain
  a distinction most of this stack cannot read: the tenant a write lands in comes from
  `X-Scope-OrgID`, not from the certificate that carried it
  ([ADR 017](../../../adr/017-stores-are-multi-tenant.md)), and the Gateway applies no per-client
  policy. **Don't add an `mtls` entry without a reader for the distinction.**
- **A name is enough to derive everything else.** An entry with no `dns_names` gets
  `<name>.<domain>`; its client half gets `CN=<name>.<domain>`. Nothing makes a caller repeat the
  domain it already declared.

## Alternatives

- **A list of named clients** — `clients = ["laptop", "nas"]` — one certificate each, so an mTLS
  listener can tell one pusher from another. This is the shape
  [ADR 014](../../../adr/014-exposed-does-not-mean-authorized.md) already priced and rejected: it
  buys per-caller identity that nothing here consumes, and it multiplies the rotation problem,
  because a certificate renewed in-cluster does not renew the copy on the device holding it.
- **Configurable authorities.** A map instead of two fixed ones. It makes the trust bundle's
  contents a per-environment question ([ADR 018](../../../adr/018-one-trust-bundle-for-the-cluster.md))
  and adds a dimension no environment has asked for.

## Consequences

- **Revocation is per entry, and all-or-nothing within one.** Losing a laptop that holds
  `default`'s client certificate means reissuing it, and every other holder of that certificate
  stops working until refreshed. Giving a pusher its own `mtls` entry narrows that to one holder
  — which is the reason to add one, and the only one.
- **There is no per-sender attribution by default**, unchanged from
  [ADR 014](../../../adr/014-exposed-does-not-mean-authorized.md). What replaces it is tenancy: a
  pusher setting its own `X-Scope-OrgID` is distinguishable in the stores by cooperation rather
  than by proof.
- **`default` is a reserved key** and the module refuses it in `certificates`. It is derived from
  `domain`, so an entry of that name would either be ignored or silently replace the wildcard.
- **The rotation problem scales with entries.** One shared client certificate was one calendar
  entry; N `mtls` entries is N. `renew_before` defaults to `720h` on every client half so the
  expiry metric describes the certificate actually deployed, but nothing refreshes the copy
  outside the cluster.
- **The input type no longer enforces anything about counts.** What stops the two authorities
  collapsing into one is that they are not configurable at all — a stronger guarantee than the
  1:1 rule ever gave, and the reason dropping it costs nothing here.
