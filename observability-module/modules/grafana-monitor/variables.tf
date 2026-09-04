variable "name" {
  type        = string
  description = "Human-readable name for this alert rule. Also used as the name of the Grafana rule group that wraps it."
}

variable "promql_expr" {
  type        = string
  description = "PromQL expression evaluated by this alert rule. Fully caller-defined — this module has no opinion on what is being measured."
}

variable "threshold" {
  type        = number
  description = "Numeric value the query result is compared against."
}

variable "comparison" {
  type        = string
  description = "Comparison operator between the query result and threshold. Restricted to what Grafana's classic condition evaluator supports for a simple last-value check."

  validation {
    condition     = contains(["gt", "lt"], var.comparison)
    error_message = "comparison must be one of: \"gt\", \"lt\"."
  }
}

variable "severity" {
  type        = string
  description = "Alert severity. Emitted as a label that an existing, externally-managed notification policy routes on — this module does not create contact points or routing rules."

  validation {
    condition     = contains(["critical", "warning", "info"], var.severity)
    error_message = "severity must be one of: \"critical\", \"warning\", \"info\"."
  }
}

variable "folder_uid" {
  type        = string
  description = "UID of the Grafana folder that will contain this alert rule."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Additional labels merged onto the alert rule, on top of the mandatory severity label."
}

variable "for_duration" {
  type        = string
  default     = "5m"
  description = "How long the condition must hold true before the alert fires."
}

variable "datasource_uid" {
  type        = string
  default     = "prometheus"
  description = "UID of the Prometheus datasource this rule queries against. Defaults to the conventional \"prometheus\" UID used by this org's Grafana provisioning; override if a given environment's datasource UID differs."
}

variable "evaluation_interval_seconds" {
  type        = number
  default     = 60
  description = "How often Grafana evaluates this rule group, in seconds."
}
