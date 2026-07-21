"""Deadline-enforced, shard-aware and cache-progressive public XAUUSD downloader.

The canonical downloader remains responsible for BI5 parsing, bar construction and
quality checks. This wrapper changes only deterministic scheduling and HTTP
acquisition. It never fabricates data, validates every downloaded payload through
the canonical parser, evicts corrupt cache entries, retries only unresolved hours,
and terminates with explicit diagnostics when the real-data threshold cannot be met.
"""
from __future__ import annotations

import importlib.util
import os
import time
import urllib.error
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("download_public_xau_m1.py")
spec = importlib.util.spec_from_file_location("xau_public_downloader", MODULE_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Cannot load canonical downloader: {MODULE_PATH}")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def int_env(name: str, default: int, minimum: int, maximum: int) -> int:
    try:
        value = int(os.environ.get(name, str(default)))
    except (TypeError, ValueError):
        value = default
    return max(minimum, min(maximum, value))


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


def evict_cached_hour(day, hour) -> bool:
    path = mod.cache_path_for(day, hour)
    if path is None:
        return False
    try:
        if path.exists():
            path.unlink()
            return True
    except OSError as exc:
        print(f"PUBLIC_HISTORY_CACHE_EVICT_FAILED={path}|{type(exc).__name__}:{exc}")
    return False


def atomic_save(day, hour, data: bytes) -> None:
    cache_path = mod.cache_path_for(day, hour)
    if cache_path is None:
        return
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = cache_path.with_suffix(cache_path.suffix + ".tmp")
    tmp.write_bytes(data)
    tmp.replace(cache_path)


def fetch_hour_once(day, hour, deadline: float):
    url = mod.hour_url(day, hour)
    if cache_has_payload(day, hour):
        return read_cached_hour(day, hour)

    remaining = deadline - time.monotonic()
    if remaining <= 0:
        return day, hour, None, "deadline_exceeded", url

    timeout = max(1.0, min(float(mod.FETCH_TIMEOUT_SECONDS), remaining))
    try:
        request = urllib.request.Request(
            url,
            headers={
                "User-Agent": "Mozilla/5.0 GitHubActions-XAU-Public-Backtest/8.0",
                "Accept": "application/octet-stream,*/*;q=0.8",
                "Accept-Encoding": "identity",
                "Cache-Control": "no-cache",
                "Connection": "close",
            },
        )
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data = response.read()
        if not data:
            return day, hour, None, "empty_response", url
        return day, hour, data, "downloaded", url
    except urllib.error.HTTPError as exc:
        return day, hour, None, f"http_error:{exc.code}", url
    except urllib.error.URLError as exc:
        return day, hour, None, f"url_error:{exc.reason}", url
    except TimeoutError:
        return day, hour, None, "timeout", url
    except Exception as exc:
        return day, hour, None, f"failed:{type(exc).__name__}:{exc}", url


def rotated(slots, round_no: int):
    items = list(slots)
    if not items:
        return items
    run_id = int_env("GITHUB_RUN_ID", 1, 1, 2_147_483_647)
    run_attempt = int_env("GITHUB_RUN_ATTEMPT", 1, 1, 100_000)
    offset = (run_id * 37 + run_attempt * 977 + (round_no - 1) * 503) % len(items)
    return items[offset:] + items[:offset]


def shard_slots(slots):
    shard_count = int_env("PUBLIC_SLOT_SHARD_COUNT", 1, 1, 64)
    shard_index = int_env("PUBLIC_SLOT_SHARD_INDEX", 0, 0, shard_count - 1)
    if shard_count == 1:
        return list(slots)
    selected = [slot for position, slot in enumerate(slots) if position % shard_count == shard_index]
    print(f"PUBLIC_HISTORY_SHARD_INDEX={shard_index}")
    print(f"PUBLIC_HISTORY_SHARD_COUNT={shard_count}")
    print(f"PUBLIC_HISTORY_SHARD_SLOTS={len(selected)}")
    return selected


def retryable_status(status: str, attempt_count: int) -> bool:
    base = status.split(":", 1)[0]
    if base in {"deadline_exceeded", "cache_disabled"}:
        return False
    if base == "http_error" and status.endswith(":404"):
        return attempt_count < int_env("PUBLIC_404_RETRY_LIMIT", 4, 1, 12)
    return base in {
        "http_error",
        "url_error",
        "timeout",
        "empty_response",
        "failed",
        "cache_read_failed",
        "cache_empty",
    }


def register_terminal_failure(day, hour, status: str, url: str) -> int:
    mod.fetch_attempt_status_counts[status.split(":", 1)[0]] += 1
    if status == "http_error:404":
        mod.missing_downloads.append(url)
        return 1
    mod.failed_downloads.append(f"{url} | {status}")
    return 0


def process_payload(day, hour, raw: bytes, bars, days_with_ticks):
    payload_status, ticks = mod.process_hour(day, hour, raw, bars)
    if payload_status == "ok":
        atomic_save(day, hour, raw)
        days_with_ticks.add(day)
        return ticks, 1, 0, False
    if payload_status == "empty_market":
        atomic_save(day, hour, raw)
        return 0, 0, 1, False
    evict_cached_hour(day, hour)
    return 0, 0, 0, True


def fetch_and_process_slots_bounded(slots, deadline_epoch: float, bars):
    slots = shard_slots(slots)
    remaining_budget = max(0.0, deadline_epoch - time.time())
    deadline = time.monotonic() + remaining_budget
    total_ticks = 0
    successful_hours = 0
    empty_market_hours = 0
    missing_404 = 0
    days_with_ticks = set()

    cached_slots, missing_slots = [], []
    for day, hour in slots:
        (cached_slots if cache_has_payload(day, hour) else missing_slots).append((day, hour))
    print(f"PUBLIC_HISTORY_CACHE_SLOTS_INITIAL={len(cached_slots)}")
    print(f"PUBLIC_HISTORY_MISSING_SLOTS_INITIAL={len(missing_slots)}")

    pending = list(missing_slots)
    evicted_corrupt = 0
    for day, hour in cached_slots:
        d, h, raw, status, _ = read_cached_hour(day, hour)
        if raw is None:
            pending.append((day, hour))
            continue
        ticks, ok, empty, corrupt = process_payload(d, h, raw, bars, days_with_ticks)
        total_ticks += ticks
        successful_hours += ok
        empty_market_hours += empty
        if corrupt:
            evicted_corrupt += 1
            pending.append((day, hour))

    print(f"PUBLIC_HISTORY_CACHE_CORRUPT_EVICTED={evicted_corrupt}")
    downloaded_this_run = 0
    attempts = Counter()
    last_status = {}
    max_rounds = max(
        int(getattr(mod, "FETCH_RETRY_ROUNDS", 1)),
        int_env("PUBLIC_FETCH_MAX_ADAPTIVE_ROUNDS", 48, 1, 96),
    )
    workers = max(int(getattr(mod, "FETCH_WORKERS", 1)), int_env("PUBLIC_ADAPTIVE_WORKERS", 12, 1, 24))

    round_no = 0
    while pending and time.monotonic() < deadline and round_no < max_rounds:
        round_no += 1
        work = rotated(pending, round_no)
        retry = []
        status_counts = Counter()
        print(f"FETCH_ROUND={round_no} pending={len(work)} workers={workers} missing_only=true")
        with ThreadPoolExecutor(max_workers=workers) as pool:
            future_map = {pool.submit(fetch_hour_once, day, hour, deadline): (day, hour) for day, hour in work}
            for future in as_completed(future_map):
                day, hour = future_map[future]
                attempts[(day, hour)] += 1
                try:
                    d, h, raw, status, url = future.result()
                except Exception as exc:
                    d, h = day, hour
                    raw, status, url = None, f"failed:{type(exc).__name__}:{exc}", mod.hour_url(day, hour)
                status_counts[status.split(":", 1)[0]] += 1
                last_status[(d, h)] = (status, url)
                if raw is not None:
                    ticks, ok, empty, corrupt = process_payload(d, h, raw, bars, days_with_ticks)
                    total_ticks += ticks
                    successful_hours += ok
                    empty_market_hours += empty
                    if ok or empty:
                        mod.fetch_attempt_status_counts[status.split(":", 1)[0]] += 1
                        if status == "downloaded" and ok:
                            downloaded_this_run += 1
                        continue
                    status = "corrupt_payload"
                    last_status[(d, h)] = (status, url)
                if retryable_status(status, attempts[(d, h)]) and time.monotonic() < deadline:
                    retry.append((d, h))
                else:
                    missing_404 += register_terminal_failure(d, h, status, url)
        pending = retry
        print("FETCH_ROUND_STATUS=" + ",".join(f"{key}:{value}" for key, value in sorted(status_counts.items())))
        if pending and time.monotonic() < deadline:
            sleep_seconds = min(30.0, 1.5 * round_no)
            time.sleep(min(sleep_seconds, max(0.0, deadline - time.monotonic())))

    deadline_hit = bool(pending) and time.monotonic() >= deadline
    round_limit_hit = bool(pending) and round_no >= max_rounds and not deadline_hit
    terminal_reason = "deadline_exceeded" if deadline_hit else "adaptive_retry_round_limit_exhausted"
    for day, hour in pending:
        status, url = last_status.get((day, hour), (terminal_reason, mod.hour_url(day, hour)))
        mod.failed_downloads.append(f"{url} | {terminal_reason};last_status={status};attempts={attempts[(day, hour)]}")

    print(f"PUBLIC_HISTORY_DOWNLOADED_THIS_RUN={downloaded_this_run}")
    print(f"PUBLIC_HISTORY_CACHE_SLOTS_FINAL={successful_hours + empty_market_hours}")
    print(f"PUBLIC_HISTORY_ADAPTIVE_ROUNDS={round_no}")
    print(f"PUBLIC_HISTORY_DEADLINE_HIT={str(deadline_hit).lower()}")
    print(f"PUBLIC_HISTORY_ROUND_LIMIT_HIT={str(round_limit_hit).lower()}")
    print(f"PUBLIC_HISTORY_UNFINISHED_SLOTS={len(pending)}")
    if pending:
        print(
            "BLOCKING_DIAGNOSIS=real_dukascopy_hours_unresolved_after_bounded_missing_only_retry;"
            f"remaining={len(pending)};rounds={round_no};deadline_hit={str(deadline_hit).lower()}"
        )
    return total_ticks, successful_hours, len(pending), empty_market_hours, missing_404, days_with_ticks


mod.fetch_and_process_slots = fetch_and_process_slots_bounded
raise SystemExit(mod.main())
