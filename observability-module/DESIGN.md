# Design Decisions and Operational Notes

See [`README.md`](./README.md) for what this module does, the architecture,
and how to call it. This file covers the reasoning behind what's
configurable and what isn't, how to validate the code locally, and how it
extends beyond this code sample.

## Design decisions: what's NOT configurable, and why

A few things are deliberately locked down, not exposed as variables. This is
a governance choice, not an oversight:

- **Severity is a closed enum (`critical` / `warning` / `info`).**
  `grafana-monitor` validates this with a `validation` block. A fixed,
  small vocabulary is what lets alert routing, dashboards, and paging
  policies stay consistent platform-wide — if any string were accepted,
  every consumer of `severity` (routing rules, on-call tooling, reporting)
  would need to defensively handle arbitrary values.

- **Comparison operators are a closed enum (`gt` / `lt`).**
  This mirrors what Grafana's classic condition evaluator supports for a
  simple last-value threshold check, and keeps every alert rule this module
  produces auditable at a glance — no bespoke per-rule logic hidden behind a
  free-form operator.

- **This module never creates a `grafana_contact_point` or
  `grafana_notification_policy`.** Alert routing (which team gets paged,
  through which channel, on what schedule) is a platform-level concern
  owned centrally, independent of any one service's Terraform. This
  module's only contract with that routing is the `severity` label it
  attaches to every rule, which an existing, externally-managed
  notification policy matches on. A service team can't accidentally
  (re)define where their pages go; a platform team can change routing
  without touching every service's code.

- **The RED/USE baseline monitors and the dashboard are not optional.**
  `service-observability` builds `local.default_monitors` from the
  threshold variables, then computes
  `merge(var.extra_monitors, local.default_monitors)` — with
  `default_monitors` merged *last*, so it always wins on a key collision.
  A caller can add monitors through `extra_monitors`; it cannot override or
  silently drop a baseline one by reusing its key. The same applies to the
  dashboard: its panel layout is fixed in `main.tf`, and it's created
  unconditionally. A service can extend the minimum standard; it can't opt
  out of it.

## Requirements

- Terraform >= 1.5
- No live Grafana instance is required to work on or validate this code —
  `terraform validate` only checks configuration syntax and types against
  the provider's schema, not against a running Grafana.

## Running locally

From the `observability-module/` directory:

```bash
# Format check across every module and example
terraform fmt -check -recursive -diff

# Validate each module and example independently
for dir in modules/grafana-monitor modules/service-observability \
           examples/payments-staging examples/payments-production; do
  (cd "$dir" && terraform init -backend=false -input=false && terraform validate)
done
```

This is exactly what `.github/workflows/terraform-ci.yml` runs on every pull
request that touches this folder.

## Extending to a live environment

In a real setting, Grafana/Prometheus/Loki/Tempo already exist as shared
platform infrastructure — a service team doesn't stand that up, they just
add their dashboard and alerts on top of it, which is exactly the boundary
this module is built around (`folder_uid` and `datasource_uid` are inputs,
not resources this module creates).

This repo includes exactly that stack, running locally via `docker-compose.yml`
at the repo root (`infra/` for the platform pieces, `payments-api/` for an
instrumented demo service) — see the root
**[README's "Running the local demo"](../README.md#running-the-local-demo)**
section for the full walkthrough: bring the stack up, create a service
account token, `terraform apply` this module against it, then force an error
burst and watch `payments-api-error-rate` actually transition to **Firing**
in Grafana Alerting. That flow has been run end to end against this module.

## Future extension: Loki & Tempo

Both would extend the same pattern already established by
`grafana-monitor`, rather than needing a new one:

- **A LogQL-based monitor** — e.g. "rate of `ERROR`-level structured logs
  containing `gateway_timeout`" — would be just another call to
  `grafana-monitor`, with `promql_expr` holding a LogQL query instead of
  PromQL and `datasource_uid` pointing at the Loki datasource. The module's
  query language is opaque to it by design (it's a caller-supplied string),
  so no code change would be required, only a new entry in
  `service-observability`'s monitor map.
- **A Tempo trace panel** — since traces aren't naturally a single
  threshold to alert on, this would extend the dashboard rather than the
  alerting side: one more entry in `service-observability`'s
  `dashboard_panel_defs`, with a TraceQL query and the Tempo datasource
  UID, following the exact same shape as the existing panels.
