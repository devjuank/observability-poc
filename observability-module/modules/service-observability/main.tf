module "monitors" {
  source   = "../grafana-monitor"
  for_each = local.monitors

  name           = "${var.service_name}-${each.key}"
  promql_expr    = each.value.promql_expr
  threshold      = each.value.threshold
  comparison     = each.value.comparison
  severity       = each.value.severity
  folder_uid     = var.folder_uid
  for_duration   = each.value.for_duration
  datasource_uid = var.datasource_uid

  labels = merge(
    {
      service     = var.service_name
      environment = var.environment
      signal_type = each.value.signal_type
    },
    each.value.labels
  )
}

# Dashboard panel layout is fixed on purpose — see the module README section
# "Design decisions: what's NOT configurable, and why". Only the underlying
# queries vary, via var.service_name.
locals {
  dashboard_panel_defs = [
    {
      title = "Request rate"
      unit  = "reqps"
      expr  = "sum(rate(http_requests_total{service=\"${var.service_name}\"}[5m]))"
    },
    {
      title = "Error rate (%)"
      unit  = "percent"
      expr  = "100 * (sum(rate(http_requests_total{service=\"${var.service_name}\", status=~\"5..\"}[5m])) / sum(rate(http_requests_total{service=\"${var.service_name}\"}[5m])))"
    },
    {
      title = "p99 latency (ms)"
      unit  = "ms"
      expr  = "1000 * histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{service=\"${var.service_name}\"}[5m])) by (le))"
    },
    {
      title = "ECS CPU utilization (%)"
      unit  = "percent"
      expr  = "avg(aws_ecs_service_cpuutilization_average{service_name=\"${var.service_name}\"})"
    },
    {
      title = "ECS memory utilization (%)"
      unit  = "percent"
      expr  = "avg(aws_ecs_service_memoryutilization_average{service_name=\"${var.service_name}\"})"
    },
  ]

  dashboard_panels = [
    for idx, panel in local.dashboard_panel_defs : {
      id    = idx + 1
      title = panel.title
      type  = "timeseries"
      gridPos = {
        h = 8
        w = 12
        x = (idx % 2) * 12
        y = floor(idx / 2) * 8
      }
      fieldConfig = {
        defaults = {
          unit = panel.unit
        }
      }
      targets = [
        {
          refId      = "A"
          expr       = panel.expr
          datasource = { type = "prometheus", uid = var.datasource_uid }
        }
      ]
    }
  ]

  dashboard_json = jsonencode({
    title         = "${var.service_name} (${var.environment})"
    uid           = "${var.service_name}-${var.environment}"
    tags          = ["terraform", var.service_name, var.environment]
    schemaVersion = 39
    time = {
      from = "now-6h"
      to   = "now"
    }
    panels = local.dashboard_panels
  })
}

resource "grafana_dashboard" "this" {
  folder      = var.folder_uid
  config_json = local.dashboard_json
  overwrite   = true
}
