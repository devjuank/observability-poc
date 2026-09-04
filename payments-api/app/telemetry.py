import logging
import os

from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.metrics.view import ExplicitBucketHistogramAggregation, View
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

SERVICE_NAME = "payments-api"
OTLP_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://alloy:4317")

# OTel's default histogram buckets are sized for millisecond-scale values;
# our duration is recorded in seconds (typical for HTTP handlers), so left
# at the default, p99 latency would be a coarse over-estimate. These match
# the buckets the Prometheus client itself defaults to for this exact case.
_DURATION_SECONDS_BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0)


def _configure() -> None:
    """Wires up tracing, metrics, and logging, all exported via OTLP/gRPC to
    the local Alloy collector. Runs once at import time so every tracer/meter
    obtained below is already bound to a real (not no-op) provider."""
    resource = Resource.create({"service.name": SERVICE_NAME})

    trace_provider = TracerProvider(resource=resource)
    trace_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=OTLP_ENDPOINT, insecure=True)))
    trace.set_tracer_provider(trace_provider)

    metric_reader = PeriodicExportingMetricReader(
        OTLPMetricExporter(endpoint=OTLP_ENDPOINT, insecure=True),
        export_interval_millis=5000,
    )
    duration_view = View(
        instrument_name="http_request_duration_seconds",
        aggregation=ExplicitBucketHistogramAggregation(_DURATION_SECONDS_BUCKETS),
    )
    metrics.set_meter_provider(
        MeterProvider(resource=resource, metric_readers=[metric_reader], views=[duration_view])
    )

    logger_provider = LoggerProvider(resource=resource)
    logger_provider.add_log_record_processor(
        BatchLogRecordProcessor(OTLPLogExporter(endpoint=OTLP_ENDPOINT, insecure=True))
    )
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    # Log records emitted while a span is active are automatically tagged
    # with trace_id/span_id by this handler — that's what correlates a log
    # line in Loki back to a trace in Tempo, with no manual wiring.
    logging.getLogger().addHandler(LoggingHandler(level=logging.INFO, logger_provider=logger_provider))


_configure()

tracer = trace.get_tracer(SERVICE_NAME)
meter = metrics.get_meter(SERVICE_NAME)

# Instrument names match exactly what
# observability-module/modules/service-observability queries by default —
# no collector-side renaming needed. See infra/alloy/config.alloy
# (add_metric_suffixes = false) for the other half of that contract.
http_requests_total = meter.create_counter(
    name="http_requests_total",
    description="Total HTTP requests handled by payments-api.",
    unit="1",
)

http_request_duration_seconds = meter.create_histogram(
    name="http_request_duration_seconds",
    description="HTTP request duration in seconds.",
    unit="s",
)
