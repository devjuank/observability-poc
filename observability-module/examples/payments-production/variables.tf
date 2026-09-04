variable "grafana_url" {
  type        = string
  default     = "http://localhost:3000"
  description = "Base URL of the Grafana instance to manage. Placeholder default so this configuration validates without a live Grafana; override when applying against a real instance (see the root README's \"Extending to a live environment\" section)."
}

variable "grafana_auth" {
  type        = string
  default     = "anonymous"
  sensitive   = true
  description = "Grafana auth string: a service account token, \"user:password\", or \"anonymous\". Placeholder default for local validation only — never commit a real token here; pass it via TF_VAR_grafana_auth or a .tfvars file excluded from version control."
}

variable "folder_uid" {
  type        = string
  default     = "payments-production"
  description = "UID of the Grafana folder for this service's alerts/dashboard. In a real environment this would reference an existing platform-managed folder (e.g. via a data source or remote state) rather than a literal default."
}
