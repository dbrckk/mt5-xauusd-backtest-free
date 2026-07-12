"""Deadline-enforced and cache-progressive public XAUUSD downloader.

The canonical downloader remains responsible for BI5 parsing, dataset quality
checks and deterministic diagnostics. This wrapper changes only scheduling and
HTTP acquisition so each hosted run:

* processes every restored cache entry before network work;
* spends network time on missing hours instead of repeatedly blocking on the
  first unavailable chronological batch;
* performs one bounded request per slot and retry round;
* rotates the missing-slot order between GitHub run attempts;
* persists every successfully downloaded raw BI5 hour for later runs.
"""

from __future__ import annotations

import importlib.util
import os
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


def cache_has_payload(day, hour) -> bool:
    path = mod.cache_path_for(day, hour)
    try:
        return path is not None and path.exists() and path.stat().st_size > 0
    except OSError:
        return False


def read_cached_hour(day, hour):
    url = mod.hour_url(day, hour)
    path = mod.cache_path_for(day, hour)
    if path is None:
        return day, hour, None, "cache_disabled", url
    try:
        data = path.read_bytes()
        if data:
            return day, hour, data, "cached", url
    except OSError as exc:
        return day, hour, None, f"cache_read_failed:{exc}", url
    return day, hour, None, "cache_empty", url


def fetch_hour_once(day, hour, deadline: float):
    """Fetch one missing hour once, bounded by the shared monotonic deadline."""
    url = mod.hour_url(day, hour)
    cache_path = mod.cache_path_for(day, hour)

    if cache_has_payload(day, hour):
        return read_cached_hour(day, hour)

    remaining = deadline - time.monotonic()
    if remaining <= 0:
        return day, hour, None, "deadline_exceeded", url

    timeout = max(1.0, min(float(mod.FETCH_TIMEOUT_SECONDS), remaining))
    try:
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": "Mozilla/5.0 GitHubActions-XAU-Public-Backtest/6.0",
                "Accept": "*/*",
                "Connection": "close",
            },
        )
        with urllib.request.urlopen(req, timeout=timeout) as response:
            data = response.read()
        if not data:
            return day, hour, None, "empty_response", url

        if cache_path is not None:
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            tmp = cache_path.with_suffix(cache_path.suffix + ".tmp")
            tmp.write_bytes(data)
            tmp.replace(cache_path)
        return day, hour, data, "downloaded", url
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return day, hour, None, "missing_404", url
        return day, hour, None, f"http_error:{exc.code}", url
    except urllib.error.URLError as exc:
        return day, hour, None, f"url_error:{exc.reason}", url
    except TimeoutError:
        return day, hour, None, "timeout", url
    except Exception as exc:
        return day, hour, None, f"failed:{type(exc).__name__}:{exc}", url


def rotated(slots, round_no: int):
    """Rotate missing work deterministically so reruns do not repeat one prefix."""
    items = list(slots)
    if not items:
        return items
    try:
        run_attempt = max(1, int(os.environ.get("GITHUB_RUN_ATTEMPT", "1")))
    except ValueError:
        run_attempt = 1
    offset = ((run_attempt - 1) * 977 + (round_no - 1) * 503) % len(items)
    return items[offset:] + items[:offset]


def record_payload(day, hour, raw, fetch_status, url, bars, days_with_ticks):
    """Process one payload and return (ticks, successful, empty, retry, missing)."""
    mod.fetch_attempt_status_counts[fetch_status.split(":", 1)[0]] += 1
    if raw is not None:
        payload_status, ticks = mod.process_hour(day, hour, raw, bars)
        if payload_status == "ok":
            days_with_ticks.add(day)
            return ticks, 1, 0, False, 0
        if payload_status == "empty_market":
            return 0, 0, 1, False, 0
        return 0, 0, 0, True, 0

    if fetch_status == "missing_404":
        mod.missing_downloads.append(url)
        return 0, 0, 0, False, 1
    return 0, 0, 0, True, 0


def fetch_and_process_slots_bounded(slots, deadline_epoch: float, bars):
    """Process restored coverage first, then use the budget only on missing slots."""
    remaining_budget = max(0.0, deadline_epoch - time.time())
    deadline = time.monotonic() + remaining_budget

    total_ticks = 0
    successful_hours = 0
    empty_market_hours = 0
    missing_404 = 0
    days_with_ticks = set()

    cached_slots = []
    missing_slots = []
    for day, hour in slots:
        (cached_slots if cache_has_payload(day, hour) else missing_slots).append((day, hour))

    print(f"PUBLIC_HISTORY_CACHE_SLOTS_INITIAL={len(cached_slots)}")
    print(f"PUBLIC_HISTORY_MISSING_SLOTS_INITIAL={len(missing_slots)}")

    corrupt_or_unreadable = []
    for day, hour in cached_slots:
        d, h, raw, status, url = read_cached_hour(day, hour)
        ticks, ok, empty, retry, missing = record_payload(
            d, h, raw, status, url, bars, days_with_ticks
        )
        total_ticks += ticks
        successful_hours += ok
        empty_market_hours += empty
        missing_404 += missing
        if retry:
            corrupt_or_unreadable.append((day, hour))

    pending = corrupt_or_unreadable + missing_slots
    downloaded_this_run = 0

    for round_no in range(1, mod.FETCH_RETRY_ROUNDS + 1):
        if not pending or time.monotonic() >= deadline:
            break

        work = rotated(pending, round_no)
        retry = []
        print(
            f"FETCH_ROUND={round_no} pending={len(work)} "
            f"workers={mod.FETCH_WORKERS} one_attempt_per_slot=true"
        )

        with ThreadPoolExecutor(max_workers=mod.FETCH_WORKERS) as pool:
            future_map = {
                pool.submit(fetch_hour_once, day, hour, deadline): (day, hour)
                for day, hour in work
            }
            for future in as_completed(future_map):
                day, hour = future_map[future]
                try:
                    d, h, raw, status, url = future.result()
                except Exception as exc:
                    d, h = day, hour
                    raw, status, url = None, f"failed:{type(exc).__name__}:{exc}", mod.hour_url(day, hour)

                ticks, ok, empty, should_retry, missing = record_payload(
                    d, h, raw, status, url, bars, days_with_ticks
                )
                total_ticks += ticks
                successful_hours += ok
                empty_market_hours += empty
                missing_404 += missing
                if status == "downloaded" and ok:
                    downloaded_this_run += 1
                if should_retry:
                    retry.append((d, h))

        pending = retry

    deadline_hit = bool(pending) and time.monotonic() >= deadline
    reason = "deadline_exceeded" if deadline_hit else "retry_rounds_exhausted"
    for day, hour in pending:
        mod.failed_downloads.append(f"{mod.hour_url(day, hour)} | {reason}")

    print(f"PUBLIC_HISTORY_DOWNLOADED_THIS_RUN={downloaded_this_run}")
    print(f"PUBLIC_HISTORY_CACHE_SLOTS_FINAL={successful_hours + empty_market_hours}")
    print(f"PUBLIC_HISTORY_DEADLINE_HIT={str(deadline_hit).lower()}")
    print(f"PUBLIC_HISTORY_UNFINISHED_SLOTS={len(pending)}")

    return (
        total_ticks,
        successful_hours,
        len(pending),
        empty_market_hours,
        missing_404,
        days_with_ticks,
    )


mod.fetch_and_process_slots = fetch_and_process_slots_bounded
raise SystemExit(mod.main())
