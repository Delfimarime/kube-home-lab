terraform {
  required_version = ">= 1.9"
}

# **This module creates nothing, and that is the point.** Every module here renders exactly one
# ApplicationSet, so a shared piece that rendered its own would give any consumer two — and a
# credential is not a capability with an implementation behind it, which is what every other
# directory under modules/ is.
#
# What it produces is one element for the caller's List generator: the git coordinates of the
# chart, the values it needs, and the wave it belongs in. The caller concatenates it into its own
# `charts` and keeps ownership of everything.
#
# It declares no provider for the same reason: there is no resource here to configure one for.
