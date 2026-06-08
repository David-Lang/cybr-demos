terraform {
  required_providers {
    swa = {
      source  = "cyberark/swa"
      version = "0.1.0"
    }
  }
}

# Authentication resolves from the environment exported by enable/go scripts:
#   CONJUR_APPLIANCE_URL  = https://<subdomain>.secretsmgr.cyberark.cloud/api
#   CONJUR_AUTHN_TOKEN    = <base64 Conjur access token>
provider "swa" {}

# Trust domain — RSA signing is required for the authn-jwt integration.
resource "swa_trust_domain" "this" {
  name = var.trust_domain

  jwt = {
    signature_algorithm = var.jwt_signature_algorithm
    signing_key_type    = var.jwt_signing_key_type
    signing_key_ttl     = var.jwt_signing_key_ttl
    token_ttl           = var.jwt_token_ttl
  }

  x509 = {
    workload_ttl = var.x509_workload_ttl
  }
}

# Server group with Kubernetes PSAT node attestation. The agent's PSAT token
# (service account = <agent_namespace>/<agent_sa>) must be on the allow-list.
resource "swa_server_group" "k8s" {
  name              = var.server_group
  description       = "Kubernetes workload server group (k8s_psat) for the SWA demo"
  trust_domain_name = swa_trust_domain.this.name

  node_attestation = {
    k8s_psat = {
      clusters = {
        (var.cluster_name) = {
          # SWA Server matches the agent SA in "namespace:serviceaccount" form.
          service_account_allow_list = [
            "${var.agent_namespace}:${var.agent_sa}",
          ]
          audience               = [var.psat_audience]
          allowed_pod_label_keys = ["app"]
        }
      }
    }
  }
}

# Kubernetes node group — defines the workload SPIFFE ID template.
# Yields: spiffe://<trustdomain>/<nodegroup>/ns/<ns>/sa/<sa>
resource "swa_node_group" "k8s" {
  name              = var.node_group
  trust_domain_name = swa_trust_domain.this.name
  server_group_name = swa_server_group.k8s.name
  workload_type     = "kubernetes"
  description       = "Kubernetes node group for the SWA demo"

  workload_configuration = {
    spiffe_id_template = "spiffe://{{ .trustdomain }}/{{ .nodegroup }}/ns/{{ .k8s.ns }}/sa/{{ .k8s.sa }}"
  }
}

# Register the in-cluster SWA Server. Uses inline public_keys (cluster OIDC JWKS)
# because Conjur Cloud cannot reach a minikube JWKS endpoint. The authn_id output
# feeds the swa-server helm chart (controlPlane.auth.authnID).
resource "swa_server" "this" {
  name            = "${var.cluster_name}-swa-server"
  server_group_id = swa_server_group.k8s.id

  auth = {
    type        = "JWT"
    subject     = "system:serviceaccount:${var.agent_namespace}:${var.server_sa}"
    audience    = var.server_audience
    issuer      = var.cluster_issuer
    public_keys = jsonencode({ type = "jwks", value = jsondecode(var.cluster_jwks) })
  }
}

output "trust_domain_name" {
  value = swa_trust_domain.this.name
}

output "server_group_name" {
  value = swa_server_group.k8s.name
}

output "node_group_name" {
  value = swa_node_group.k8s.name
}

output "server_address" {
  value = "${var.trust_domain}/${var.server_group}"
}

output "server_authn_id" {
  value     = swa_server.this.authn_id
  sensitive = true
}
