# Documentation

Intent lives in the specs. The reasons live in the ADRs. Code implements the specs and
cites the ADRs.

```
docs/
  spec/
    platform.md                    intent, scope, shared contracts
    modules/*.md                   one per module: inputs, outputs, acceptance criteria
  adr/
    NNNN-*.md                      one decision each, with its consequences
```

## Specifications

| Spec | Covers |
| --- | --- |
| [platform](spec/platform.md) | intent, assumptions, the `gateway`/`database`/`oidc` contracts |
| [observability-victoria-metrics](spec/modules/observability-victoria-metrics.md) | metrics, logs, traces, Grafana |
| [openid-connect-zitadel](spec/modules/openid-connect-zitadel.md) | the OIDC issuer |
| [secret-manager-openbao](spec/modules/secret-manager-openbao.md) | secret storage and delivery |
| [audit-management-auditum](spec/modules/audit-management-auditum.md) | audit record API |

## Decisions

| ADR | Decision |
| --- | --- |
| [1](adr/0001-oidc-provider-zitadel.md) | OIDC provider is Zitadel |
| [2](adr/0002-observability-victoriametrics.md) | VictoriaMetrics family, three independent components |
| [3](adr/0003-grafana-standalone-and-alerting.md) | Standalone Grafana; alerting inside it |
| [4](adr/0004-scrape-config-via-prometheus-crds.md) | Scrape config through Prometheus operator CRDs |
| [5](adr/0005-one-argocd-application-per-module.md) | Each module renders its own Application |
| [6](adr/0006-routes-emitted-by-terraform.md) | Modules emit their own HTTPRoute |
| [7](adr/0007-modules-receive-credentials.md) | Providers publish addresses; consumers receive credentials |
| [8](adr/0008-postgresql-is-external.md) | PostgreSQL is external to this project |
| [9](adr/0009-secret-delivery-openbao-eso.md) | OpenBao plus External Secrets Operator |

## Traceability

| Requirement | Decided in | Implemented by |
| --- | --- | --- |
| One identity provider for the lab | ADR 1, 7 | `openid-connect-zitadel` |
| Metrics, logs and traces, independently switchable | ADR 2 | `observability-victoria-metrics` |
| One query UI regardless of which components are on | ADR 3 | `observability-victoria-metrics` |
| Scraping declared by charts, not by hand | ADR 4 | `observability-victoria-metrics` |
| Uniform ingress across chart and chartless workloads | ADR 6 | every module |
| No secret value in etcd or in a values file | ADR 7, 9 | every module |
| Durable audit records | ADR 8 | `audit-management-auditum` |

## Open questions

Tracked in the specs that own them:

- What Auditum is auditing — [audit-management-auditum](spec/modules/audit-management-auditum.md)
- How OpenBao unseals — [secret-manager-openbao](spec/modules/secret-manager-openbao.md)

## Making the specs executable

Acceptance criteria are written as Given/When/Then but are checked by hand today. The path
to executable is conftest against `terraform plan -json` for the structural criteria and
`kubectl` assertions for the runtime ones. That harness is not worth building before the
modules exist.
