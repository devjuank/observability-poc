variable "service_name" {
  type        = string
  description = "Name of the service being observed. Used to prefix alert rule names and to scope PromQL queries and the dashboard."
}

variable "environment" {
  type        = string
  description = "Environment this instance targets (e.g. \"staging\", \"production\"). Used for labeling only — thresholds are controlled independently via the threshold variables below."
}

variable "folder_uid" {
  type        = string
  description = "UID of the Grafana folder that will contain this service's alert rules and dashboard. In a real environment this typically references a platform-managed folder rather than being created by this module."
}

variable "datasource_uid" {
  type        = string
  default     = "prometheus"
  description = "UID of the Prometheus datasource backing every default monitor and every dashboard panel."
}

# --- RED thresholds (service-level signals) ---

variable "error_rate_threshold_pct" {
  type        = number
  default     = 2
  description = <<-EOT
    Error rate (%) above which the alert fires. 2% is set for a payment
    authorization path specifically: normal gateway/client error noise sits
    well under 1%, so 2% is high enough to avoid paging on noise but low
    enough to catch a real outage before it shows up in revenue reporting.
  EOT
}

variable "p99_latency_threshold_ms" {
  type        = number
  default     = 2000
  description = <<-EOT
    p99 latency (ms) above which the alert fires. 2000ms is used because
    checkout flows lose users well before that point, and p99 (rather than
    p50) is tracked because the payment gateway is a hard external
    dependency whose tail latency is what actually drives cart abandonment
    and client-side timeouts/retries.
  EOT
}

variable "request_rate_drop_threshold_pct" {
  type        = number
  default     = 50
  description = <<-EOT
    Percentage drop in request rate, compared to the same window one hour
    earlier, above which the alert fires. A drop this large is well outside
    normal hour-to-hour traffic variance and usually signals an upstream
    problem (broken checkout UI, misrouted load balancer) rather than
    organic low traffic.
  EOT
}

# --- USE thresholds (underlying ECS task signals) ---

variable "cpu_utilization_threshold_pct" {
  type        = number
  default     = 80
  description = <<-EOT
    ECS task CPU utilization (%) above which the alert fires. Tasks are
    sized with headroom for bursts; 80% sustained leaves roughly 20% margin
    before autoscaling lag turns into visible latency degradation.
  EOT
}

variable "memory_utilization_threshold_pct" {
  type        = number
  default     = 85
  description = <<-EOT
    ECS task memory utilization (%) above which the alert fires. Memory is
    less elastic than CPU under ECS (no swap), so 85% leaves a safety margin
    before an OOM-kill drops in-flight authorization requests.
  EOT
}

variable "enable_queue_saturation_monitor" {
  type        = bool
  default     = false
  description = "Whether this deployment offloads work (e.g. retries) to a queue worth monitoring for saturation. Off by default since not every deployment of this service has one."
}

variable "queue_saturation_threshold_pct" {
  type        = number
  default     = 75
  description = "Queue saturation (%) above which the alert fires. Only used when enable_queue_saturation_monitor is true."
}

variable "extra_monitors" {
  type = map(object({
    promql_expr  = string
    threshold    = number
    comparison   = string
    severity     = string
    for_duration = optional(string, "5m")
    signal_type  = optional(string, "custom")
    labels       = optional(map(string), {})
  }))
  default     = {}
  description = "Additional monitors merged on top of the RED/USE defaults. Can only add signals: see local.monitors in main.tf for why a default can never be overridden or removed from here."
}
