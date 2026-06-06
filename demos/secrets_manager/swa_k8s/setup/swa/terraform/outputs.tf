output "trust_domain_id" {
  value = swa_trust_domain.demo.id
}

output "trust_domain_name" {
  value = swa_trust_domain.demo.name
}

output "oidc_issuer_url" {
  value = "${var.conjur_url}/swa/trust-domains/${swa_trust_domain.demo.name}"
}

output "server_login_url" {
  value = swa_server.demo.login_url
}

output "node_group_name" {
  value = swa_node_group.demo.name
}

output "spiffe_id_prefix" {
  value = "spiffe://${swa_trust_domain.demo.name}/${swa_node_group.demo.name}"
}
