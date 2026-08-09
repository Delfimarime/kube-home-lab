# LOCAL-002. OpenBao's seal

**Status:** proposed — no option chosen · **Scope:** module — `secret-manager-openbao` ·
**Date:** 2026-08-09

## Context

[LOCAL-001](LOCAL-001-openbao-and-eso.md) puts OpenBao in the lab and has ESO materialise
Secrets from it. None of that works while OpenBao is sealed, and by
[ADR 007](../../../adr/007-modules-receive-credentials.md) every credential the platform
references lives behind it. How it unseals is therefore the highest-stakes unresolved
question in this repository.

[ADR 011](../../../adr/011-environments-are-clusters.md) makes it worse: each environment
runs its own OpenBao, so whatever is chosen is operated once per environment.

PKCS#11 being open source in OpenBao and Enterprise-only in Vault was part of the reason for
choosing OpenBao. That widened the option set; it did not pick from it.

## Options

| | Unattended across reboots | Root of trust | Cost |
| --- | --- | --- | --- |
| **TPM 2.0 via PKCS#11** | yes | real, hardware | Key bound to that machine — node death means restore from backup, not migrate. Needs the `kms` plugin (OpenBao 2.6+) and a token on the host |
| SoftHSM2 | yes | none worth the name | The key sits on disk beside what it protects. Convenience, not security |
| Transit seal from a second OpenBao | yes | inherited | Moves the problem to a second instance that still needs unsealing. Only worth it if that one lives somewhere more durable |
| Shamir, unsealed by hand | no | the operator | Honest, and fine at monthly reboots. Not fine at weekly ones |

## Decision

**None yet.** Shamir with manual unsealing is the status quo and the honest fallback.

TPM 2.0 via PKCS#11 is the only option that is both unattended and not self-defeating on a
single node, and is the presumptive answer if one is needed. SoftHSM2 is listed to be ruled
out explicitly rather than rediscovered later as an apparent shortcut.

## Consequences of not deciding

- A reboot leaves OpenBao sealed and, downstream, a Zitadel that will not start — because its
  masterkey Secret is one of the things ESO has not materialised. Survivable at monthly
  reboots; not at weekly ones. Which of those the lab does is the thing that decides this
  ADR.
- Whichever is chosen, backup of OpenBao's storage remains out of scope and
  [REQ-04](../../../requirements.md) leans on it. That gap is independent of the seal and is
  not closed by resolving this.
- The acceptance criterion
  [SEC-04](../README.md#acceptance-criteria) deliberately asserts only that restart behaviour
  is *known and documented*, not that it is unattended. It stays satisfiable while this is
  unresolved, and gets stricter when it is.
