"""Deadline-enforced entry point for the public XAUUSD downloader.

The canonical downloader remains responsible for parsing, quality gates and
reproducible diagnostics. This wrapper replaces only the slot scheduler and
HTTP fetch routine so a cold/stalled Dukascopy run cannot consume the entire
GitHub Actions job before MT5 compilation and testing.
"""

from __future__ import annotations

import importlib.util
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("download_public_xau_m1.py")
spec = importlib.util.spec_from_file_location("xau_public_downloader", MODULE_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Cannot load canonical downloader: {MODULE_PATH}")

mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def fetch_hour_bounded(day, hour, deadline: float):
    """Fetch one hour while respecting the shared monotonic wall-clock budget."""
    url = mod.hour_url(day, hour)
    cache_path = mod.cache_path_for(day, hour)
    if cache_path is not None and cache_path.exists() and cache_path.stat().st_size > 0:
        try:
            return day, hour, cache_path.read_bytes(), "cached", url
        except Exception:
            pass

    last_error = ""
    for attempt in range(1, mod.FETCH_RETRIES + 1):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return day, hour, None, "deadline_exceeded", url

        timeout = max(1.0, min(float(mod.FETCH_TIMEOUT_SECONDS), remaining))
        try:
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": "Mozilla/5.0 GitHubActions-XAU-Public-Backtest/5.0",
                    "Accept": "*/*",
                    "Connection": "close",
                },
            )
            with urllib.request.urlopen(req, timeout=timeout) as response:
                data = response.read()
            if data:
                if cache_path is not None:
                    cache_path.parent.mkdir(parents=True, exist_ok=True)
                    tmp = cache_path.with_suffix(cache_path.suffix + ".tmp")
                    tmp.write_bytes(data)
                    tmp.replace(cache_path)
                return day, hour, data, "downloaded", url
            last_error = "empty response"
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return day, hour, None, "missing_404", url
            last_error = f"HTTP {exc.code}"
        except Exception as exc:
            last_error = str(exc)

        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return day, hour, None, "deadline_exceeded", url
        time.sleep(min(5.0, 0.5 + attempt, remaining))

    return day, hour, None, f"failed:{last_error}", url


def fetch_and_process_slots_bounded(slots, deadline_epoch: float, bars):
    """Process bounded worker-size batches and stop within one request timeout."""
    # Convert the canonical wall-clock deadline once. monotonic() is resilient
    # to runner clock adjustments during a long download.
    remaining_budget = max(0.0, deadline_epoch - time.time())
    deadline = time.monotonic() + remaining_budget

    pending = list(slots)
    total_ticks = 0
    successful_hours = 0
    failed_hours = 0
    empty_market_hours = 0
    missing_404 = 0
    days_with_ticks = set()

    for round_no in range(1, mod.FETCH_RETRY_ROUNDS + 1):
        if not pending or time.monotonic() >= deadline:
            break

        retry = []
        cursor = 0
        print(
            f"FETCH_ROUND={round_no} pending={len(pending)} "
            f"workers={mod.FETCH_WORKERS} bounded_batches=true"
        )

        while cursor < len(pending) and time.monotonic() < deadline:
            batch = pending[cursor : cursor + mod.FETCH_WORKERS]
            cursor += len(batch)

            with ThreadPoolExecutor(max_workers=mod.FETCH_WORKERS) as pool:
                future_map = {
                    pool.submit(fetch_hour_bounded, day, hour, deadline): (day, hour)
                    for day, hour in batch
                }
                for future in as_completed(future_map):
                    day, hour = future_map[future]
                    try:
                        d, h, raw, fetch_status, url = future.result()
                    except Exception as exc:
                        d, h = day, hour
                        raw, fetch_status, url = None, f"failed:{exc}", mod.hour_url(day, hour)

                    mod.fetch_attempt_status_counts[fetch_status.split(":", 1)[0]] += 1

                    if raw is not None:
                        payload_status, ticks = mod.process_hour(d, h, raw, bars)
                        if payload_status == "ok":
                            total_ticks += ticks
                            successful_hours += 1
                            days_with_ticks.add(d)
                        elif payload_status == "empty_market":
                            empty_market_hours += 1
                        else:
                            retry.append((d, h))
                        continue

                    if fetch_status == "missing_404":
                        missing_404 += 1
                        mod.missing_downloads.append(url)
                    elif fetch_status == "deadline_exceeded":
                        retry.append((d, h))
                    else:
                        retry.append((d, h))

        # Slots not submitted because the deadline expired remain pending and
        # are reported explicitly instead of silently disappearing.
        retry.extend(pending[cursor:])
        pending = retry

    deadline_hit = bool(pending) and time.monotonic() >= deadline
    reason = "deadline_exceeded" if deadline_hit else "retry_rounds_exhausted"
    for day, hour in pending:
        failed_hours += 1
        mod.failed_downloads.append(f"{mod.hour_url(day, hour)} | {reason}")

    print(f"PUBLIC_HISTORY_DEADLINE_HIT={str(deadline_hit).lower()}")
    print(f"PUBLIC_HISTORY_UNFINISHED_SLOTS={len(pending)}")
    return (
        total_ticks,
        successful_hours,
        failed_hours,
        empty_market_hours,
        missing_404,
        days_with_ticks,
    )


mod.fetch_and_process_slots = fetch_and_process_slots_bounded
raise SystemExit(mod.main())
