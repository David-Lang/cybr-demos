terraform {
  required_providers {
    swa = {
      source  = "registry.terraform.io/cyberark/swa"
      version = "0.1.0-SNAPSHOT"
    }
  }
}

provider "swa" {
  url          = var.conjur_url
  access_token = var.conjur_token
}

resource "swa_trust_domain" "demo" {
  name = var.trust_domain_name

  jwt = {
    signature_algorithm = "RS256"
    signing_key_type    = "RSA_2048"
    signing_key_ttl     = 86400
    token_ttl           = 600
  }
}

resource "swa_server_group" "demo" {
  name              = "${var.resource_prefix}-server-group"
  trust_domain_name = swa_trust_domain.demo.name
  description       = ""

  node_attestation = {
    k8s_psat = {
      clusters = {
        (var.cluster_name) = {
          service_account_allow_list = [
            "${var.swa_namespace}:swa-agent",
          ]
          public_keys = var.k8s_public_keys
          issuer      = var.k8s_issuer
        }
      }
    }
  }
}

resource "swa_server" "demo" {
  name            = "${var.resource_prefix}-server"
  server_group_id = swa_server_group.demo.id

  auth = {
    type        = "JWT"
    subject     = var.server_jwt_subject
    audience    = "conjur"
    public_keys = var.k8s_public_keys
    issuer      = var.k8s_issuer
  }
}

resource "swa_node_group" "demo" {
  name              = var.node_group_name
  trust_domain_name = swa_trust_domain.demo.name
  server_group_name = swa_server_group.demo.name
  workload_type     = "unix"

  workload_configuration = {
    spiffe_id_template = "spiffe://{{ .trustdomain }}/{{ .nodegroup }}/workload/{{ .unix.uid }}"
    workload_registration_policies = [
      "unix.uid == 1000",
    ]
  }
}
