# Module: certificate-management-cert-manager

**Status:** draft ·
**Satisfies:** [REQ-08, REQ-09, REQ-14](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-certificates-from-an-internal-ca.md),
[LOCAL-002](adr/LOCAL-002-one-certificate-per-authority.md),
[ADR 005](../../adr/005-modules-are-applicationsets.md),
[ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 010](../../adr/010-resources-delivered-via-chart.md),
[ADR 014](../../adr/014-exposed-does-not-mean-authorized.md),
[ADR 016](../../adr/016-metrics-enabled-is-the-fourth-input.md),
[ADR 018](../../adr/018-one-trust-bundle-for-the-cluster.md)

## Intent

Issue every certificate the environment uses, from authorities this module owns, and put the
root where anything that has to trust it can find it.

Two jobs, and they are not the same job. **Server certificates** make an exposed hostname
serve TLS. **Client certificates** let a Gateway listener authenticate a machine that has no
notion of a person — which is the gap
[ADR 014](../../adr/014-exposed-does-not-mean-authorized.md) named, examined and left open, on
the grounds that closing it meant owning the Gateway. This module closes half of it: it
provisions the material, and the environment's Gateway decides whether to demand it.

**This module does not expose anything and does not configure a Gateway.** The Gateway is a
per-environment prerequisite ([platform scope](../../platform.md#scope)) and stays one. What
this module publishes is Secret names, which a listener references.

## Provisions

One Argo CD `ApplicationSet` ([ADR 005](../../adr/005-modules-are-applicationsets.md)), whose
`List` generator produces three Applications, all unconditional:

| Wave | Application | Chart | Provides |
| --- | --- | --- | --- |
| 0 | `cert-manager` | `cert-manager` (jetstack) | the controller, webhook, cainjector and CRDs |
| 1 | `trust-manager` | `trust-manager` (jetstack) | the `Bundle` controller |
| 2 | `lab-pki` | `lab-pki` — authored by this repo | the authorities, their certificates, the bundle, the grant |

**The waves are load-bearing**, for two different reasons. cert-manager's CRDs must exist before
anything declares a `Certificate`. trust-manager issues its own webhook certificate *through*
cert-manager, so it cannot start first. The CRD Application also sets `ServerSideApply=true`:
cert-manager's CRDs exceed the 262144-byte `last-applied-configuration` annotation limit, and
without it the first sync fails with an error that does not obviously say so. The chart installs
them itself — the flag is `crds.enabled`, renamed from `installCRDs` at v1.15, which is a
version bump that can silently install nothing.

**`lab-pki` is the custom case** of [ADR 010](../../adr/010-resources-delivered-via-chart.md):
there is no upstream chart for "this lab's authorities", so this repo authors one. It renders,
per entry in `var.certificate_authorities`:

- a self-signed `Issuer`, and the CA `Certificate` it signs
- a `ClusterIssuer` backed by that CA's Secret
- **exactly one** leaf `Certificate` from that `ClusterIssuer`
  ([LOCAL-002](adr/LOCAL-002-one-certificate-per-authority.md))

plus one `Bundle` distributing the trusted authorities cluster-wide
([ADR 018](../../adr/018-one-trust-bundle-for-the-cluster.md)), and one `ReferenceGrant` when
`var.gateway` is set.

**The `ReferenceGrant` is why this module needs to know about the Gateway at all.** A listener's
`certificateRefs` reads a Secret in another namespace, and that is a cross-namespace reference
Gateway API requires a grant for. The platform's existing assumption —
`allowedRoutes.namespaces.from: All` — governs route *attachment* and does not cover it.

**Scraping.** When `metrics_enabled` is `true`, the chart's own `prometheus.servicemonitor`
values are set, producing a `ServiceMonitor` the collector reads directly
([ADR 004](../../adr/004-scrape-config-via-prometheus-crds.md),
[ADR 016](../../adr/016-metrics-enabled-is-the-fourth-input.md)). cert-manager exposes
`certmanager_certificate_expiration_timestamp_seconds` and
`certmanager_certificate_ready_status`, which is the whole of this module's user interface —
there is no console, and `cmctl status certificate` is the other half.

## Prerequisites

**The environment's Gateway needs two listeners, and this module provisions neither.** It
provisions what they reference:

```yaml
listeners:
  - name: web-tls
    port: 443
    protocol: HTTPS
    tls:
      certificateRefs:
        - name: <certificate_secret_names["server"]>
          namespace: <namespace>          # requires the ReferenceGrant this module renders
  - name: otlp-mtls
    port: 8443
    protocol: HTTPS
    tls:
      certificateRefs:
        - name: <certificate_secret_names["server"]>
          namespace: <namespace>
      frontendValidation:
        caCertificateRefs:
          - name: <ca_secret_names["client"]>
            namespace: <namespace>
```

A module attaches to one or the other by naming it in `gateway.section_name`
([ADR 007](../../adr/007-modules-receive-credentials.md)) — no new input, and no module changes
when a listener's posture changes.

**No Secret has to exist before this module runs.** It is the first module in the repository
that creates its own credentials rather than referencing ones made by hand, because a private
key that a person types is a private key that lives somewhere else too.

## Inputs

```hcl
namespace = "certificates"      # where the authorities and their Secrets live

certificate_authorities = {
  server = {
    common_name = "lab server CA"
    duration    = "87600h"      # 10y
    certificate = {
      dns_names = ["*.lab.internal"]
      usages    = ["server auth"]
      duration  = "8760h"       # 1y
    }
  }
  client = {
    common_name = "lab client CA"
    duration    = "87600h"
    certificate = {
      common_name = "lab client"
      usages      = ["client auth"]
      duration    = "8760h"
      renew_before = "720h"     # 30d — see below
    }
  }
}

trust_bundle = {
  name        = "lab-ca-bundle"
  authorities = ["server"]      # which authorities every namespace is told to trust
}

gateway = null                  # only .namespace is read: who may reference these Secrets

metrics_enabled = false   # declared once in env.hcl — ADR 016
```

**`certificate_authorities` is the module.** Everything else is placement. An authority declares
the one certificate it signs, so the 1:1 rule
([LOCAL-002](adr/LOCAL-002-one-certificate-per-authority.md)) is enforced by the type rather
than by review. Two entries is the default and not the limit.

**`renew_before` is short on the client certificate on purpose.** cert-manager renews at two
thirds of lifetime by default, so a one-year certificate is replaced in-cluster at month eight
while the copy on the laptop keeps working until month twelve. Nothing breaks — but the expiry
metric then describes the new certificate and says nothing about the one actually deployed, so
an alert built on it is worse than no alert. Renewing close to expiry keeps the metric and
reality talking about the same object.

**`gateway` is the shared contract, re-read.** This module renders no route and exposes nothing;
what it needs from the contract is the namespace holding the Gateway that reads these Secrets.
`null` means no `ReferenceGrant`, which means a Gateway in another namespace cannot use them —
the same "not wired" meaning the contract has everywhere else
([ADR 007](../../adr/007-modules-receive-credentials.md)). A second input of the same shape
would be two ways to say one thing.

## Outputs

| Output | Used by |
| --- | --- |
| `ca_secret_names` | map, authority → Secret holding that authority's certificate. The Gateway's `frontendValidation` reads the client one |
| `certificate_secret_names` | map, authority → Secret holding its issued certificate. The Gateway's `certificateRefs` reads the server one |
| `trust_bundle_name` | the ConfigMap present in every namespace; consumers mount it |

**Nothing cert-manager-shaped crosses the boundary.** No `Issuer` name, no `ClusterIssuer` kind,
no CRD reference — every output names a plain Kubernetes object, so
[REQ-09](../../requirements.md) costs nothing here. That is only possible because no in-cluster
workload requests a certificate; the day one does, it will need an issuer reference and this
property ends.

**No output carries a private key**, and none is marked sensitive, because none needs to be.

## Acceptance criteria

```gherkin
Feature: Certificates come from authorities this repository owns

  @cluster
  Scenario: [CERT-01] An authority signs exactly one certificate
    Given certificate_authorities declares server and client
    When Certificates in the namespace are listed
    Then exactly one exists per authority, excluding the authorities' own
     And each names the ClusterIssuer of the authority that declared it

  @cluster
  Scenario: [CERT-02] The bundle reaches every namespace, and adds rather than replaces
    Given the module has been applied
    When the trust bundle ConfigMap is read from any namespace
    Then it contains the server authority's certificate
     And it contains the public root certificates

  @cluster
  Scenario: [CERT-03] The client authority is not distributed
    Given trust_bundle.authorities names only server
    When the trust bundle ConfigMap is read
    Then the client authority's certificate does not appear in it

  @cluster
  Scenario Outline: [CERT-04] The Gateway reads these Secrets only when wired
    Given gateway is <gateway>
    When ReferenceGrants in the namespace are listed
    Then <outcome>

    Examples:
      | gateway | outcome                                                  |
      | null    | none exists                                              |
      | set     | one exists, permitting that namespace to read Secrets    |

  @cluster
  Scenario: [CERT-05] A server certificate is not a client certificate
    Given a listener validating clients against the client authority
    When the server certificate is presented as a client certificate
    Then the connection is refused
     And the refusal does not depend on Extended Key Usage being enforced

  @plan
  Scenario: [CERT-06] An authority outlives what it signs
    Given an authority whose duration is shorter than its certificate's
    When terraform plan runs
    Then it fails, naming both durations

  @cluster
  Scenario: [CERT-07] No private key is rendered
    Given the module has been applied
    When each Argo CD Application spec is read from the API server
    Then no private key appears in any rendered Helm values
     And every key material object was created by cert-manager
```

## Open items

- **`tls.frontendValidation` support is unverified.** Client certificate validation on a
  listener is Gateway API's experimental channel (GEP-91), and Traefik's support is
  version-dependent. This module is unaffected either way — it produces Secrets — but the
  mTLS intent fails outside this repository if the answer is no, and the fallback is a
  Traefik `TLSOption`, which is a different object and a different ADR.
- **Certificate rotation may need a Gateway restart.** cert-manager will renew the wildcard on
  schedule; whether Traefik notices a changed Secret without a pod bounce is unverified. If it
  does not, a renewal serves an expired certificate silently until something restarts. Verify,
  or give the server certificate a long duration and treat renewal as an event.
- **The authorities' private keys are the only unrecoverable objects in this repository.**
  Every other Secret can be recreated by typing the same value again. These cannot — reissuing
  produces a *different* root, and every device that trusts the old one has to be visited.
  Back up the namespace's Secrets or accept that a cluster rebuild is also a
  trust-distribution event.
- **Nothing makes a consumer mount the bundle.** Distribution puts the ConfigMap in the
  namespace; the consumer's own chart has to reference it. A consumer that forgets fails
  exactly as it would have with no trust-manager at all, and
  [`observability-console-grafana`](../observability-console-grafana/README.md) is the one that
  fails today.
- **The client certificate is shared, so revocation is all or nothing**
  ([LOCAL-002](adr/LOCAL-002-one-certificate-per-authority.md)). One pusher compromised means
  every pusher refreshed on the same afternoon.
- **Three pods for a capability that is mostly one wildcard.** cert-manager, its webhook and
  cainjector, plus trust-manager. The wildcard alone would not justify them; the client
  certificates and [REQ-14](../../requirements.md)'s "not made by hand" do. Build the client
  half first — it is the half that pays for the module.
- **cainjector will fight Argo CD.** It rewrites `caBundle` on the validating and mutating
  webhook configurations, which Argo CD sees as drift. The Application needs
  `ignoreDifferences` on `/webhooks/*/clientConfig/caBundle`, and this is the one place in the
  repository where that mechanism is needed for something other than a generated credential.
