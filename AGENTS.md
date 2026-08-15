# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, etc.) working in this repository.

This file holds only what an implementer must not get wrong. Everything else is documented
once, elsewhere, and linked — do not restate it here.

| For | Read |
| --- | --- |
| What has to be true, and why | [docs/requirements.md](docs/requirements.md) |
| The domain model, the contracts, and any behaviour spanning modules | [docs/platform.md](docs/platform.md#mechanisms) |
| A specific module | `docs/modules/<module>/README.md` and its `adr/` |
| Why a platform-wide choice was made | [docs/adr/](docs/README.md#decisions) |
| Doc conventions, ID schemes, statuses | [docs/README.md](docs/README.md#conventions) |
| How to run anything | [README.md](README.md#layout) |

## Repository structure

```
main.tf                        required_version, required_providers, the pg backend
providers.tf                   the one provider, configured once
variables.tf                   everything true of the cluster being addressed
<capability>.tf                one module block per capability this cluster ships
outputs.tf
modules/<capability>-<impl>/
  tofu/                        the OpenTofu that renders this module's ApplicationSet
  helm/<chart>/                a chart this repo authors, when no upstream one fits
docs/                          requirements, specs, decisions
```

Specs come first: a module's spec and its ADRs are written before its `tofu/` is.

**Everything in this repository provisions a platform capability, and nothing provisions a
prerequisite.** k3s, Argo CD, the Gateway and PostgreSQL are things an environment already has
([platform scope](docs/platform.md#scope)) — this repo addresses them and never creates them.
A directory for running one of them here would be a different project sharing a checkout.
**Don't add one**, and don't let a module grow into provisioning what it is meant to consume.

## Workflow: requirements → ADRs → specs → code

1. A requirement (`REQ-NN`) says what must be true, independent of implementation. New ones go
   in [docs/requirements.md](docs/requirements.md), with a row in its traceability matrix.
2. An ADR resolves how, and records what it cost. One decision per ADR. Platform-wide ADRs go
   in `docs/adr/` with a global number; module-scoped ones go in
   `docs/modules/<module>/adr/` as `LOCAL-NNN`.
3. A spec designs it and states acceptance criteria as tagged, IDed Gherkin scenarios.
4. Code implements the spec and cites the ADRs it follows.

**Before changing a module, read its `README.md` and every ADR it links** — its own `LOCAL-`
ones and the platform ADRs it obeys. Before changing a convention below, read the ADR that
established it; the consequences section is usually why the convention looks odd.

**Scope test for a new ADR:** if reversing this decision would change code outside the module,
it is platform-wide. ADR 004 is the trap — it reads like an observability decision and is
platform-wide, because it is why every module declares scraping through its chart.

**The test has a tell.** A module ADR that wants to cite another module's ADR has failed it, and
the fix is to lift the decision rather than link across. ADR 017 and ADR 018 were both written
as module ADRs and lifted for exactly this reason. If you reach for a cross-module citation,
stop and re-run the scope test.

## Conventions every module follows

Load-bearing decisions from the ADRs. Violating one is a regression, not a style choice.

- **Modules are named `<capability>-<implementation>`** (e.g. `openid-connect-keycloak`), and
  their outputs stay implementation-neutral (`issuer_url`, not `keycloak_realm_id`) so swapping
  the implementation doesn't touch consumers. [keycloak LOCAL-001]
- **Every module renders its own Argo CD `ApplicationSet`** — a `List` generator with one
  static entry per chart the module needs, even when that's a single entry. There is no shared
  `ApplicationSet` module, and no module ever creates a bare `Application` directly. [ADR 005]
- **Every consumer module takes the same three optional inputs**, each defaulting to `null`
  (meaning "not wired", never "disabled by a flag"): `gateway`, `database`, `oidc`. [ADR 007]
- **A fourth input, `metrics`, is not one of them and is not a contract.** One field,
  `enabled`, defaulting to `false`, taken by every module whose workload can emit a
  `ServiceMonitor`; it says the environment has the CRDs *and* a collector. A module with no
  metrics endpoint doesn't take it. [ADR 016]
- **Related inputs are one object, not a prefix.** `cert_manager.chart_version`, not
  `chart_versions.cert_manager`; `argocd.plain_text`, not `argocd_plain_text`. The object is the
  subject, and it is where the next field about that subject goes without renaming anything.
- **A module declares the fields it reads and no others.** Taking a contract's whole shape to
  use one field forces a caller to invent values nothing reads — `certificate-management-cert-manager`
  takes `gateway_namespace` rather than `gateway`, because it renders no route. [ADR 007, rule 3]
- **Each chart's generated Argo CD `Application` owns every resource it needs, including its
  route — OpenTofu never creates a bare Kubernetes object.** Prefer the workload's own chart
  when it already renders what's needed (native, e.g. Grafana's `route.main`); wrap it with a
  local chart that adds a Helm dependency plus one template when it doesn't (wrapped); author
  a local chart from scratch when there's no upstream chart at all (custom — e.g. Auditum,
  Keycloak's instance, the lab's certificate authorities). [ADR 010]
- **Modules are wired by reference, in the root module.** A value one module publishes and
  another consumes is `module.<a>.<output>` passed into `module.<b>` — one graph, resolved at
  plan time. There is no second state to read, so there is nothing to mock and nothing to copy
  by hand. [ADR 020]
- **Credentials are passed by reference, never by value**: `var.database` and `var.oidc` carry
  a Secret name plus a key, never a password or client secret. Nothing sensitive reaches a
  values.yaml or the rendered Helm values inside an `Application` spec in etcd. [ADR 007]
- **Providers publish addresses; they don't know their consumers.**
  `openid-connect-keycloak` outputs only `issuer_url`/`discovery_url` — it registers no OIDC
  clients and holds no client secrets. Client registration happens by hand in Keycloak's
  console until roughly fifteen clients, and so does every role and grant. [ADR 007, ADR 013]
- **A module declares what it needs, not when it is satisfied.** A `secret_name` or a
  `host_port` names something this repo may not provision. Who creates it, and in what order,
  is operational — do not encode ordering or dependency-checking into a module. [ADR 007]
- **PostgreSQL is external** — never provisioned by this repo. A consumer needing a database
  just gets `var.database` pointing at one that already exists, described per environment.
  [ADR 008]
- **Scrape config goes through Prometheus-operator CRDs** (`ServiceMonitor`/`PodMonitor`), read
  directly by the collector — a workload declares scraping through its own chart's
  `serviceMonitor.enabled`, never through hand-written scrape config or a vendor-specific
  equivalent. Chartless workloads like Auditum are the exception and need a `ServiceMonitor`
  written by hand. The observability module installs the CRD bundle. [ADR 004]
- **What a person may do comes from the token.** A consumer wired to `oidc` reads roles named
  `<SLUG>_ADMIN`/`<SLUG>_VIEWER` from `resource_access.<slug>.roles`, maps them to its own
  native roles, and **refuses anyone carrying none** — never falls back to a default role.
  [ADR 013]
- **The tool is OpenTofu.** `tofu`, not `terraform`, in every runbook and every `@plan`
  scenario; `required_version` is an OpenTofu version and does not read across. "Terraform"
  in these documents means the *language*. [ADR 019]
- **Provider configuration comes from the environment, never from a variable** — `ARGOCD_SERVER`,
  `ARGOCD_AUTH_TOKEN`, `ARGOCD_INSECURE` — so no credential reaches a tfvars file or state. The
  single exception is a field the provider offers no environment variable for: `plain_text` is a
  module input with a default, and a new one needs the same justification. Nothing is hardcoded
  in a `provider` block. [ADR 012]
- **A module directory holds exactly two things: `tofu/` and `helm/`.** The OpenTofu that
  renders the `ApplicationSet` goes in `tofu/`; a chart this repo authors goes in
  `helm/<chart-name>/`, wrapped or custom, same place. No `.tf` at the module root, no chart
  outside `helm/`, and nothing else in the directory. [ADR 010, ADR 019]
- **Chart versions are pinned exactly.** An upgrade is a deliberate edit, which is what keeps
  a native chart's values schema from changing underneath a module silently. [ADR 010]
- **Nothing in this repo creates the Secrets that `var.database` and `var.oidc` reference.**
  They are made by hand, per environment. Don't write a module that assumes otherwise, and
  don't add ordering or existence checks to compensate. [ADR 007]
  **A module that needs one names it and shows a placeholder `kubectl create secret` in its
  spec.** That documentation is the only record of what has to exist, so a new `secret_name`
  without an example is an incomplete change.
- **No chart here generates a credential**, so nothing needs `ignoreDifferences` to protect one.
  Credentials arrive by reference [ADR 007] and certificates are issued by cert-manager, which
  owns those Secrets outright — a chart that templated either would be creating the drift it
  then had to suppress. The one legitimate use is cert-manager's cainjector rewriting
  `caBundle` on its webhook configurations, which needs `ignoreDifferences` on
  `/webhooks/*/clientConfig/caBundle`. **If you find yourself reaching for that mechanism for
  anything else, the chart is wrong.**
- **Certificates come from `certificate-management-cert-manager` and are never made by hand.**
  A module needing TLS references a Secret that module publishes; it does not run `openssl` and
  it does not request a certificate of its own. [REQ-14, cert-manager LOCAL-001]
- **The stores are multi-tenant, and the tenant is trusted, not verified.** `X-Scope-OrgID`
  comes from the caller and nothing validates it — tenancy buys per-tenant limits and
  retention, not isolation. Don't derive a tenant from a client certificate, and don't add a
  check that a caller "owns" a tenant.

## Environments

- **An environment is a cluster with its own Argo CD.** Nothing is shared between them, and
  configuration is per environment. [ADR 011]
- **An environment ships a module by having a `module` block for it** — no enable flags, no
  inventory file. Don't add one. [ADR 020]
- **The environment is the shell, not the tree.** `ARGOCD_SERVER`/`ARGOCD_AUTH_TOKEN` select the
  cluster, `-backend-config` selects its state, `-var-file` supplies its values. Don't
  reintroduce a per-environment directory, an `env.hcl`, or Terragrunt.
- **The root module composes and wires; it never renders.** Anything that creates a resource
  belongs in a module — a bare Kubernetes object or an `ApplicationSet` at the root is a
  regression against [ADR 005], and the root module is the only place with the reach to make
  that mistake.
- **Don't restate a module's variable defaults at the root.** A value is written there because
  the cluster decides it, not to document it.
- **Never widen a module's blast radius past its environment.** A module addresses its own
  cluster; nothing reaches across. [REQ-12]
- **State is per environment, in a PostgreSQL.** A backend block takes no interpolation, so the
  schema is chosen at `init` with `-backend-config`. **Which PostgreSQL is not this repo's
  business** — don't assume it is the environment's application database, and don't assume it
  runs in the cluster. The connection string is never declared: `PG_CONN_STR` carries the
  address and the credential. [ADR 012]
- **Nothing checks that the shell is coherent.** A `-backend-config` naming one cluster's state
  and an `ARGOCD_SERVER` naming another's API will plan something meaningless, silently. Export
  the three together, per environment. Don't try to fix this with a check inside a module — it
  is the operator's, and [ADR 020] says so.

## Trade-offs to respect

A tiny k3s cluster per environment, one operator across all of them, weeks of neglect. See
[README § Rationale](README.md#rationale).

**Don't propose HA, multi-replica or tuning changes unless asked** — they cut against the
repo's stated intent, and the cost is paid every day, in every environment, on nodes with a
finite amount of RAM.

## Blocked and undecided

- `audit-management-auditum` is **blocked** on an open question — application audit trails vs.
  Kubernetes API audit logs. See
  [its Blocking question](docs/modules/audit-management-auditum/README.md#blocking-question).
  Don't build it out further without resolving that; if the answer is the second one, the
  module should not exist.
- **Nothing backs up PostgreSQL**, and two things in it cannot be regenerated from git:
  Keycloak's realm and every Grafana alert rule. Don't add a third without saying so. OpenTofu
  state is in a PostgreSQL too but a separate one, and it *is* regenerable
  [ADR 012](docs/adr/012-state-is-per-environment.md).
- **There is no secret manager.** REQ-04 was dropped along with the module that satisfied it,
  so every `secret_name` in the repo names something created by hand. Don't reintroduce one
  without a requirement above it.
- **The identity model is not declared anywhere.** Keycloak's realm — its clients, their
  redirect URIs, the `<SLUG>_<ROLE>` roles [ADR 013] defines, and every grant — is created by
  hand in a console. `KeycloakRealmImport` is a *partial* fix and is deferred: it applies rather
  than reconciles, and a realm export embeds client secrets that REQ-05 forbids reaching a
  rendered `Application`. **This is the largest gap in the platform.** Don't paper over it by
  adding a module input that carries a role list.
- **Three things are unverified and each would change a spec.** Whether Alloy's
  `otelcol.auth.headers` accepts `from_context` and `default_value` at the pinned version (the
  chart wiring for [ADR 017] is confirmed by rendering; the component
  is not); whether Traefik supports `tls.frontendValidation` on a listener (decides whether
  mTLS is portable Gateway API or a Traefik `TLSOption`); and whether Loki's and Tempo's charts
  expose per-tenant overrides (decides the shape `mimir-monolithic` is written to match). Check
  before implementing, not after.
