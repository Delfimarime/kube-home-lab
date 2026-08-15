# 019. The tool is OpenTofu

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-15

## Context

This repository is written in the Terraform language and driven by Terragrunt. Two
implementations run that language: HashiCorp Terraform, under the BUSL since 1.6, and OpenTofu,
an MPL-2.0 fork under the Linux Foundation. They share the language and the provider protocol,
and diverge on licence, registry, release cadence and a handful of features.

The choice was implicit until now — `terraform` appeared in every runbook and every Gherkin
scenario, and the binary actually on the machine was `tofu`. That is the sort of gap that costs
an afternoon the first time someone new follows the documentation exactly.

## Decision

**OpenTofu.** `tofu` is the binary named everywhere, `required_version` is read as an OpenTofu
version, and providers resolve from OpenTofu's registry.

**"Terraform" in these documents means the *language*.** Where the tool is meant, it is called
OpenTofu or `tofu`. Prose that says one and means the other is a defect, not a synonym.

## Rationale

- **The licence is the whole of it.** BUSL asks a homelab to accept terms it has no reason to
  accept, in exchange for nothing it needs. MPL-2.0 asks nothing.
- **Nothing else in the stack cares.** Terragrunt drives both. The one provider this repo
  depends on — `argoproj-labs/argocd` — is published to both registries.
- **Feature parity holds where this repo actually leans.** `required_version >= 1.9` exists
  because a `validation` block references a second variable, and OpenTofu has that; it is
  verified working on 1.12.
- **Naming it costs one ADR and saves a category of confusion.** `>= 1.9` means a different
  feature set in each implementation, so a version constraint with no named tool is ambiguous in
  exactly the way version constraints exist to prevent.

## Consequences

- **`required_version` is an OpenTofu constraint and must not be read across.** The same number
  is a different feature set in Terraform.
- **Providers resolve from OpenTofu's registry.** One published only to HashiCorp's would need a
  mirror; none does today, and a module that needed such a provider would be a decision, not a
  detail.
- **Every runbook and every `@plan` scenario says `tofu`.** A scenario that says `terraform plan`
  describes a command nobody runs.
- **Reversible, and cheaply.** The language is shared, so switching back is a binary and a
  registry rather than a rewrite. What would not survive is any use of an OpenTofu-only feature —
  state encryption, `for_each` in provider blocks — and none is used. Adopting one would make
  this decision expensive to reverse, which is the point at which it should be revisited rather
  than assumed.
