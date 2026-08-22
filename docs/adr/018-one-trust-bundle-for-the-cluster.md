# 018. One trust bundle for the cluster, not a mount per workload

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-15

## Context

[REQ-14](../requirements.md) is satisfied by certificates from an authority this repo owns
rather than a publicly-trusted one, which carries a cost that lands outside the module issuing
them: a workload calling another
workload over its external hostname has to trust the root, or it fails with
`x509: certificate signed by unknown authority`.

That is not hypothetical and it is not rare. A console wired to `oidc` fetches the issuer's
discovery document, exchanges the authorization code and reads userinfo — three server-to-server
calls made by its own HTTP client, all validated against the container's trust store. Without
the root, [REQ-01](../requirements.md) does not work at all, and the symptom is a login that
redirects correctly and then fails on the callback, which reads as a broken OIDC configuration
rather than a trust problem.

Kubernetes Secrets do not cross namespaces, so the authority's certificate has to arrive in each
consuming namespace somehow. Three ways were real:

- **A hand-made ConfigMap per namespace**, documented as a prerequisite alongside the Secret
  examples. Consistent with how every other prerequisite here is handled.
- **A bundle distributed by a controller**, so a namespace has it before anything asks.
- **Avoid the trust requirement**, by pointing server-to-server calls at in-cluster addresses
  over plain HTTP so that no certificate is validated. Some issuers support this through a
  backchannel hostname; it was rejected because it makes each consumer's configuration carry a
  second address that must agree with the first, and because it is not a property every issuer
  has.

## Decision

**One bundle, distributed to every namespace by a controller.** A single resource names the
source and every namespace receives the same ConfigMap.
[`certificate-management-cert-manager`](../modules/certificate-management-cert-manager/README.md)
provisions it; every consumer mounts it.

**The bundle carries the server authority only, and includes the public roots.**

This is platform-scoped because reversing it changes every module wired to `oidc`, not the
module that publishes the bundle.

## Rationale

- **A per-namespace prerequisite is one that gets forgotten in the namespace that needed it.**
  Every other prerequisite here is a Secret whose absence produces a workload that does not
  start — visible immediately. A missing CA produces a workload that starts, serves, and fails
  one code path, which is the failure mode this repo is least able to notice.
- **The consumer count only goes up.** One console today; every future consumer wired to `oidc`
  after that. A mechanism that costs one Deployment once is cheaper than a documented step
  repeated per namespace, and it is cheaper the second time it is needed rather than the
  twentieth.
- **Including the public roots is not optional, it is the whole safety of the thing.** A bundle
  containing only the lab root, mounted over a container's `ca-certificates.crt`, replaces the
  public roots rather than adding to them — so the workload trusts this lab and nothing else on
  the internet. Including the public set means a consumer can mount the bundle as its whole
  trust store without losing anything.
- **The client authority does not belong in it.** Nothing inside the cluster verifies a client
  certificate; that is the Gateway's job
  ([ADR 014](014-exposed-does-not-mean-authorized.md)), and the Gateway reads the client CA's
  Secret directly. Shipping it to every namespace would distribute material with no reader.
- **It belongs to the certificate module rather than a new one.** Issuing certificates nobody
  trusts is not certificate management, so distribution is the other half of one capability —
  one more entry in that module's `List` generator, which is what
  [ADR 005](005-modules-are-applicationsets.md) exists for.

## Consequences

- **One more Deployment and one more CRD** in a repo that counts pods. It is the cost of
  choosing an internal authority rather than a public one; a publicly-trusted certificate would
  have needed neither.
- **The bundle is load-bearing for identity.** With no backchannel split, a consumer reaches the
  issuer over TLS on every server-to-server call. If the bundle is missing or unmounted, OIDC
  fails. This is the first cross-module dependency here that is not an address.
- **A consumer still has to mount it.** Distribution puts the ConfigMap in the namespace;
  nothing makes a chart consume it. Each consumer's spec names the mount, and a consumer that
  forgets fails exactly as it would have without distribution.
- **Rotating the root is one edit with cluster-wide reach.** The bundle updates everywhere
  automatically, which is the benefit; every workload holding the old bundle in memory keeps it
  until restarted, which is the caveat.
- **Sync order matters** inside the module that provisions it: the distributor uses cert-manager
  to issue its own webhook certificate, so it syncs after it, and the bundle after both.
- **Reversible.** Removing it means documenting a ConfigMap per namespace, which is the option
  this decision rejected. Nothing else changes.
