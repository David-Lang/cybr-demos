variable "conjur_url" {
  description = "Conjur SaaS API URL."
  type        = string
}

variable "conjur_token" {
  description = "Conjur access token used by the Terraform provider."
  type        = string
  sensitive   = true
}

variable "trust_domain_name" {
  description = "SWA trust domain name."
  type        = string
}

variable "resource_prefix" {
  description = "Prefix for SWA resource names."
  type        = string
}

variable "node_group_name" {
  description = "SWA node group name."
  type        = string
}

variable "cluster_name" {
  description = "Kubernetes cluster name used by k8s_psat node attestation."
  type        = string
}

variable "swa_namespace" {
  description = "Namespace where SWA Helm releases are installed."
  type        = string
}

variable "k8s_public_keys" {
  description = "Kubernetes JWKS JSON used by k8s_psat node attestation."
  type        = string
}

variable "k8s_issuer" {
  description = "Kubernetes OIDC issuer."
  type        = string
}

variable "k8s_jwks_uri" {
  description = "Kubernetes OIDC JWKS URI."
  type        = string
}

variable "server_jwt_subject" {
  description = "Kubernetes service account subject for the SWA Server pod."
  type        = string
}

variable "workload_namespace" {
  description = "Kubernetes namespace allowed to receive the demo workload SPIFFE ID."
  type        = string
}

variable "workload_service_account" {
  description = "Kubernetes service account allowed to receive the demo workload SPIFFE ID."
  type        = string
}
