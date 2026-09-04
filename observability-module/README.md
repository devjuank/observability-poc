# Observability Terraform Module

This is a small, self-contained Terraform module set for managing Grafana
content — alert rules and a dashboard — for HTTP services running on ECS,
observed through a Prometheus/Loki/Tempo stack. It's demonstrated against a
fictional **Payment Authorization Service** (`payments-api`): a synchronous
checkout-flow service that calls out to an external payment gateway to
authorize a charge. The module itself is generic; `payments-api` is just the
example used to exercise it across two environments.

## Architecture

```
                 ┌───────────────────────────┐
                 │  Payment Authorization      │
                 │  Service (ECS task)         │
                 └─────────────┬───────────────┘
                                │ metrics / logs / traces
                                ▼
                 ┌───────────────────────────┐
                 │  OpenTelemetry Collector    │
                 │  (Grafana Alloy)            │
                 └──────┬───────┬───────┬──────┘
                         │       │       │
                 metrics │  logs │       │ traces
                         ▼       ▼       ▼
                  ┌──────────┐ ┌──────┐ ┌───────┐
                  │Prometheus│ │ Loki │ │ Tempo │
                  └────┬─────┘ └──┬───┘ └───┬───┘
                       └──────────┼─────────┘
                                  ▼
                            ┌───────────┐
                            │  Grafana   │  dashboards + Alerting
                            └─────┬─────┘
                                  │ managed by
                                  ▼
                  ┌────────────────────────────────┐
                  │  This Terraform module           │
                  │  (grafana-monitor +               │
                  │   service-observability)          │
                  │  → creates dashboard + alert rules │
                  │    on top of the stack above       │
                  └────────────────────────────────┘
```

Prometheus, Loki, Tempo, and Grafana itself are treated as pre-existing
infrastructure. This module doesn't stand up that stack — it only adds
content (dashboards, alert rules) on top of it. See
["Extending to a live environment"](#extending-to-a-live-environment) below.

## RED (service) and USE (infra) signals

`modules/service-observability` wraps `modules/grafana-monitor` and always
creates one baseline set of monitors, following two complementary frameworks:

- **RED** (Rate, Errors, Duration) — for the service itself, since it's a
  synchronous request/response API.
- **USE** (Utilization, Saturation, Errors) — for the ECS task the service
  runs on, since the service can be healthy while its infrastructure is
  quietly running out of headroom.

| Signal | Framework | Default threshold | Why it matters |
|---|---|---|---|
| Error rate | RED — Errors | > 2% for 5m | Normal gateway/client error noise sits well under 1% on this path; 2% is high enough to avoid paging on noise but low enough to catch a real outage before it shows up in revenue reporting. |
| p99 latency | RED — Duration | > 2000ms for 5m | Checkout flows lose users well before that point. p99, not p50, is tracked because the payment gateway is a hard external dependency, and tail latency is what drives cart abandonment and client-side timeouts/retries. |
| Request rate drop | RED — Rate | > 50% drop vs. 1h earlier for 10m | A drop this large is well outside normal hour-to-hour traffic variance and usually means an upstream problem (broken checkout UI, misrouted load balancer), not organic low traffic. |
| ECS CPU utilization | USE — Utilization | > 80% for 10m | Tasks are sized with headroom for bursts; 80% sustained leaves roughly 20% margin before autoscaling lag turns into visible latency degradation. |
| ECS memory utilization | USE — Utilization | > 85% for 10m | Memory is less elastic than CPU under ECS (no swap); 85% leaves a safety margin before an OOM-kill drops in-flight authorization requests. |
| Queue saturation *(optional)* | USE — Saturation | > 75% for 5m | Only relevant if a deployment offloads retries to a queue; off by default via `enable_queue_saturation_monitor` since not every deployment has one. |

Thresholds are tunable per environment (see `examples/`); the signal set
itself is not — see below.

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

From this directory:

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
