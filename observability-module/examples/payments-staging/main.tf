# Staging carries lower-stakes, often synthetic traffic and is more tolerant
# of transient blips — thresholds are relaxed relative to production so the
# on-call rotation isn't paged for staging-only flakiness. Everything else
# (the RED/USE signal set, the dashboard) is identical to production: this is
# the same module, reused with different inputs.
module "payments_api_observability" {
  source = "../../modules/service-observability"

  service_name = "payments-api"
  environment  = "staging"
  folder_uid   = var.folder_uid

  error_rate_threshold_pct = 5
  p99_latency_threshold_ms = 3000
}
