# 023. A module's OpenTofu is at its root

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-16 ·
the sentence keeping `helm/` inside the module superseded by
[ADR 027](027-charts-are-first-class-artifacts.md)

**A module's `.tf` files live at the module root, not under `tofu/`.**

## Decision

**A module's `.tf` files live at the module root.** `helm/<chart>/` stays where it is, as a
subdirectory of the module that owns the chart.

```
modules/<capability>-<implementation>/
  *.tf                    the OpenTofu that renders this module's ApplicationSet
  helm/<chart>/           a chart this repo authors, when no upstream one fits
```

Call sites become `source = "./modules/<name>"`. Nothing about what Argo CD reads changes: an
Application's `path` already pointed at `modules/<module>/helm/<chart>`, and it still does.

## Context

A module directory held two things: `tofu/`, carrying the `.tf` that renders its `ApplicationSet`,
and `helm/<chart>/` for a chart this repo authors. So a call site read
`source = "./modules/certificate-management-cert-manager/tofu"`, and every module had one
directory whose name described a tool rather than a thing.

That layout answers a question this repository does not have. `tofu/` distinguishes OpenTofu from
some other tool at the same level — but [ADR 019](019-the-tool-is-opentofu.md) settled that there
is one tool, and nothing else has ever wanted a peer directory. What the level actually costs is
one segment on every `source`, one on every `cd` in a runbook, and a small ambiguity about where
a new file goes.

The counter-argument is that `.tf` at the root puts configuration next to `helm/`, so a reader
sees both at once. That is true, and it is what makes it work: a module *is* its OpenTofu, and the
chart is a thing that OpenTofu points an Application at.

The cost of deciding is entirely in when. There are two modules today.

## Rationale

- **The directory named a tool, and there is one tool.** A level that distinguishes nothing from
  nothing is a level a reader has to hold anyway.
- **A module is its OpenTofu.** Everywhere else in this repository the directory is the thing —
  `docs/modules/<module>/` is the spec, `helm/<chart>/` is the chart. This makes `modules/<module>/`
  the module.
- **Now costs two directories; later costs every module.** The change is mechanical and it does
  not get cheaper.
- **Nothing depends on the old shape.** No Application path, no `.gitignore` rule, no runbook step
  survives it unchanged except the `source` lines, which are two.

## Alternatives

- **Keep `tofu/`**, which is what the layout had. It answers a question this repository does not
  have — distinguishing OpenTofu from some other tool at the same level — while costing one segment
  on every `source`, one on every `cd` in a runbook, and an ambiguity about where a new file goes.
- **Move the chart out too**, to a repository-level `charts/`. It separates a module from what it
  deploys, so a reader has to hold two paths, and it makes accidental sharing of a chart between
  modules the easy thing to do.

## Consequences

- **Every `source` in the root module changed**, once, and the old paths are gone rather than
  aliased. A checkout that fails to plan after this is a checkout that needs `tofu init` again.
- **`tofu init` in a module now leaves `.terraform/` beside `helm/`.** Cosmetic, gitignored, and
  the module is still plannable on its own with `tofu init -backend=false`.
- **A module directory holds `.tf` files and one subdirectory**, so §2.2's old sentence — "exactly
  two things" — no longer describes it and has been rewritten rather than reinterpreted.
- **Reversible mechanically**, and it will not be worth reversing: the argument for `tofu/` returns
  only if a module ever needs a second tool at the same level, and a module that did would have a
  bigger problem than its layout.
