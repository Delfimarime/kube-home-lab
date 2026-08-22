# Two addresses and nothing else. **There is deliberately no client output**: this module
# registers no client, holds no client secret, and knows nothing about who authenticates against
# it. A consumer receives one URL and never assembles it.
#
# Nothing is sensitive and nothing is marked so, because there is no credential here to protect —
# which is the property `OIDC-01` checks.
#
# Both carry the realm, and both are built from the same string the server is given as its own
# hostname. That is what makes `OIDC-03` — the discovery document's `issuer` equalling the output
# below — a check rather than a hope.

output "issuer_url" {
  value       = local.issuer_url
  description = "The OIDC issuer. A consumer's oidc.issuer_url reads this."
}

output "discovery_url" {
  value       = local.discovery_url
  description = "The OpenID Connect discovery document for the same issuer."
}
