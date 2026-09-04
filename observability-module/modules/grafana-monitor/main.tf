# Severity -> notification routing is intentionally NOT configurable here.
#
# This module never creates grafana_contact_point or grafana_notification_policy
# resources. Contact points (PagerDuty, Slack, email, ...) and the routing tree
# that maps label matchers to them are a platform-level concern owned centrally,
# so that on-call routing can be changed without touching every service's
# Terraform. This module's only contract with that routing is the `severity`
# label below, which the platform's existing notification policy matches on.
locals {
  mandatory_labels = {
    severity = var.severity
  }

  labels = merge(local.mandatory_labels, var.labels)
}

resource "grafana_rule_group" "this" {
  name             = var.name
  folder_uid       = var.folder_uid
  interval_seconds = var.evaluation_interval_seconds

  rule {
    name           = var.name
    for            = var.for_duration
    condition      = "threshold"
    no_data_state  = "NoData"
    exec_err_state = "Alerting"
    labels         = local.labels

    annotations = {
      summary = "${var.name} crossed threshold (${var.comparison} ${var.threshold})"
    }

    # Stage A: run the caller-supplied PromQL query.
    data {
      ref_id         = "query"
      query_type     = ""
      datasource_uid = var.datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        refId         = "query"
        expr          = var.promql_expr
        intervalMs    = 1000
        maxDataPoints = 43200
      })
    }

    # Stage B: classic condition comparing the last value of stage A against
    # the configured threshold. This is the Grafana-native "expression" that
    # drives alert state.
    data {
      ref_id         = "threshold"
      query_type     = ""
      datasource_uid = "-100"

      relative_time_range {
        from = 0
        to   = 0
      }

      model = jsonencode({
        refId = "threshold"
        type  = "classic_conditions"
        datasource = {
          type = "__expr__"
          uid  = "-100"
        }
        conditions = [
          {
            type = "query"
            evaluator = {
              type   = var.comparison
              params = [var.threshold]
            }
            operator = {
              type = "and"
            }
            query = {
              params = ["query"]
            }
            reducer = {
              type   = "last"
              params = []
            }
          }
        ]
      })
    }
  }
}
