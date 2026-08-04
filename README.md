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

## Scope

Provision workload-facing platform services:

- Metrics, logs and dashboards
- Alerting to one place
- The shared bits workloads keep asking for (certs, secrets, storage)

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

Each service is a directory of manifests, picked up by Argo CD.

## License

See [LICENSE](LICENSE).
