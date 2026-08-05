# 5. Each module renders its own Argo CD Application

**Status:** accepted · **Date:** 2026-08-05

## Context

An earlier scaffold had a shared `argocd-app` module that every unit called with a chart
name and values. The alternative is for each module to render its own Application inline.

## Decision

Every module provisions its own Argo CD `Application` — or `ApplicationSet` where a
generator is warranted. There is no shared Application module.

## Rationale

Each module is readable on its own, with no indirection to chase, and can be copied as a
starting point for the next one. The shared module saved boilerplate at the cost of making
every module a partial description of itself.

`ApplicationSet` stays in the convention but is unused today. A generator earns its place
when it discovers things Terraform does not already know — git directories, cluster labels,
a list that changes without an apply. The observability module's four components are all
known at plan time, so `for_each` over four Applications is simpler than an ApplicationSet
whose list generator is a constant.

## Consequences

- Roughly 25 lines of Application boilerplate repeated per module.
- A global change to `syncPolicy` or `syncOptions` touches every module. With four modules
  this is tolerable; revisit if it starts to itch.
