# Observability Terraform Module

This is a small, self-contained Terraform module set for managing Grafana
content — alert rules and a dashboard — for HTTP services running on ECS,
observed through a Prometheus/Loki/Tempo stack. It's demonstrated against a
fictional **Payment Authorization Service** (`payments-api`): a synchronous
checkout-flow service that calls out to an external payment gateway to
authorize a charge. The module itself is generic; `payments-api` is just the
example used to exercise it across two environments.

## How to use the Terraform modules

Two modules, two levels of use:

- **`modules/service-observability`** — call this for a service. It wraps
  `grafana-monitor` with RED/USE defaults (see below) and creates the
  service's dashboard. This is the entry point for almost every use case.
- **`modules/grafana-monitor`** — an atomic module, one alert rule per
  instance. Call it directly only for a one-off monitor outside the RED/USE
  baseline — `service-observability` already calls it internally, once per
  signal, via `for_each`.

### Example: a service

```hcl
module "payments_api_observability" {
  source = "git::https://github.com/devjuank/observability-poc.git//observability-module/modules/service-observability"

  service_name = "payments-api"
  environment  = "production"
  folder_uid   = "payments-production" # must already exist in Grafana

  # Optional: override a default threshold for this environment.
  error_rate_threshold_pct = 5

  # Optional: add a monitor beyond the RED/USE baseline. Can't remove or
  # override a default one this way — see DESIGN.md.
  extra_monitors = {
    "gateway-timeout-rate" = {
      promql_expr = "sum(rate(payment_gateway_timeouts_total{service=\"payments-api\"}[5m]))"
      threshold   = 5
      comparison  = "gt"
      severity    = "warning"
    }
  }
}

output "payments_api_dashboard_uid" {
  value = module.payments_api_observability.dashboard_uid
}
```

Two fully runnable root modules built this way, one per environment, live in
[`examples/payments-staging`](./examples/payments-staging) and
[`examples/payments-production`](./examples/payments-production) — copy
either one as a starting point.

### Example: a single ad-hoc alert

For one monitor outside the RED/USE baseline, call `grafana-monitor` directly:

```hcl
module "checkout_queue_backlog" {
  source = "git::https://github.com/devjuank/observability-poc.git//observability-module/modules/grafana-monitor"

  name        = "checkout-queue-backlog"
  promql_expr = "sum(checkout_queue_depth)"
  threshold   = 1000
  comparison  = "gt"
  severity    = "warning"
  folder_uid  = "payments-production"
}
```

## Architecture

```
                 ┌─────────────────────────────┐
                 │  Payment Authorization      │
                 │  Service (ECS task)         │
                 └──────────────┬──────────────┘
                                │ metrics / logs / traces
                                ▼
                 ┌─────────────────────────────┐
                 │  OpenTelemetry Collector    │
                 │  (Grafana Alloy)            │
                 └───────┬───────┬───────┬─────┘
                         │       │       │
                 metrics │  logs │       │ traces
                         ▼       ▼       ▼
                  ┌──────────┐ ┌──────┐ ┌───────┐
                  │Prometheus│ │ Loki │ │ Tempo │
                  └────┬─────┘ └──┬───┘ └───┬───┘
                       └──────────┼─────────┘
                                  ▼
                            ┌───────────┐
                            │  Grafana  │  dashboards + Alerting
                            └─────┬─────┘
                                  │ managed by
                                  ▼
                  ┌────────────────────────────────────┐
                  │  This Terraform module             │
                  │  (grafana-monitor +                │
                  │   service-observability)           │
                  │  → creates dashboard + alert rules │
                  │    on top of the stack above       │
                  └────────────────────────────────────┘
```

Prometheus, Loki, Tempo, and Grafana itself are treated as pre-existing
infrastructure. This module doesn't stand up that stack — it only adds
content (dashboards, alert rules) on top of it. See
[DESIGN.md](./DESIGN.md#extending-to-a-live-environment) for how that maps
to a live environment.

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
itself is not — see [DESIGN.md](./DESIGN.md) for why.

## More

[`DESIGN.md`](./DESIGN.md) covers what's deliberately not configurable (and
why), requirements, running `fmt`/`validate` locally, extending this to a
live environment, and how a future Loki- or Tempo-based monitor would fit
the same pattern.
