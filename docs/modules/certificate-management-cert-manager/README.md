# Module: certificate-management-cert-manager

**Status:** draft ·
**Satisfies:** [REQ-08, REQ-09, REQ-14](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-certificates-from-an-internal-ca.md),
[LOCAL-002](adr/LOCAL-002-one-certificate-per-authority.md),
[ADR 005](../../adr/005-modules-are-applicationsets.md),
[ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 010](../../adr/010-resources-delivered-via-chart.md),
[ADR 014](../../adr/014-exposed-does-not-mean-authorized.md),
[ADR 016](../../adr/016-metrics-is-the-fourth-input.md),
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
cert-manager, so it cannot start first. `ServerSideApply=true` is set on all three:
cert-manager's CRDs exceed the 262144-byte `last-applied-configuration` annotation limit, and
without it the first sync fails with an error that does not obviously say so. The chart installs
them itself — the flag is `crds.enabled`, **which defaults to `false`**, and which replaced
`installCRDs` at v1.15; the old name is still accepted and silently ignored, so a bump that
missed the rename would install a controller with no types to reconcile.

**All three land in one namespace, and that is not tidiness.** A `ClusterIssuer` resolves its CA
Secret in cert-manager's `--cluster-resource-namespace`, and trust-manager reads a `Bundle`'s
sources from its `--trust-namespace`, which defaults to `cert-manager`. Splitting the
controllers from the authorities means setting both, and forgetting either produces a
`ClusterIssuer` that never becomes ready and says only "secret not found". One namespace makes
the first correct by default; the module sets both explicitly anyway.

**`lab-pki` is the custom case** of [ADR 010](../../adr/010-resources-delivered-via-chart.md):
there is no upstream chart for "this lab's authorities", so this repo authors one. It renders,
for each of the two authorities — `server` and `client`, which are not configurable:

- a self-signed `Issuer`, and the CA `Certificate` it signs
- a `ClusterIssuer` backed by that CA's Secret

and, per entry in `var.certificates` plus the always-issued `default`:

- a server `Certificate` from the `server` ClusterIssuer, `server auth`
- when `mode = "mtls"`, **also** a client `Certificate` from the `client` ClusterIssuer,
  `client auth` ([LOCAL-002](adr/LOCAL-002-one-certificate-per-authority.md))

The chart has no notion of a mode: the module resolves it into shapes, and an entry carrying a
`client` block *is* the pair. That is why there is no second place the two could disagree about
what mtls means.

Plus one `Bundle` distributing the trusted authorities cluster-wide
([ADR 018](../../adr/018-one-trust-bundle-for-the-cluster.md)), and one `ReferenceGrant` when
`var.gateway_namespace` is set.

**The `ReferenceGrant` is why this module needs to know about the Gateway at all.** A listener's
`certificateRefs` reads a Secret in another namespace, and that is a cross-namespace reference
Gateway API requires a grant for. The platform's existing assumption —
`allowedRoutes.namespaces.from: All` — governs route *attachment* and does not cover it.

**Scraping.** When `metrics.enabled` is `true`, the chart's own `prometheus.servicemonitor`
values are set, producing a `ServiceMonitor` the collector reads directly
([ADR 004](../../adr/004-scrape-config-via-prometheus-crds.md),
[ADR 016](../../adr/016-metrics-is-the-fourth-input.md)). cert-manager exposes
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
domain    = "lab.internal"      # required; every issued name is built from it
namespace = "cert-manager"      # where the authorities and their Secrets live

# Additional to `default`, which is always issued: the wildcard *.lab.internal and the shared
# client identity paired with it. "default" is a reserved key here.
certificates = {
  storage = {
    mode      = "mtls"          # a pair: server certificate + client certificate
    dns_names = ["mimir.lab.internal"]
  }
  console = {}                  # mode defaults to "tls"; dns_names to ["console.lab.internal"]
}

default_certificate = { duration = "8760h" }   # 1y
authority           = { duration = "87600h" }  # 10y — an authority outlives what it signs

trust_bundle = {
  name        = "lab-ca-bundle"
  authorities = ["server"]      # which authorities every namespace is told to trust
}

gateway_namespace = null        # whose Gateway may reference these Secrets

