output "rule_uid" {
  description = "UID of the created alert rule."
  value       = grafana_rule_group.this.rule[0].uid
}
