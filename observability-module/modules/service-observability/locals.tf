# The RED/USE base signals below are the non-negotiable minimum for any HTTP
# service running on ECS in this org — see the module README section
# "Design decisions: what's NOT configurable, and why" for the reasoning.
# Thresholds are tunable per environment via the variables above; the set of
# signals itself is not.
locals {
  red_monitors = {
    "error-rate" = {
      promql_expr  = "100 * (sum(rate(http_requests_total{service=\"${var.service_name}\", status=~\"5..\"}[5m])) / sum(rate(http_requests_total{service=\"${var.service_name}\"}[5m])))"
      threshold    = var.error_rate_threshold_pct
      comparison   = "gt"
      severity     = "critical"
      for_duration = "5m"
      signal_type  = "RED"
      labels       = {}
    }
    "p99-latency" = {
      promql_expr  = "1000 * histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{service=\"${var.service_name}\"}[5m])) by (le))"
      threshold    = var.p99_latency_threshold_ms
      comparison   = "gt"
      severity     = "warning"
      for_duration = "5m"
      signal_type  = "RED"
      labels       = {}
    }
    "request-rate-drop" = {
      promql_expr  = "100 * (1 - (sum(rate(http_requests_total{service=\"${var.service_name}\"}[5m])) / sum(rate(http_requests_total{service=\"${var.service_name}\"}[5m] offset 1h))))"
      threshold    = var.request_rate_drop_threshold_pct
      comparison   = "gt"
      severity     = "critical"
      for_duration = "10m"
      signal_type  = "RED"
      labels       = {}
    }
  }

  use_monitors = {
    "cpu-utilization" = {
      promql_expr  = "avg(aws_ecs_service_cpuutilization_average{service_name=\"${var.service_name}\"})"
      threshold    = var.cpu_utilization_threshold_pct
      comparison   = "gt"
      severity     = "warning"
      for_duration = "10m"
      signal_type  = "USE"
      labels       = {}
    }
    "memory-utilization" = {
      promql_expr  = "avg(aws_ecs_service_memoryutilization_average{service_name=\"${var.service_name}\"})"
      threshold    = var.memory_utilization_threshold_pct
      comparison   = "gt"
      severity     = "warning"
      for_duration = "10m"
      signal_type  = "USE"
      labels       = {}
    }
  }

  # Queue saturation is the one USE signal that doesn't apply to every
  # deployment of this service, so it's opt-in rather than always-on.
  queue_monitor = var.enable_queue_saturation_monitor ? {
    "queue-saturation" = {
      promql_expr  = "avg(aws_sqs_approximate_number_of_messages_visible{queue_name=\"${var.service_name}-retry-queue\"})"
      threshold    = var.queue_saturation_threshold_pct
      comparison   = "gt"
      severity     = "warning"
      for_duration = "5m"
      signal_type  = "USE"
      labels       = {}
    }
  } : {}

  default_monitors = merge(local.red_monitors, local.use_monitors, local.queue_monitor)

  # default_monitors is merged LAST: on a key collision with var.extra_monitors
  # the default always wins, so a caller can add monitors but can never
  # override or silently disable one of the RED/USE base signals.
  monitors = merge(var.extra_monitors, local.default_monitors)
}
