# 028. A module renders the network policy its own guarantee depends on

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-23

**A module with a port that is protected only by nothing else being able to reach it renders the
`NetworkPolicy` that makes that true — admitting a caller an existing input already names, and
re-opening every other port explicitly.**

## Decision

**The module renders the policy**, in the chart its own `ApplicationSet` points at. Not the root,
not a separate network module: the module is what knows which of its ports carries the guarantee,
and a policy applied by something else is a guarantee held one directory away from the thing that
depends on it.

Three obligations, and the second and third are where this gets got wrong:

1. **The selector rides on the input that already names the caller.** A module gets a dedicated
   selector input only when nothing it already takes names that caller.
   `resource-authorization-ory-keto` takes `write_access_from`, because its callers are workloads
   it has no other reason to know about — and this repository does not deploy them, so there is no
   module output to read them from either.
2. **Every port the policy does not restrict is re-opened explicitly.** A `NetworkPolicy` that
   selects a pod switches that pod to default-deny for the directions it names. There is no partial
   application: restricting one port closes all of them unless the others are named again. The
   rule that re-opens them looks redundant and is not.
3. **`policyTypes` names `Ingress` only.** Adding `Egress` gives the pod default-deny outbound —
   which for the store means losing PostgreSQL, and so losing every tuple it was protecting. A
   wider blast radius than the policy was written to have.

## Context

`resource-authorization-ory-keto` runs a write API with **no authentication of its own** — Ory's
documented design, and the recorded cost of choosing that store. Anything able to address the port
writes what it likes, including a tuple granting itself everything.

So the whole protection of that path is a statement about the network — *nothing else can reach
this port* — and nothing in this repository was making it. Kubernetes has a mechanism for saying
it, and no module here had ever rendered one.

**It is platform-scoped although one module implements it today.** What is decided here is not
which port that module protects — it is the shape every such policy takes, and the three ways of
getting one wrong that are silent when wrong. A second module rendering one would need all of it
unchanged, which is the test for where a decision belongs rather than how many places currently
obey it.

## Rationale

- **The obligations are general, and only the first is obvious.** That a module renders its own
  policy is arguable either way; that a policy closes every port it does not name, and that
  `Egress` has a blast radius nobody intends, are facts about the mechanism rather than about any
  module — and a second module would rediscover them the expensive way.
- **The selector belongs to whoever already names the caller**, because a second input holding the
  same fact is the drift [§4.5](../../CONSTITUTION.md#4-composition) exists to prevent. A module
  naming one workload once as a route target and again as a policy subject would give a route that
  resolves to a port refusing it — a timeout at request time, with both objects reconciled healthy.
- **The default-deny obligation is stated as a rule because it is invisible in review.** A policy
  restricting one port reads as restricting one port. What it does is close the rest, and the
  symptom is every consumer of the open port timing out against a green cluster.

## Alternatives

- **The root renders the policies**, one place for the cluster's network posture. It reads tidier
  and separates the guarantee from the thing guaranteed: a module would then depend on a resource
  it cannot see, and [ADR 010](010-resources-delivered-via-chart.md) would have to give up
  OpenTofu creating no bare objects.
- **A dedicated selector input per module**, uniform across all of them. Simpler to describe, and
  it puts a caller in two places in any module that already names it for another reason.
- **A service mesh**, authenticating pod to pod and making none of this depend on the CNI. It is a
  control plane plus a sidecar per pod on a two-node cluster
  ([§1.4](../../CONSTITUTION.md#1-boundaries)).
- **Say nothing about the network and rely on what is in front of the port.** What the whole
  decision exists to reject: whatever fronts a service protects the route to it, and a pod
  addressing the service directly never takes that route.

## Consequences

- **Enforcement is an assumption this repository cannot check.** A `NetworkPolicy` in a cluster
  that does not enforce them reconciles healthy and does nothing, and the failure is silent and
  total. It is on firmer ground than it reads: k3s enforces them by default through an embedded
  kube-router controller, and disabling it takes `--disable-network-policy`. That makes the
  assumption *"this cluster was not started with that flag"* rather than *"this CNI happens to
  implement policy"*, and it is stated in [the assumptions](../../README.md#assumptions).
- **A wrong selector fails open, not closed.** Admitting nobody breaks the caller visibly, which is
  safe. Admitting more than intended looks exactly like admitting the right thing, and nothing
  compares a selector to what the caller actually runs as.
- **`namespaceSelector` and `podSelector` in one `from` element are an AND; in two they are an
  OR.** One indent apart, and the OR form admits every pod in the namespace *plus* every pod
  carrying those labels anywhere in the cluster. Both forms pass a test that only checks the
  intended caller gets through.
- **The network is the whole boundary where it applies.** Nothing authenticates the caller of a
  port protected this way, so reachability *is* the permission. A wrong selector does not weaken a
  second layer, because there is no second layer.
- **Revisit if a second module wants one.** That is the point to ask whether network posture
  belongs in a chart at all, or in something that sees the whole cluster — the question is cheap to
  answer with two examples and guesswork with one.
