# Two addresses and nothing else.
#
# **They are two trust levels rather than one address with a credential.** A consumer given the
# read address cannot write no matter what it does with it, and that is a property of the address
# rather than of anything it holds. That is the whole reason this store was chosen over one with a
# single API and a token.
#
# Nothing here is sensitive and nothing is marked so, because there is no credential to protect —
# the store authenticates nobody, and what protects the write address is the network policy alone.
#
# **Neither names the model.** An application that needs to know which relations exist reads this
# repository, not the store — a permission graph is not a discovery endpoint.
#
# There is deliberately no output for the Secret's name: it is fixed rather than derived, stated in
# the module's spec, and an operator reads it there before typing the `kubectl patch`.

output "read_url" {
  value       = local.read_url
  description = "Where applications ask authorization questions. Open in-cluster and unauthenticated."
}

output "write_url" {
  value       = local.write_url
  description = "Where relation tuples are created and deleted, by the applications that grant access."
}
