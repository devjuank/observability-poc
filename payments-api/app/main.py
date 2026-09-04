import asyncio
import logging
import random
import time

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel

from .telemetry import http_request_duration_seconds, http_requests_total, tracer

SERVICE_NAME = "payments-api"

# ~0.5% simulated gateway declines under normal conditions — enough to look
# like a real external dependency without ever tripping the module's 2%
# error-rate alert on its own. scripts/simulate_traffic.py --error-burst is
# what pushes error rate past that threshold on demand.
BASELINE_ERROR_RATE = 0.005

logger = logging.getLogger(SERVICE_NAME)

app = FastAPI(title="Payment Authorization Service")


@app.middleware("http")
async def record_http_metrics(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    duration = time.perf_counter() - start

    attributes = {
        "service": SERVICE_NAME,
        "status": str(response.status_code),
        "route": request.url.path,
    }
    http_requests_total.add(1, attributes)
    http_request_duration_seconds.record(duration, attributes)
    return response


class AuthorizeRequest(BaseModel):
    amount_cents: int
    card_last4: str
    force_error: bool = False


class AuthorizeResponse(BaseModel):
    authorized: bool
    authorization_id: str


async def call_payment_gateway(force_error: bool) -> None:
    """Simulates a synchronous call to an external payment gateway: adds
    realistic latency and can decline the charge."""
    with tracer.start_as_current_span("payment_gateway.charge") as span:
        latency_s = random.uniform(0.05, 0.25)
        await asyncio.sleep(latency_s)
        span.set_attribute("gateway.latency_ms", latency_s * 1000)

        if force_error or random.random() < BASELINE_ERROR_RATE:
            span.set_attribute("gateway.result", "declined")
            raise RuntimeError("payment gateway declined the charge")

        span.set_attribute("gateway.result", "approved")


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/authorize", response_model=AuthorizeResponse)
async def authorize(payload: AuthorizeRequest):
    with tracer.start_as_current_span("authorize") as span:
        span.set_attribute("payment.amount_cents", payload.amount_cents)

        try:
            await call_payment_gateway(payload.force_error)
        except RuntimeError as exc:
            logger.error("authorization failed for card ending %s: %s", payload.card_last4, exc)
            raise HTTPException(status_code=502, detail="payment gateway declined the charge") from exc

        logger.info("authorization approved for card ending %s", payload.card_last4)
        return AuthorizeResponse(authorized=True, authorization_id=f"auth_{random.randint(100000, 999999)}")
