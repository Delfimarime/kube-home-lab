# kube-home-lab

A homelab platform on k3s. Small cluster, few services, deliberately boring.

This repo holds the manifests for the _platform_ layer — observability and the shared
services workloads depend on. Cluster bootstrap is out of scope.

## Assumptions

The cluster already exists and already runs:

- **k3s** — single node or a couple of them
- **Argo CD** — everything here is applied by Argo CD, not `kubectl apply`
- **Gateway API (Traefik)** — ingress is a `HTTPRoute`, never an `Ingress`

If any of those is missing, this repo does nothing useful.

PostgreSQL is also assumed to exist, supplied from outside this project.

## Scope

Provision workload-facing platform services:

| Module | Provides |
| --- | --- |
| `observability-victoria-metrics` | metrics, logs and traces — each independently switchable — behind one Grafana |
| `openid-connect-zitadel` | one OIDC issuer for the lab |
| `secret-manager-openbao` | secret storage, and delivery into namespaces |
| `audit-management-auditum` | an audit record API |

Intent and acceptance criteria live in [docs/spec](docs/spec/platform.md). The reasoning
behind each choice lives in [docs/adr](docs/README.md#decisions).

## Rationale

Homelab, not production. Choices follow from that:

| Choice                            | Why                                                  |
| --------------------------------- | ---------------------------------------------------- |
| One replica of everything         | Nothing here is worth an HA story on one node        |
| Short retention                   | Disk is the scarce resource, not history             |
| Defaults over tuning              | A knob is only turned once something actually hurts  |
| Helm charts, upstream values      | Forking a chart is a maintenance bill with no payoff |
| No service mesh, no multi-tenancy | There is one tenant and it is me                     |

The measure of success is that the cluster stays understandable after six months of
not touching it.

## Layout

Terragrunt declares the Argo CD `Application` for each platform service. Argo CD does the
installing and the reconciling — Terraform never talks to a workload.

Specs come first; only `docs/` exists so far.

```
root.hcl                              backend + kubernetes provider, included by every unit
docs/spec/                            what is being built, and how to tell it worked
docs/adr/                             why, and what it costs
modules/<capability>-<impl>/          each renders its own Argo CD ApplicationSet
platform/<unit>/terragrunt.hcl        one unit per module, with its inputs
```

Modules are named `<capability>-<implementation>`, and their outputs stay
implementation-neutral — `issuer_url`, not `zitadel_org_id` — so the implementation half of
the name is genuinely swappable.

Every consumer module takes the same three optional inputs, each defaulting to `null`:
`gateway` (expose it), `database` (connect it), `oidc` (authenticate it). Credentials are
passed as Secret references, never values.

```sh
export KUBECONFIG=~/.kube/config
terragrunt run --all plan             # or `cd platform/cert-manager && terragrunt apply`
```

State is a local file under `.tfstate/`, gitignored. It holds nothing but Application specs.

## License

See [LICENSE](LICENSE).
