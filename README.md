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
- **PostgreSQL** — reachable, described in that environment's `env.hcl`

If any of those is missing, this repo does nothing useful for that environment.

## Scope

Provision workload-facing platform services. Each environment ships the ones it wants:

| Module | Provides |
| --- | --- |
| `observability-victoria-metrics` | metrics, logs and traces — each independently switchable — behind one Grafana |
| `openid-connect-zitadel` | one OIDC issuer for the environment |
| `secret-manager-openbao` | secret storage, and delivery into namespaces |
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
| [docs/requirements.md](docs/requirements.md) | what the platform has to do, and which decision satisfies each |
| [docs/platform.md](docs/platform.md) | the domain model, the shared contracts, the acceptance criteria |
| [docs/modules/](docs/README.md#specifications) | one folder per module: its spec and its own ADRs |
| [docs/adr/](docs/README.md#decisions) | platform-wide decisions — why, what it cost, when to revisit |
| [AGENTS.md](AGENTS.md) | the conventions an implementer must not break |

[docs/README.md](docs/README.md) is the map.

## Layout

Terragrunt handles the monorepo and the environments. The Terraform modules provision Argo CD
resources — one `ApplicationSet` per module. Argo CD does the installing and the reconciling:
Terraform never talks to a workload, and never creates a bare Kubernetes object.

Specs come first; only `docs/` exists so far.

```
root.hcl                       provider + remote_state generation, included by every unit
_envcommon/<module>.hcl        inputs shared by a module across environments
<env>/
  env.hcl                      cluster endpoint, hostnames, database host/port
  <unit>/terragrunt.hcl        includes root.hcl and _envcommon; holds only the deltas
modules/<capability>-<impl>/   the Terraform
docs/                          requirements, specs, decisions
```

**An environment ships a module by having a unit directory for it.** There is no enable flag
and no inventory file — `ls <env>/` is the answer, so it cannot drift.

Modules are named `<capability>-<implementation>`, and their outputs stay
implementation-neutral — `issuer_url`, not `zitadel_org_id` — so the implementation half of
the name is genuinely swappable.

Every consumer module takes the same three optional inputs, each defaulting to `null`:
`gateway` (expose it), `database` (connect it), `oidc` (authenticate it). Credentials are
passed as Secret references, never values. The shapes are in
[the platform spec](docs/platform.md#shared-contracts).

```sh
export KUBECONFIG=~/.kube/config
terragrunt run --all plan                        # from an environment directory
cd prod/openid-connect-zitadel && terragrunt apply
```

Terraform 1.9 or later. State is per environment
([ADR 012](docs/adr/012-state-is-per-environment.md)) — a local file under `.tfstate/` today,
gitignored, with a Kubernetes backend intended. It holds nothing but ApplicationSet specs,
which is what makes keeping it in-cluster defensible.

## License

See [LICENSE](LICENSE).
