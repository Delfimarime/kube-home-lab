# LOCAL-002. The operator comes from upstream's manifests, pinned by tag

**Status:** accepted · **Scope:** module — `openid-connect-keycloak` · **Date:** 2026-08-22

## Context

[LOCAL-001](LOCAL-001-oidc-provider-keycloak.md) ships the Keycloak Operator and the
environment's instance together. The instance is settled — it is
[ADR 010](../../../adr/010-resources-delivered-via-chart.md)'s custom case, a chart this repo
authors around the `Keycloak` resource. **Wave 0 was left open**, because the operator is not
distributed as a chart and [ADR 010](../../../adr/010-resources-delivered-via-chart.md) requires
a version pinned exactly. The module spec offered two ways out: adopt a community chart and pin
it, or wrap the published manifests in a second locally-authored chart.

Checked against Keycloak 26.7.2 on 2026-08-22, upstream publishes the operator through exactly
two channels, and neither is a chart:

- **OLM**, from OperatorHub, on the `fast` channel.
- **A kustomization**, in `keycloak/keycloak-k8s-resources`, applied at a git ref —
  `kubernetes?ref=26.7.2` for the namespaced install, `kubernetes/cluster-wide?ref=26.7.2` for
  the other. It carries the CRDs, the RBAC and the controller.

There is no official Helm chart and the project has declined to publish one. The community
charts that exist are one-maintainer republications of those same manifests.

## Decision

**Wave 0's `Application` reads upstream's kustomization directly, at a git tag.** No chart, no
vendored copy, and the tag is the pin.

## Rationale

- **A git tag is a stronger pin than a chart version, not a weaker one.** §2.5 wants an upgrade
  to be a deliberate edit; a chart version names a mutable artifact in a registry, and a tag
  names a tree. The property the rule is protecting — that a values schema cannot change
  underneath this module silently — is better served here than by the thing the rule describes.
- **Vendoring is a fork wearing another name.** The repository's own rationale table already
  priced it: forking a chart is a maintenance bill with no payoff. The CRDs would be the bulk of
  what got committed, they are the part that changes on every Keycloak release, and a stale copy
  does not fail loudly — it produces a controller that cannot reconcile a type it was compiled
  against.
- **OLM is a prerequisite, and §1.1 forbids provisioning one.** Installing an operator lifecycle
  manager in order to install one operator is a different project sharing a checkout, which is
  the exact shape §1.1 names.
- **A chart's value here would be its values.yaml, and this module would set nothing in it.** The
  operator takes no configuration worth exposing — the whole of this module's configuration lands
  on the `Keycloak` resource in wave 1. What a community chart would add is a second maintainer
  between this repository and upstream, for a file with no content in it.
- **It does not breach [ADR 010](../../../adr/010-resources-delivered-via-chart.md).** That
  decision binds on ownership: the generated `Application` owns every in-cluster resource, and
  OpenTofu creates no bare Kubernetes object. Both hold — the Application owns the CRDs, the
  RBAC and the controller, and OpenTofu creates an `ApplicationSet` and nothing else. Its
  native/wrapped/custom preference is about *which chart* to use where a chart is the vehicle,
  and here none is.

## Consequences

- **This is a case [ADR 010](../../../adr/010-resources-delivered-via-chart.md) does not
  enumerate**, and it is deliberately not lifted. A fourth case — *upstream publishes
  ready-to-apply manifests, so point at them* — would be a platform decision the moment a second
  module needed it, and this repository's practice is to lift on the second consumer rather than
  the first ([ADR 017](../../../adr/017-stores-are-multi-tenant.md) and
  [ADR 018](../../../adr/018-one-trust-bundle-for-the-cluster.md) are the precedent). Until then
  §2.4's three cases are not wrong, only incomplete, and amending them here would put a citation
  to a module ADR in a platform document — which runs the wrong way.
- **The `ApplicationSet` gains a third `source_kind`, and `templatePatch` is what makes that
  possible.** A `List` generator has one template for every element, and Argo CD decides a
  source's type by which of `helm` and `kustomize` is *present* — not by whether it is empty. An
  element rendered with `helm: {values: ""}` is therefore a Helm source, and a kustomization
  underneath it is a chart Argo CD cannot find. `templatePatch` is applied as a Kubernetes
  strategic merge patch, in which a null deletes a key, so the element carrying the operator
  removes the block it does not want:

  ```yaml
  {{- if eq .source_kind "kustomize" }}
  spec:
    source:
      helm: null
  {{- end }}
  ```

  It is the only per-element escape hatch a single template has. Worth knowing it exists before
  reaching for a second `ApplicationSet`, which §2.3 forbids anyway.
- **`ServerSideApply=true` on wave 0 stops being a precaution.** The CRDs arrive inside the same
  source as the controller rather than as a separate element, so the annotation-size limit is hit
  on the first sync rather than possibly.
- **The namespaced kustomization is the one to use**, since this module puts one Keycloak in one
  namespace. Its CRDs are cluster-scoped regardless of which variant installs them, which is
  worth knowing before an environment assumes the namespaced choice contains the blast radius.
- **An upgrade is a one-line edit and reads as a version bump**, which is what it is. The operator
  and the server image are versioned together by upstream, so the tag here and the image on the
  `Keycloak` resource move as a pair — two edits, and neither is safe alone.
