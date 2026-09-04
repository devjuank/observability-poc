#!/usr/bin/env python3
"""Traffic generator for the payments-api local demo.

Stdlib-only on purpose, so it can be run straight from the host without
installing payments-api's own dependencies.

Examples:
    python3 scripts/simulate_traffic.py
        Steady normal traffic until Ctrl+C.

    python3 scripts/simulate_traffic.py --error-burst 90
        Forces every /authorize call to fail (HTTP 502) for the first 90s,
        then reverts to normal traffic. See the root README's "Running the
        local demo" section for how long it then takes for the
        payments-api-error-rate alert to reach "Firing" — it's driven by the
        alert rule's 5-minute PromQL window plus its own 5-minute "for"
        duration, not instant.
"""

import argparse
import json
import random
import sys
import time
import urllib.error
import urllib.request

DEFAULT_URL = "http://localhost:8000"


def send_authorize(base_url: str, force_error: bool) -> int:
    payload = json.dumps(
        {
            "amount_cents": random.randint(500, 20000),
            "card_last4": f"{random.randint(0, 9999):04d}",
            "force_error": force_error,
        }
    ).encode()

    request = urllib.request.Request(
        f"{base_url}/authorize",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code
    except urllib.error.URLError as exc:
        print(f"request failed: {exc}", file=sys.stderr)
        return 0


def run(base_url: str, rps: float, duration: int, error_burst: int) -> None:
    interval = 1.0 / rps
    start = time.monotonic()
    count = 0

    while duration <= 0 or (time.monotonic() - start) < duration:
        elapsed = time.monotonic() - start
        force_error = elapsed < error_burst

        status = send_authorize(base_url, force_error)
        count += 1

        marker = "ERROR-BURST" if force_error else "normal"
        print(f"[{count}] {marker} -> HTTP {status}")

        time.sleep(interval)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default=DEFAULT_URL, help=f"Base URL of payments-api (default: {DEFAULT_URL})")
    parser.add_argument("--rps", type=float, default=2.0, help="Requests per second (default: 2.0)")
    parser.add_argument(
        "--duration",
        type=int,
        default=0,
        help="Total run duration in seconds (default: 0, run until Ctrl+C)",
    )
    parser.add_argument(
        "--error-burst",
        type=int,
        default=0,
        metavar="SECONDS",
        help="Force every /authorize call to fail for this many seconds at the start of the "
        "run, pushing error rate well above the module's alert thresholds. 0 disables (default).",
    )
    args = parser.parse_args()

    print(
        f"Sending traffic to {args.url} at ~{args.rps} req/s"
        + (f", forcing errors for the first {args.error_burst}s" if args.error_burst else "")
    )

    try:
        run(args.url, args.rps, args.duration, args.error_burst)
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()
