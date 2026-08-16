# CONSTITUTION.md

The rules this repository is built on. Each is load-bearing: breaking one is a regression, not a
style choice.

Most rules cite the decision that established them; a few are plain conventions with no ADR
behind them. **Before changing a rule that cites one, read that decision** — its Consequences
section is usually why the rule looks odd. Cite a rule as `§4.2`.

ADR links are by number: [`004`](docs/adr/004-scrape-config-via-prometheus-crds.md) …
[`023`](docs/adr/023-a-modules-opentofu-is-at-its-root.md), indexed in
[docs/README.md](docs/README.md#decisions).

---

## 1. Boundaries

**1.1** This repository provisions platform capabilities and **never a prerequisite**. k3s, Argo
CD, the Gateway and PostgreSQL are things an environment already has. Don't add a directory that
runs one — that is a different project sharing a checkout.
[scope](docs/platform.md#scope), [`008`](docs/adr/008-postgresql-is-external.md)

**1.2** A module never grows into provisioning what it consumes — the corollary of §1.1 at
module scope.

**1.3** Nothing reaches past its own cluster. [REQ-12](docs/requirements.md)

**1.4** Don't propose HA, multi-replica or tuning changes unless asked. Tiny clusters, one
operator, weeks of neglect — the cost is paid daily, per environment, on finite RAM.
[rationale](README.md#rationale)

## 2. Modules

**2.1** Named `<capability>-<implementation>`. Outputs are named for the capability, never the
product — `issuer_url`, not `keycloak_realm_id` — so the implementation half stays swappable.
[keycloak LOCAL-001](docs/modules/openid-connect-keycloak/adr/LOCAL-001-oidc-provider-keycloak.md)

**Exactly one directory under `modules/` is not a capability**: `secret-template`, which other
modules import and which **renders nothing** — it returns one `ApplicationSet` element for its
caller to own (§5.2). It has no spec, because it designs nothing; a second exception needs the
argument that one made.
[`022`](docs/adr/022-secrets-are-rendered-empty.md)

**2.2** A module directory holds its `.tf` files at the root and, where it authors a chart,
`helm/<chart>/`. Nothing else, and no chart outside `helm/`.
[`010`](docs/adr/010-resources-delivered-via-chart.md), [`019`](docs/adr/019-the-tool-is-opentofu.md),
[`023`](docs/adr/023-a-modules-opentofu-is-at-its-root.md)

**2.3** Each module renders exactly one Argo CD `ApplicationSet` — a `List` generator, one static
entry per chart, even at one entry. No shared `ApplicationSet` module; no bare `Application`,
ever. [`005`](docs/adr/005-modules-are-applicationsets.md)

**2.4** Each generated `Application` owns every resource its chart needs, including its route;
**OpenTofu creates no bare Kubernetes object**. Prefer the workload's own chart (*native*); wrap
it with a local chart adding a dependency plus one template when it can't do the job (*wrapped*);
author one from scratch when no upstream chart exists (*custom*).
[`010`](docs/adr/010-resources-delivered-via-chart.md)

**2.5** Chart versions are pinned exactly. An upgrade is a deliberate edit — which is what stops a
chart's values schema changing underneath a module silently.
[`010`](docs/adr/010-resources-delivered-via-chart.md)

**2.6** No chart here generates a credential. `ignoreDifferences` has exactly **two** legitimate
uses, and both protect a field whose content is owned by something other than the chart:
cert-manager's cainjector rewriting `/webhooks/*/clientConfig/caBundle`, and the `.data` of a
placeholder Secret an operator fills (§5.2) — the latter always paired with
`RespectIgnoreDifferences=true`, which is the half people miss. **Reaching for that mechanism
anywhere else means the chart is wrong**, and protecting a credential a chart *generated* is
still the case that means it.
[`007`](docs/adr/007-modules-receive-credentials.md),
[`022`](docs/adr/022-secrets-are-rendered-empty.md)

## 3. Module inputs

**3.1** Every consumer module takes the same three optional inputs, one shape each, defaulting to
`null` — meaning *not wired*, never *disabled by a flag*: `gateway`, `database`, `oidc`. Shapes in
[contracts](docs/platform.md#contracts). [`007`](docs/adr/007-modules-receive-credentials.md)

**3.2** `metrics` is a fourth input and **not** a contract. One field, `enabled`, default `false`,
taken by every module whose workload can emit a `ServiceMonitor`; it asserts the cluster has the
CRDs *and* a collector. A module with no metrics endpoint doesn't take it.
[`016`](docs/adr/016-metrics-is-the-fourth-input.md)

**3.3** Related inputs are one object, not a prefix: `cert_manager.chart_version`, not
`chart_versions.cert_manager`. The object is the subject, and is where the next field about that
subject goes without renaming anything.

**3.4** A module declares the fields it reads and no others. Taking a contract's whole shape to
use one field forces callers to invent values nothing reads — `certificate-management-cert-manager`
takes `gateway_namespace`, not `gateway`, because it renders no route.
[`007`](docs/adr/007-modules-receive-credentials.md) rule 3

**3.5** Credentials pass **by reference, never by value**: `database` and `oidc` carry a Secret
name plus a key. Nothing sensitive reaches a values.yaml, a rendered `Application` spec, or state.
[`007`](docs/adr/007-modules-receive-credentials.md), [REQ-05](docs/requirements.md)

**3.6** A module declares *what* it needs, not *when* it is satisfied. Who creates a Secret, and
in what order, is operational — never encode ordering or existence checks into a module.
[`007`](docs/adr/007-modules-receive-credentials.md)

## 4. Composition

**4.1** There is one root module and no Terragrunt. **The environment is the shell, not the
tree**: `ARGOCD_SERVER`/`ARGOCD_AUTH_TOKEN` select the cluster, `-backend-config` its state,
`-var-file` its values. Don't reintroduce a per-environment directory or an `env.hcl`.
[`020`](docs/adr/020-one-root-module.md), [`011`](docs/adr/011-environments-are-clusters.md)

**4.2** Modules are wired by reference: `module.<a>.<output>` passed into `module.<b>`. One graph,
resolved at plan time — nothing to mock, no state to read, no address copied by hand.
[`020`](docs/adr/020-one-root-module.md)

**4.3** The root module composes and wires; **it never renders**. Anything creating a resource
belongs in a module. The root is the only place with the reach to break §2.3.

**4.4** An environment ships a module by having a `module` block for it. No enable flags, no
inventory file — the composition *is* what is deployed.
[`020`](docs/adr/020-one-root-module.md)

**4.5** Don't restate a module's variable defaults at the root. A value is written there because
the cluster decides it, not to document it.

**4.6** **Nothing checks that the shell is coherent.** A `-backend-config` naming one cluster's
state beside another cluster's `ARGOCD_SERVER` plans something meaningless, silently. Export the
three together, per environment — and don't try to fix it inside a module.
[`020`](docs/adr/020-one-root-module.md)

## 5. Secrets

**5.1** **There is no secret manager.** A credential's *value* is typed in by a person, per
environment, and again after every rebuild — managed by nobody, stored nowhere, backed up by
nothing. Don't write a module that assumes otherwise; don't reintroduce a manager without a
requirement above it.
[`007`](docs/adr/007-modules-receive-credentials.md),
[`022`](docs/adr/022-secrets-are-rendered-empty.md)

**5.2** **A `secret_name` names a Secret; whether the module also declares it is the caller's
choice.** Set, the module references it and creates nothing. Null, the module **renders a
placeholder** by importing `modules/secret-template` into its own namespace — **keys present**, taken
from the same `*_key` inputs the workload's configuration is built from, values empty — with
`ignoreDifferences` on `.data` *and* `RespectIgnoreDifferences=true` (§2.6), and publishes the
name it chose. Either way the module holds a name and a key and never a value. A module renders
only its own and **never adopts an object it did not create**; where two modules need one
credential, each renders a placeholder and both get filled, and **a provider never renders a
Secret into a consumer's namespace**. Its spec **shows the `kubectl patch` that fills each
Secret** and says the workload needs a rollout restart afterwards: the object declares the shape,
the spec is still the only record of what the value has to be, so a new `secret_name` without
that example is an incomplete change.
[`022`](docs/adr/022-secrets-are-rendered-empty.md)

**5.3** Provider configuration comes from the environment, never a variable — `ARGOCD_SERVER`,
`ARGOCD_AUTH_TOKEN`, `ARGOCD_INSECURE`. The one exception is a field the provider offers no
environment variable for: `plain_text`. A second exception needs the same justification. Nothing
is hardcoded in a `provider` block. [`012`](docs/adr/012-state-is-per-environment.md)

## 6. Identity and authorization

**6.1** Providers publish addresses and know nothing about their consumers.
`openid-connect-keycloak` outputs `issuer_url`/`discovery_url` only — it registers no clients and
holds no client secrets. [`007`](docs/adr/007-modules-receive-credentials.md)

**6.2** What a person may do comes from the token. A consumer wired to `oidc` reads
`<SLUG>_ADMIN`/`<SLUG>_VIEWER` from `resource_access.<slug>.roles`, maps them to its native roles,
and **refuses anyone carrying none** — never falls back to a default role.
[`013`](docs/adr/013-roles-are-carried-in-the-token.md)

**6.3** Client registration, roles and grants are done by hand in Keycloak's console until roughly
fifteen clients. Don't add a module input carrying a role list.
[`007`](docs/adr/007-modules-receive-credentials.md), [`013`](docs/adr/013-roles-are-carried-in-the-token.md)

**6.4** Exposed does not mean authorized. A route makes a hostname reachable and says nothing
about who may use it. [`014`](docs/adr/014-exposed-does-not-mean-authorized.md)

## 7. Certificates

**7.1** Certificates come from `certificate-management-cert-manager` and are **never made by
hand**. A module needing TLS references a Secret that module publishes; it does not run `openssl`
and does not request a certificate of its own.
[REQ-14](docs/requirements.md),
[cert-manager LOCAL-001](docs/modules/certificate-management-cert-manager/adr/LOCAL-001-certificates-from-an-internal-ca.md)

**7.2** One trust bundle for the cluster, not a mount per workload.
[`018`](docs/adr/018-one-trust-bundle-for-the-cluster.md)

## 8. Observability

**8.1** Scrape config goes through Prometheus-operator CRDs (`ServiceMonitor`/`PodMonitor`), read
directly by the collector. A workload declares scraping through its own chart's
`serviceMonitor.enabled` — never hand-written scrape config or a vendor equivalent. Chartless
workloads are the exception and need one written by hand. The observability module installs the
CRD bundle. [`004`](docs/adr/004-scrape-config-via-prometheus-crds.md)

**8.2** The stores are multi-tenant and **the tenant is trusted, not verified**. `X-Scope-OrgID`
comes from the caller and nothing validates it — tenancy buys per-tenant limits and retention,
not isolation. Don't derive a tenant from a client certificate; don't check that a caller "owns"
one. [`017`](docs/adr/017-stores-are-multi-tenant.md)

## 9. Tooling and state

**9.1** The tool is OpenTofu. `tofu`, not `terraform`, in every runbook and every `@plan`
scenario; `required_version` is an OpenTofu version and does not read across. "Terraform" in these
documents means the *language*. [`019`](docs/adr/019-the-tool-is-opentofu.md)

**9.2** State is per environment, in a PostgreSQL. A backend block takes no interpolation, so the
schema is chosen at `init` with `-backend-config`; `PG_CONN_STR` carries the address and the
credential, so nothing about state reaches git. **Which PostgreSQL is not this repo's business** —
not necessarily the workloads' database, not necessarily in the cluster.
[`012`](docs/adr/012-state-is-per-environment.md)

## 10. Documentation

**10.1** The order is **requirements → ADRs → specs → code**, and nothing is restated between
layers.

1. A requirement (`REQ-NN`) states what must be true, independent of implementation — in
   [docs/requirements.md](docs/requirements.md), with a row in its traceability matrix.
2. An ADR resolves *how* and records what it cost. One decision per ADR.
3. A spec designs it, with acceptance criteria as tagged, IDed Gherkin scenarios.
4. Code implements the spec and carries its reasons.

**10.2** Specs come first: a module's spec and its ADRs are written before its OpenTofu is.

**10.3** **No code file cites a document** — not an ADR number, not a `REQ-NN`, not a scenario ID,
not a section of this file. A comment states the reason itself, in enough words to stand alone.
Traceability runs documentation → code and never back, because a citation in a comment is a link
nothing checks and this repository renumbers.
[`021`](docs/adr/021-code-does-not-cite-documentation.md)

**10.4** **Scope test.** If reversing a decision would change code outside the module, it is
platform-wide → `docs/adr/NNN-slug.md`. Otherwise it is module-scoped →
`docs/modules/<module>/adr/LOCAL-NNN-slug.md`. [`004`](docs/adr/004-scrape-config-via-prometheus-crds.md)
is the trap: it reads like an observability decision and is platform-wide, because it is why
every module declares scraping through its chart.

**10.5** **The test has a tell.** A module ADR that wants to cite another module's ADR has failed
it — lift the decision instead of linking across. ADRs
[`017`](docs/adr/017-stores-are-multi-tenant.md) and
[`018`](docs/adr/018-one-trust-bundle-for-the-cluster.md) were both written as module ADRs and
lifted for exactly this reason.

**10.6** Before changing a module, read its `README.md` and every ADR it links — its own `LOCAL-`
ones and the platform ADRs it obeys.
