output "dashboard_uid" {
  description = "UID of the service dashboard."
  value       = grafana_dashboard.this.uid
}

output "rule_uids" {
  description = "Map of monitor key to the UID of its alert rule."
  value       = { for key, monitor in module.monitors : key => monitor.rule_uid }
}
