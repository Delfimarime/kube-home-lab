# 008. PostgreSQL is external to this project

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-05

**PostgreSQL is not provisioned here — a module needing one receives `database` and names an
instance the environment already runs.**

## Decision

PostgreSQL is **not** provisioned by this project, for now. Modules that need a database
receive `var.database` per [ADR 007](007-modules-receive-credentials.md).

## Context

Keycloak needs PostgreSQL, and a second consumer was in scope when this was written — a workload
supporting SQLite or PostgreSQL, where PostgreSQL was the choice because it allows more than one
replica and therefore a meaningful rolling update.

Provisioning it here was considered — CloudNativePG with one small cluster per consumer,
which would have brought backup and point-in-time recovery for the two datasets whose loss
actually hurts.

## Rationale

Scope. This repo provisions workload-facing platform services; a database is a dependency
it consumes, like the cluster and Argo CD itself. Keeping it out means one fewer operator,
one fewer backup story, and no opinion imposed on where the data actually lives.

## Alternatives

- **CloudNativePG, one small cluster per consumer.** This was considered seriously and is the only
  option that would have brought backup and point-in-time recovery for the two datasets whose loss
  actually hurts. It was rejected on standing cost — an operator plus a cluster per consumer, paid
  daily on finite RAM — and on scope: a database is something an environment already has, which is
  the test [§1.1](../../CONSTITUTION.md#1-boundaries) applies.
- **An embedded or SQLite mode per workload.** Removes the dependency and the ability to run more
  than one replica with it, and moves the durability problem inside a pod's volume.
- **A single shared PostgreSQL provisioned here for every consumer.** Same standing cost as the
  first option with none of its recovery story, and it couples environments through one server —
  which is exactly the boundary [REQ-12](../requirements.md) declines to claim.

## Consequences

- No CloudNativePG module. The earlier `database-postgres-cloudnativepg` proposal is dropped.
- Backup, restore and availability of the database are out of scope and someone else's
  problem — which is a real answer only if someone else is actually solving it.
- Each consumer needs a `host_port`, a database, and a Secret with `username` and `password`
  keys supplied to it. Creating those is a manual prerequisite.
- `host_port` is one string, so each module pays a `split(":", …)`. One line.
- Each environment describes its own database configuration in its var file
  ([ADR 011](011-environments-are-clusters.md)). Whether two environments point at the same
  server is invisible to every module and is not constrained here — which also means REQ-12
  does not cover it.
- **OpenTofu's own state lives in a PostgreSQL too**
  ([ADR 012](012-state-is-per-environment.md)), and this decision covers it by the same
  reasoning: which instance, and where it runs, is not this repo's business. It is a separate
  concern from a consumer's database and is deliberately not assumed to be the same one.
- Revisit if supplying databases by hand becomes the annoying part. The consumer contract
  would not change — only who satisfies it.
