# Production keeps the module's strict RED/USE defaults as-is (error rate
# > 2%, p99 > 2000ms, ...) — no threshold overrides needed. Compare with
# ../payments-staging/main.tf: same module, same signal set, only the
# environment and threshold inputs differ.
module "payments_api_observability" {
  source = "../../modules/service-observability"

  service_name = "payments-api"
  environment  = "production"
  folder_uid   = var.folder_uid
}