metrics = { enabled = false }   # a root variable, declared once — ADR 016
```

**`domain` and `certificates` are the module.** Everything else is placement or a lifetime. A
name is enough on its own: an entry with no `dns_names` gets `<name>.<domain>`, and its client
half gets `CN=<name>.<domain>`, so nothing makes a caller repeat the domain it already declared.

**`mode` decides how many certificates an entry produces, not what usages one carries.** Adding
`client auth` to the server certificate would render more simply and would defeat the two
authorities — that separation is what `CERT-05` rests on
([LOCAL-002](adr/LOCAL-002-one-certificate-per-authority.md)).

**`renew_before` is unset by default, and the client half then gets `720h`.** cert-manager renews
at two thirds of lifetime, so a one-year certificate is replaced in-cluster at month eight while
the copy on the laptop keeps working until month twelve. Nothing breaks — but the expiry metric
then describes the new certificate and says nothing about the one actually deployed, so an alert
built on it is worse than no alert. The in-cluster server halves have no such problem, which is
why the shorter window applies only to the half that leaves.

**`gateway_namespace` is not the `gateway` contract, and is deliberately not shaped like it.**
That contract carries a name, a hostname and a section — everything a module needs to *emit a
route*. This module emits no route. Taking the whole shape to read one field would force a
caller to invent a hostname nothing here reads, which is the opposite of
[ADR 007](../../adr/007-modules-receive-credentials.md)'s third rule: a module declares what it
needs. `null` keeps the contract's ordinary meaning — not wired, so no `ReferenceGrant`, so a
Gateway in another namespace cannot use these Secrets.

**This module therefore takes none of the three contracts.** It has no route, no database and no
issuer, which is the same fact as having no consumer inside this repository.

**Almost none of it is written down per environment.** `domain` is the one value with no
default, and everything else is derived from it: both authorities' common names, the wildcard, and
each entry's `dns_names` and client subject. `namespace`, `default_certificate`, `authority`,
`trust_bundle` and the three chart pins stay at their defaults; `argocd.namespace`,
`gateway_namespace` and `metrics` come from root variables, because they describe the cluster
rather than this module. The root module is a pass-through — it composes nothing.

## Outputs

| Output | Used by |
| --- | --- |
| `ca_secret_names` | `server`/`client` → Secret holding that authority's own certificate. A listener's `frontendValidation` reads the client one |
| `certificate_secret_names` | certificate name → Secret holding its server certificate. A listener's `certificateRefs` reads one; `default` is the wildcard |
| `client_certificate_secret_names` | certificate name → Secret holding its client certificate. Only `mtls` entries appear |
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
  Scenario Outline: [CERT-01] A certificate's mode decides how many it produces
    Given a certificate entry named <name> with mode <mode>
    When Certificates in the namespace are listed
    Then <count> exist for that entry, excluding the authorities' own
     And every server certificate names the server ClusterIssuer
     And every client certificate names the client ClusterIssuer

    Examples:
      | name    | mode | count |
      | console | tls  | one   |
      | storage | mtls | two   |

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
    Given gateway_namespace is <gateway_namespace>
    When ReferenceGrants in the namespace are listed
    Then <outcome>

    Examples:
      | gateway_namespace | outcome                                              |
      | null              | none exists                                          |
      | set               | one exists, permitting that namespace to read Secrets |

  @cluster
  Scenario: [CERT-05] A server certificate is not a client certificate
    Given a listener validating clients against the client authority
    When the server certificate is presented as a client certificate
    Then the connection is refused
     And the refusal does not depend on Extended Key Usage being enforced

  @plan
  Scenario: [CERT-06] An authority outlives everything it signs
    Given authority.duration is shorter than any certificate's duration
    When tofu plan runs
    Then it fails, naming both durations

  @plan
  Scenario: [CERT-08] The reserved certificate name is refused
    Given certificates declares an entry named default
    When tofu plan runs
    Then it fails, saying default is derived from domain

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
- **`default`'s client certificate is shared, so revoking it is all or nothing**
  ([LOCAL-002](adr/LOCAL-002-one-certificate-per-authority.md)). One pusher compromised means
  every holder refreshed on the same afternoon. Giving a pusher its own `mtls` entry narrows
  that to one holder, and is the only reason to add one — per-client certificates are otherwise
  a distinction nothing in this stack reads.
- **Three pods for a capability that is mostly one wildcard.** cert-manager, its webhook and
  cainjector, plus trust-manager. The wildcard alone would not justify them; the client
  certificates and [REQ-14](../../requirements.md)'s "not made by hand" do. Build the client
  half first — it is the half that pays for the module.
- **cainjector will fight Argo CD.** It rewrites `caBundle` on the validating and mutating
  webhook configurations, which Argo CD sees as drift. The `ApplicationSet` template carries
  `ignore_difference` on `.webhooks[]?.clientConfig.caBundle` for both kinds, together with
  `RespectIgnoreDifferences=true` — without the second, the rule only hides the field from the
  diff and a sync triggered by anything else still writes the empty value back, which breaks the
  webhook and with it every certificate the cluster tries to issue. This is the one place in the
  repository where that mechanism is needed for something other than a generated credential.
- **The two vendor charts put the same switch in different places.** cert-manager's is
  `prometheus.servicemonitor.enabled`; trust-manager's is
  `app.metrics.service.servicemonitor.enabled`, and `app.webhook.service` exists but does not
  take one. The values schema rejects the wrong path, which is the good case — a chart without
  one would have accepted it silently. Render against the pinned chart before believing a key.
