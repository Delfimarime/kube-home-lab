# LOCAL-002. The write port admits only the caller it is told to admit

**Status:** accepted · **Scope:** module — `resource-authorization-ory-keto` · **Date:** 2026-08-23

**The write port admits only the pod selector its caller names; the read port is left
unrestricted.**

## Decision

**This module renders a `NetworkPolicy` restricting its write port to a pod selector its caller
supplies**, and leaves the read port unrestricted.

The module does not know what it is admitting. It takes a selector as an input, renders it, and
publishes nothing about it; which workload that selector names is the composing root's business.

## Context

The store this module runs has no authentication of its own
([LOCAL-001](LOCAL-001-the-store-is-ory-keto.md)). Its write API is fronted by a proxy that
authenticates callers, and the read API is deliberately open to the cluster.

**A proxy protects a route, not a service.** Everything reaching the write port *through* the
proxy is authenticated; anything reaching that port by another path is not, and there is nothing
in the store to stop it. In a cluster with flat pod networking, "another path" means any pod.

So the proxy's guarantee is conditional on a statement about the network — *nothing else can reach
this port* — and nothing in this repository makes that statement true. Kubernetes has a mechanism
for it, and no module here has ever rendered one.

## Rationale

- **Without it, the proxy is decoration.** The whole authentication design for the write path
  assumes the port is not otherwise reachable. Stating that assumption in an object the cluster
  can enforce is the difference between a security property and an intention.
- **Taking a selector rather than naming the proxy is what keeps this decision local.** A module
  that decided "only the access proxy may write" would be reaching into another module's business,
  and reversing it would change that module too — which by
  [§10.4](../../../../CONSTITUTION.md#10-documentation) would make it a platform decision wearing a
  module's number. Phrased as *what the caller names*, reversing it changes nothing outside this
  directory, and the wiring is an ordinary root-level pass
  ([§4.2](../../../../CONSTITUTION.md#4-composition)).
- **The read port is left open on purpose.** Restricting it would mean naming every workload that
  might ever ask an authorization question, which is every application in the cluster and the ones
  not written yet. The cost of leaving it open is stated in
  [LOCAL-001](LOCAL-001-the-store-is-ory-keto.md) and was accepted there.

## Alternatives

- **Rely on the proxy alone.** What this decision exists to reject: everything reaching the write
  port *through* the proxy is authenticated, and nothing stops a pod reaching it directly.
- **Name the access proxy in this module** rather than taking a selector. Reversing it would then
  change that module too, which by [§10.4](../../../../CONSTITUTION.md#10-documentation) makes it
  a platform decision wearing a module's number.
- **Restrict the read port as well.** It means naming every workload that might ever ask an
  authorization question — every application in the cluster, including the ones not written yet.
- **A service mesh** authenticating pod to pod. It would make the guarantee independent of the
  CNI, and it is a control plane and a sidecar per pod on a two-node cluster.

## Consequences

- **This is the only `NetworkPolicy` in the repository, and it is an exception.** No platform rule
  says modules render their network posture, and this one does not establish that they should.
  **The moment a second module wants one, this stops being an exception** — a decision reaching two
  modules is platform-scoped by [§10.4](../../../../CONSTITUTION.md#10-documentation), and the
  correct response then is to lift it rather than to copy this file. Copying it is the failure
  mode; the second module is the trigger to watch for.
- **Nothing verifies that anything enforces it.** A `NetworkPolicy` in a cluster whose CNI does not
  implement one is a resource that reconciles healthy and does nothing. Whether the CNI enforces is
  a property of the cluster, which this repository never provisions
  ([§1.1](../../../../CONSTITUTION.md#1-boundaries)) and therefore cannot check. **The failure is
  silent and it is total**: everything stays green and the write path is open to every pod in the
  cluster. This is the single largest assumption in this module.
- **An empty or wrong selector fails open, not closed.** A policy admitting nobody would break
  writes visibly, which is safe; a selector matching more than intended admits more than intended
  and looks identical to a correct one. Nothing compares the selector to what the proxy actually
  runs as.
- **The policy is one half of a pair held in two modules.** The port is restricted here and the
  authentication happens elsewhere, so reading either file alone understates what protects this
  path. Each says so.
