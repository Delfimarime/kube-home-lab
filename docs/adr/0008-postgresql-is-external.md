# 8. PostgreSQL is external to this project

**Status:** accepted · **Date:** 2026-08-05

## Context

Zitadel needs PostgreSQL. Auditum supports SQLite or PostgreSQL, and PostgreSQL is the
choice there because it allows more than one replica and therefore a meaningful rolling
update.

Provisioning it here was considered — CloudNativePG with one small cluster per consumer,
which would have brought backup and point-in-time recovery for the two datasets whose loss
actually hurts.

## Decision

PostgreSQL is **not** provisioned by this project, for now. Modules that need a database
receive `var.database` per [ADR 7](0007-modules-receive-credentials.md).

## Rationale

Scope. This repo provisions workload-facing platform services; a database is a dependency
it consumes, like the cluster and Argo CD itself. Keeping it out means one fewer operator,
one fewer backup story, and no opinion imposed on where the data actually lives.

## Consequences

- No CloudNativePG module. The earlier `database-postgres-cloudnativepg` proposal is dropped.
- Backup, restore and availability of the database are out of scope and someone else's
  problem — which is a real answer only if someone else is actually solving it.
- Each consumer needs a `host_port`, a database, and a Secret with `username` and `password`
  keys supplied to it. Creating those is a manual prerequisite.
- `host_port` is one string, so each module pays a `split(":", …)`. One line.
- Revisit if supplying databases by hand becomes the annoying part. The consumer contract
  would not change — only who satisfies it.
