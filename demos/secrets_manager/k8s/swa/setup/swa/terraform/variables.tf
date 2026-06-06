variable "trust_domain" {
  type        = string
  description = "SWA trust domain name (must match the agent's trustDomain.name)."
}

variable "server_group" {
  type        = string
  description = "Name of the server group (k8s_psat node attestation)."
}

variable "node_group" {
  type        = string
  description = "Name of the kubernetes node group (defines the workload SPIFFE ID template)."
}

variable "cluster_name" {
  type        = string
  description = "k8s_psat cluster name; must match the SWA Agent's nodeAttestor.k8s_psat.cluster."
}

variable "agent_namespace" {
  type        = string
  description = "Namespace where the SWA Agent + Server run."
}

variable "agent_sa" {
  type        = string
  description = "SWA Agent ServiceAccount name (allow-listed for k8s_psat node attestation)."
}

variable "server_sa" {
  type        = string
  description = "SWA Server ServiceAccount name (subject the control plane trusts for this server)."
}

variable "server_audience" {
  type        = string
  description = "JWT audience the SWA Server projects when authenticating to the control plane."
  default     = "conjur"
}

variable "psat_audience" {
  type        = string
  description = "Expected audience on the agent's PSAT node-attestation token."
  default     = "swa-server"
}

variable "cluster_jwks" {
  type        = string
  description = "Inline JWKS (JSON) from the cluster OIDC (kubectl get --raw /openid/v1/jwks). Used as the server's public_keys because Conjur Cloud cannot reach minikube."
}

variable "cluster_issuer" {
  type        = string
  description = "Cluster OIDC issuer (token 'iss' claim) for the SWA Server's projected SA token."
  default     = "https://kubernetes.default.svc.cluster.local"
}

variable "jwt_signature_algorithm" {
  type        = string
  description = "Trust domain JWT signing algorithm. Must be RSA (RS*) for the authn-jwt integration."
  default     = "RS256"
}

variable "jwt_signing_key_type" {
  type        = string
  description = "Trust domain JWT signing key type. Must be RSA_* for the authn-jwt integration."
  default     = "RSA_2048"
}

variable "jwt_token_ttl" {
  type        = number
  description = "TTL (seconds) for issued JWT-SVIDs (raised for a comfortable demo window)."
  default     = 3600
}

variable "jwt_signing_key_ttl" {
  type        = number
  description = "TTL (seconds) for trust domain signing keys."
  default     = 86400
}

variable "x509_workload_ttl" {
  type        = number
  description = "TTL (seconds) for issued X.509-SVIDs."
  default     = 3600
}
