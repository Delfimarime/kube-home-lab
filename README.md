# kube-home-lab

A homelab platform on k3s. Small clusters, few services, deliberately boring.

This repo holds the manifests for the _platform_ layer — observability and the shared
services workloads depend on — across one or more environments. Cluster bootstrap is out of
scope.

## Assumptions

An **environment is a Kubernetes cluster with its own Argo CD**. Each one already exists and
already runs:

- **k3s** — a tiny cluster; single node or a couple of them
- **Argo CD** — its own, not shared. Everything here is applied by Argo CD, not `kubectl apply`
- **Gateway API (Traefik)** — ingress is a `HTTPRoute`, never an `Ingress`
- **PostgreSQL** — reachable, described in that environment's var file

If any of those is missing, this repo does nothing useful for that environment.

## Scope

Provision workload-facing platform services. Each environment ships the ones it wants:

| Module | Provides |
| --- | --- |
| `certificate-management-cert-manager` | the lab's certificate authorities, and one trust bundle |
| `observability-storage-grafana-lgtm` | metrics, logs and traces — each independently switchable — collected and stored |
| `observability-console-grafana` | one Grafana over whichever of the three is switched on |
| `openid-connect-keycloak` | one OIDC issuer for the environment |
| `audit-management-auditum` | an audit record API |

## Rationale

Homelab, not production. Choices follow from that:

| Choice                            | Why                                                       |
| --------------------------------- | --------------------------------------------------------- |
| One replica of everything         | Nothing here is worth an HA story on a tiny cluster        |
| Short retention                   | Disk is the scarce resource, not history                   |
| Defaults over tuning              | A knob is only turned once something actually hurts        |
| Helm charts, upstream values      | Forking a chart is a maintenance bill with no payoff       |
| No service mesh, no multi-tenancy | There is one tenant and it is me                           |
| Environments are whole clusters   | Namespaces would make isolation a promise, not a property  |

Every one of these is paid per environment, which sharpens rather than softens them.

The measure of success is that the clusters stay understandable after six months of not
touching them.

## Documentation

Spec-driven: what has to be true, then how it is solved, then why that way. Nothing is
restated between layers.

| Read this | To find out |
| --- | --- |
| [CONSTITUTION.md](CONSTITUTION.md) | the rules, each citing the decision behind it |
| [docs/requirements.md](docs/requirements.md) | what the platform has to do, and which decision satisfies each |
| [docs/platform.md](docs/platform.md) | the system: the domain model, the mechanisms that span modules, the contracts |
| [docs/modules/](docs/README.md#specifications) | one folder per module: its spec and its own ADRs |
| [docs/adr/](docs/README.md#decisions) | platform-wide decisions — why, what it cost, when to revisit |
| [AGENTS.md](AGENTS.md) | orientation for coding agents, and what is currently blocked |

[docs/README.md](docs/README.md) is the map.

## Layout

One OpenTofu root module composes the cluster; each module it calls provisions Argo CD
resources — one `ApplicationSet` per module. Argo CD does the installing and the reconciling:
OpenTofu never talks to a workload, and never creates a bare Kubernetes object.

Specs come first. One module exists so far.

```
main.tf                        required_version, required_providers, provider, backend
variables.tf                   everything true of the cluster being addressed
<capability>.tf                one module block per capability this cluster ships
outputs.tf
modules/<capability>-<impl>/
  *.tf                         the OpenTofu that renders this module's ApplicationSet
  helm/<chart>/                a chart this repo authors, when no upstream one fits
modules/secret-template/       imported by the modules that need a credential; renders
                               nothing itself
docs/                          requirements, specs, decisions
```

That is the whole tree. Everything this repo contains provisions a platform capability into an
environment that already exists; nothing here runs the prerequisites
[the assumptions](#assumptions) name.

**An environment ships a module by having a `module` block for it.** There is no enable flag
and no inventory file — the composition *is* what is deployed, so it cannot drift
([ADR 020](docs/adr/020-one-root-module.md)).

Modules are named `<capability>-<implementation>`, and their outputs stay
implementation-neutral — `issuer_url`, not `keycloak_realm_id` — so the implementation half of
the name is genuinely swappable.

Every consumer module takes the same three optional inputs, each defaulting to `null`:
`gateway` (expose it), `database` (connect it), `oidc` (authenticate it). Credentials are
passed as Secret references, never values — and a module needing a Secret names it and shows
how to create it. A fourth input, `metrics`, is not a contract: it carries whether the cluster
scrapes and which tenant this workload's telemetry belongs to, and the root derives both. The
shapes are in [the platform spec](docs/platform.md#contracts).

Modules are wired by reference: a value one publishes and another consumes is
`module.<a>.<output>`, resolved at plan time in one graph
([ADR 020](docs/adr/020-one-root-module.md)).

### Running it

```sh
export KUBECONFIG=~/.kube/config
export ARGOCD_SERVER=... ARGOCD_AUTH_TOKEN=...   # this cluster's Argo CD
export PG_CONN_STR=postgres://...                # where this cluster's state lives

tofu init -backend-config=<backend file>
tofu plan  -var-file=<vars file>
```

**Export all three together, per environment.** They are what selects the cluster, and nothing
checks that they agree — a shell holding one cluster's `ARGOCD_SERVER` and another's
`PG_CONN_STR` will plan something meaningless and say nothing.

OpenTofu 1.9 or later. State is per environment, in a PostgreSQL
([ADR 012](docs/adr/012-state-is-per-environment.md)) — the backend file names the schema and
`PG_CONN_STR` carries the address and credential, so nothing in git holds one. The **database**
must already exist; the schema is created on first `init`. **Which PostgreSQL is deliberately
unspecified**: not necessarily the one this environment's workloads use, and not necessarily in
the cluster.

Both of these run offline — no PostgreSQL, no Argo CD — and are worth having before either:

```sh
tofu init -backend=false && tofu validate          # the composition

cd modules/certificate-management-cert-manager
tofu init -backend=false && tofu validate          # a module on its own
```

A module stays plannable by itself because it declares `required_providers` and no `provider`
block. That is also how its input `validation` blocks are exercised: they run before the
provider is configured, so a bad `-var-file` is refused with no cluster and no database.

Nothing here provisions a prerequisite. [ADR 008](docs/adr/008-postgresql-is-external.md) holds
without qualification: PostgreSQL is external, and no module knows or cares whether the instance
it addresses is managed, containerised, or a box under the desk. The same is true of the
cluster, its Argo CD and its Gateway.

## License

See [LICENSE](LICENSE).
