# LOCAL-001. Certificates come from an internal CA, not from a public one

**Status:** accepted · **Scope:** module — `certificate-management-cert-manager` ·
**Date:** 2026-08-15

**Every certificate is issued by a self-signed authority this module provisions — no ACME, no public CA, no registered domain.**

## Decision

**Every certificate is issued by a self-signed authority provisioned by this module.** There is
no ACME, no public CA, no registered domain and no egress requirement. `.lab.internal` stays.

The chain per authority is: a self-signed `Issuer`, a CA `Certificate` it signs, and a
`ClusterIssuer` backed by that CA's Secret. Leaf certificates reference the `ClusterIssuer`.

## Context

Something has to issue the certificate the environment's Gateway serves, and something has to
issue the client certificates an mTLS listener validates. Those are two different jobs and only
one of them has a public option.

A publicly-trusted certificate needs a public certificate authority, which means ACME. HTTP-01
is unavailable — it requires an inbound connection from the internet to a workload, and nothing
here is reachable from outside the LAN. DNS-01 does not: it proves control by writing a TXT
record in a public zone, so the services themselves stay unreachable. That makes DNS-01 the only
public option, and it carries two hard prerequisites:

- **A domain, publicly delegated.** `.lab.internal` cannot be one. ICANN reserved `.internal`
  for private use in 2024 precisely so that it can never be publicly resolvable, so no public CA
  can ever issue for a name under it. Choosing DNS-01 means every hostname in every var file
  moves to a registered domain.
- **Outbound egress** from the cluster to the ACME endpoint and to the DNS provider's API. This
  repo currently assumes nothing about egress at all.

The client certificates have no public option in any case. No public CA issues client
certificates for a private mTLS listener, so an internal authority exists in this environment
whichever way the server half is decided.

## Rationale

- **An internal CA exists either way.** The mTLS half cannot be public. Running one authority
  rather than one authority plus an ACME account is the smaller system, and the smaller system
  is the one still understandable after six months
  ([REQ-11](../../../requirements.md)).
- **The public option's cost is a domain and an egress assumption**, and both are permanent.
  A domain is a yearly renewal in someone's name and a DNS credential in every environment;
  egress turns a stack that currently talks only to itself into one with an external dependency
  that fails on a schedule nobody watches.
- **Hostnames stay put.** DNS-01 would move every hostname in every var file, and hostnames are
  already load-bearing — [ADR 007](../../../adr/007-modules-receive-credentials.md) makes them
  the one value the issuer and its consumers must agree on.
- **The certificates are declared, which is the actual requirement.**
  [REQ-14](../../../requirements.md) asks that certificates come from a declared source rather
  than being made by hand. A self-signed authority satisfies that exactly as well as a public
  one; what a public CA additionally buys is *third-party trust*, and the price of not having it
  is paid in trust distribution rather than in correctness.

## Alternatives

- **A publicly-trusted certificate over ACME DNS-01.** The only public option that works here —
  HTTP-01 needs an inbound connection from the internet and nothing is reachable from outside the
  LAN. It costs a registered domain, a public DNS zone and a credential to write to it, for names
  nobody outside the LAN resolves.
- **Certificates made by hand with `openssl`.** No component to run, and each one becomes a
  resource nobody renews and nothing records — [REQ-08](../../../requirements.md)'s problem
  arriving with a deadline attached.
- **One authority for both jobs.** Fewer objects, and it means anything that can serve TLS can
  also authenticate as a client — see [LOCAL-002](LOCAL-002-one-certificate-per-authority.md).

## Consequences

- **The root must be trusted on every device that opens a browser here.** One installation per
  laptop, phone and tablet, and one more for every device added later. This is the recurring
  cost of the decision and it is not small in aggregate; it is simply cheaper than a domain plus
  egress plus a hostname migration.
- **Workloads that call another workload over its external hostname need the root too**, or they
  fail with `x509: certificate signed by unknown authority`. Grafana fetching Keycloak's
  discovery document is the case that exists today, and it will not be the last. Distributing
  the root inside the cluster is a decision of its own — see
  [ADR 018](../../../adr/018-one-trust-bundle-for-the-cluster.md).
- **Nothing outside the LAN will ever trust these certificates**, which is correct, because
  nothing outside the LAN is meant to reach them.
- **Losing the CA's namespace loses the CA.** The Secrets holding the authorities' private keys
  are the only objects in this repo that cannot be regenerated into the same value. Reissuing is
  mechanical; redistributing a new root to every device is not. Back up those Secrets or accept
  that a cluster rebuild is also a trust-distribution event.
- **Reversible, at the price it always had.** Adopting ACME later means registering a domain,
  moving hostnames, adding a DNS credential and an egress assumption, and swapping one
  `ClusterIssuer` for another. The client authority stays regardless, so the reversal is partial
  by construction.
