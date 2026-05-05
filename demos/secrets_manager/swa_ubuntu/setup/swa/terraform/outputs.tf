output "trust_domain_id" {
  description = "SWA trust domain UUID — used to derive the OIDC issuer URL"
  value       = swa_trust_domain.demo.id
}

output "trust_domain_name" {
  value = swa_trust_domain.demo.name
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for this trust domain — used as Conjur jwks-uri base and issuer"
  value       = "https://api.venafi.cloud/swa/v1/issuers/${swa_trust_domain.demo.id}"
}

output "server_login_url" {
  description = "Conjur login URL for the SWA Server — goes into bootstrapConfig.yaml loginURL"
  value       = swa_server.demo.login_url
}

output "node_group_name" {
  value = swa_node_group.demo.name
}

output "spiffe_id_prefix" {
  description = "SPIFFE ID prefix for workloads — sub claim format: <prefix>/workload/<unix-user>"
  value       = "spiffe://${swa_trust_domain.demo.name}/${swa_node_group.demo.name}"
}
