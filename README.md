# observability-poc

A Payment Authorization Service — a synchronous checkout API that calls out
to an external payment gateway — used as the running example for a small
observability stack: Grafana + Prometheus + Loki + Tempo + Grafana Alloy,
with a Terraform module managing the dashboard and alert rules on top of it.

- [`observability-module/`](./observability-module/) — the Terraform module
  set (the main piece of this repo): a generic `grafana-monitor` alert-rule
  module wrapped by a `service-observability` module that enforces RED/USE
  defaults, demonstrated for `payments-api` across staging and production.
  See its README for the architecture, the RED/USE framework, and the
  governance reasoning behind what is and isn't configurable.
- [`infra/`](./infra/) — local observability platform config (Grafana,
  Prometheus, Loki, Tempo, Alloy), owned independently of the service code.
- [`payments-api/`](./payments-api/) — the demo service itself: a minimal
  FastAPI app instrumented with OpenTelemetry (metrics, traces, structured
  logs), plus a traffic simulation script.
- `docker-compose.yml` — wires `infra/` and `payments-api/` together for a
  local, disposable demo of the whole thing running end to end.

## Running the local demo

This exercises the Terraform module against a real, local Grafana instance:
bring the stack up, apply `examples/payments-production`, generate traffic,
then force an error burst and watch the `payments-api-error-rate` alert
transition to **Firing**.

### 1. Bring up the stack

```bash
docker compose up -d --build
```

This starts Prometheus, Loki, Tempo, Alloy, Grafana (with the three
datasources auto-provisioned — see `infra/grafana/provisioning/`), and
`payments-api` itself. Grafana is reachable at `http://localhost:3000`
(default login: `admin` / `admin`, set in `docker-compose.yml` — change it
before using this compose file for anything beyond a local demo).

### 2. Create a Grafana service account token

The Terraform `grafana` provider needs its own credential, separate from
your login — a service account token, exactly as it would in a real
environment:

```bash
SA_ID=$(curl -s -u admin:admin -X POST http://localhost:3000/api/serviceaccounts \
  -H 'Content-Type: application/json' \
  -d '{"name":"terraform","role":"Admin"}' | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')

curl -s -u admin:admin -X POST "http://localhost:3000/api/serviceaccounts/$SA_ID/tokens" \
  -H 'Content-Type: application/json' \
  -d '{"name":"terraform-token"}'
```

Copy the `key` from the response — it's shown once. (Equivalently: Grafana
UI → Administration → Service accounts → Add service account.)

### 3. Create the target folder

`folder_uid` is an input to the module, not something it creates (see
`observability-module/README.md`'s design decisions) — in a real org this
folder is already there, managed by the platform team. Here, create it once:

```bash
curl -s -u admin:admin -X POST http://localhost:3000/api/folders \
  -H 'Content-Type: application/json' \
  -d '{"uid":"payments-production","title":"payments-production"}'
```

### 4. Apply the Terraform example against it

```bash
export TF_VAR_grafana_url="http://localhost:3000"
export TF_VAR_grafana_auth="<service-account-token-from-step-2>"

cd observability-module/examples/payments-production
terraform init
terraform apply
```

This creates the `payments-api (production)` dashboard and all 5 RED/USE
alert rules directly in your local Grafana — check Dashboards and Alerting
in the UI.

### 5. Generate traffic, then trigger the alert

From the repo root:

```bash
# steady normal traffic
python3 payments-api/scripts/simulate_traffic.py

# in another terminal, once you want to see the alert fire:
python3 payments-api/scripts/simulate_traffic.py --error-burst 90
```

`--error-burst 90` forces every `/authorize` call to fail (HTTP 502) for the
first 90 seconds, well above the production `error_rate_threshold_pct` of
2%. This isn't instant: `payments-api-error-rate` computes error rate over a
trailing 5-minute PromQL window and itself has a 5-minute `for` duration
(both by design — see the RED/USE table in `observability-module/README.md`
for why), so expect roughly **5–10 minutes** from the start of the burst
until Grafana Alerting shows it as **Firing**, not immediately. Watch it at
Alerting → payments-production in Grafana, or:

```bash
curl -s -u admin:admin http://localhost:3000/api/prometheus/grafana/api/v1/rules \
  | python3 -c 'import json,sys; [print(r["name"], r["state"]) for g in json.load(sys.stdin)["data"]["groups"] for r in g["rules"]]'
```

### Known limitation of this local demo

`cpu-utilization` and `memory-utilization` query CloudWatch-exporter-style
metrics (`aws_ecs_service_*`) that only exist against a real ECS task —
there's no ECS here, so those two will sit at **No Data** locally, by
design, not as a bug. `request-rate-drop` compares current traffic to
traffic from an hour ago (`offset 1h`); it will also read **No Data** until
the demo has been running for over an hour, since that history doesn't
exist yet. `error-rate` — the one this walkthrough exercises — doesn't have
either problem.

### Tear down

```bash
docker compose down -v
```
