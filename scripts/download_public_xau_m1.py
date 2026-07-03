import csv
import datetime as dt
import hashlib
import lzma
import os
import struct
import sys
import time
import urllib.error
import urllib.request
from collections import Counter, OrderedDict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

BASE_URL = "https://datafeed.dukascopy.com/datafeed"
INSTRUMENT = "XAUUSD"
SCALE = 1000.0
MAX_PUBLIC_SPREAD_POINTS = 120


def int_env(name: str, default: int, minimum: int | None = None, maximum: int | None = None) -> int:
    try:
        value = int(os.environ.get(name, str(default)))
    except Exception:
        value = default
    if minimum is not None:
        value = max(minimum, value)
    if maximum is not None:
        value = min(maximum, value)
    return value


def float_env(name: str, default: float, minimum: float | None = None, maximum: float | None = None) -> float:
    try:
        value = float(os.environ.get(name, str(default)))
    except Exception:
        value = default
    if minimum is not None:
        value = max(minimum, value)
    if maximum is not None:
        value = min(maximum, value)
    return value


def hours_env() -> list[int]:
    raw = os.environ.get("PUBLIC_SESSION_HOURS", "7,8,9,10,11,12,13,14,15,16,17,18,19,20")
    hours: list[int] = []
    for part in raw.split(","):
        try:
            hour = int(part.strip())
        except Exception:
            continue
        if 0 <= hour <= 23 and hour not in hours:
            hours.append(hour)
    return hours or list(range(7, 21))


SESSION_HOURS = hours_env()
FETCH_TIMEOUT_SECONDS = int_env("PUBLIC_FETCH_TIMEOUT_SECONDS", 25, 5, 180)
FETCH_RETRIES = int_env("PUBLIC_FETCH_RETRIES", 4, 1, 12)
FETCH_RETRY_ROUNDS = int_env("PUBLIC_FETCH_RETRY_ROUNDS", 3, 1, 8)
FETCH_WORKERS = int_env("PUBLIC_FETCH_WORKERS", 24, 1, 32)
MAX_DAYS = int_env("PUBLIC_MAX_HISTORY_DAYS", 370, 1, 400)
MAX_DOWNLOAD_SECONDS = int_env("PUBLIC_MAX_DOWNLOAD_SECONDS", 10800, 60)
MIN_REQUIRED_BARS = int_env("PUBLIC_MIN_REQUIRED_BARS", 150000, 1)
MIN_REQUIRED_DAYS_WITH_TICKS = int_env("PUBLIC_MIN_REQUIRED_DAYS_WITH_TICKS", 220, 1)
MIN_HOUR_SUCCESS_RATIO = float_env("PUBLIC_MIN_HOUR_SUCCESS_RATIO", 0.90, 0.0, 1.0)
CACHE_DIR = os.environ.get("PUBLIC_CACHE_DIR", "").strip()

failed_downloads: list[str] = []
missing_downloads: list[str] = []
status_counts: Counter = Counter()


def parse_ymd(value: str) -> dt.date:
    return dt.datetime.strptime(value, "%Y.%m.%d").date()


def daterange(start: dt.date, end_inclusive: dt.date):
    current = start
    while current <= end_inclusive:
        yield current
        current += dt.timedelta(days=1)


def market_days(start: dt.date, end: dt.date) -> list[dt.date]:
    return [day for day in daterange(start, end) if day.weekday() < 5]


def hour_url(day: dt.date, hour: int) -> str:
    return f"{BASE_URL}/{INSTRUMENT}/{day.year}/{day.month - 1:02d}/{day.day:02d}/{hour:02d}h_ticks.bi5"


def cache_path_for(day: dt.date, hour: int) -> Path | None:
    if not CACHE_DIR:
        return None
    return Path(CACHE_DIR) / INSTRUMENT / f"{day.year}" / f"{day.month - 1:02d}" / f"{day.day:02d}" / f"{hour:02d}h_ticks.bi5"


def fetch_hour(day: dt.date, hour: int) -> tuple[dt.date, int, bytes | None, str, str]:
    url = hour_url(day, hour)
    cache_path = cache_path_for(day, hour)
    if cache_path is not None and cache_path.exists() and cache_path.stat().st_size > 0:
        try:
            return day, hour, cache_path.read_bytes(), "cached", url
        except Exception:
            pass

    last_error = ""
    for attempt in range(1, FETCH_RETRIES + 1):
        try:
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": "Mozilla/5.0 GitHubActions-XAU-Public-Backtest/3.0",
                    "Accept": "*/*",
                    "Connection": "close",
                },
            )
            with urllib.request.urlopen(req, timeout=FETCH_TIMEOUT_SECONDS) as response:
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

        time.sleep(min(5.0, 0.5 + attempt))

    return day, hour, None, f"failed:{last_error}", url


def decompress_bi5(data: bytes) -> bytes | None:
    try:
        return lzma.decompress(data)
    except Exception:
        try:
            return lzma.LZMADecompressor(format=lzma.FORMAT_AUTO).decompress(data)
        except Exception:
            return None


def update_bar(bars: dict[str, list], minute: dt.datetime, price: float, spread_points: int) -> None:
    key = minute.strftime("%Y.%m.%d %H:%M")
    spread_points = max(1, min(MAX_PUBLIC_SPREAD_POINTS, int(spread_points)))
    if key not in bars:
        bars[key] = [price, price, price, price, 0, spread_points, 0]
    bar = bars[key]
    bar[1] = max(bar[1], price)
    bar[2] = min(bar[2], price)
    bar[3] = price
    bar[4] += 1
    bar[5] = min(bar[5], spread_points)


def process_hour(day: dt.date, hour: int, raw: bytes, bars: dict[str, list]) -> int:
    data = decompress_bi5(raw)
    if not data or len(data) < 20:
        return 0

    base_time = dt.datetime(day.year, day.month, day.day, hour, tzinfo=dt.timezone.utc)
    tick_count = 0
    for offset in range(0, len(data) - 19, 20):
        try:
            ms, ask_i, bid_i, _ask_vol, _bid_vol = struct.unpack(">IIIff", data[offset:offset + 20])
        except Exception:
            continue
        ask = ask_i / SCALE
        bid = bid_i / SCALE
        if ask <= 0 or bid <= 0 or ask < bid:
            continue
        price = (ask + bid) / 2.0
        spread_points = max(1, int(round((ask - bid) * SCALE)))
        tick_time = base_time + dt.timedelta(milliseconds=ms)
        minute = tick_time.replace(second=0, microsecond=0, tzinfo=None)
        update_bar(bars, minute, price, spread_points)
        tick_count += 1
    return tick_count


def fetch_slots(slots: list[tuple[dt.date, int]], deadline: float):
    pending = list(slots)
    results: dict[tuple[dt.date, int], tuple[bytes | None, str, str]] = {}

    for round_no in range(1, FETCH_RETRY_ROUNDS + 1):
        if not pending or time.time() >= deadline:
            break

        retry: list[tuple[dt.date, int]] = []
        print(f"FETCH_ROUND={round_no} pending={len(pending)} workers={FETCH_WORKERS}")
        with ThreadPoolExecutor(max_workers=FETCH_WORKERS) as pool:
            future_map = {pool.submit(fetch_hour, day, hour): (day, hour) for day, hour in pending}
            for future in as_completed(future_map):
                day, hour = future_map[future]
                try:
                    d, h, raw, status, url = future.result()
                except Exception as exc:
                    raw, status, url = None, f"failed:{exc}", hour_url(day, hour)
                    d, h = day, hour

                key = (d, h)
                status_key = status.split(":", 1)[0]
                status_counts[status_key] += 1
                if raw is not None or status == "missing_404":
                    results[key] = (raw, status, url)
                else:
                    retry.append(key)

        pending = retry

    for day, hour in pending:
        url = hour_url(day, hour)
        results[(day, hour)] = (None, "failed:retry_rounds_exhausted", url)

    return results


def write_csv(out_csv: str, bars: dict[str, list]) -> tuple[int, str]:
    ordered = OrderedDict((key, bars[key]) for key in sorted(bars))
    hasher = hashlib.sha256()
    count = 0

    with open(out_csv, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        header = ["time", "open", "high", "low", "close", "tick_volume", "spread", "real_volume"]
        writer.writerow(header)
        hasher.update((",".join(header) + "\n").encode())

        for timestamp, row in ordered.items():
            o, h, l, c, tick_volume, spread, real_volume = row
            values = [
                timestamp,
                f"{o:.3f}",
                f"{h:.3f}",
                f"{l:.3f}",
                f"{c:.3f}",
                str(int(tick_volume)),
                str(int(spread)),
                str(int(real_volume)),
            ]
            writer.writerow(values)
            hasher.update((",".join(values) + "\n").encode())
            count += 1

    return count, hasher.hexdigest()


def main() -> int:
    if len(sys.argv) < 4:
        print("usage: download_public_xau_m1.py FROM_DATE TO_DATE OUT_CSV")
        return 2

    start = parse_ymd(sys.argv[1])
    requested_end = parse_ymd(sys.argv[2])
    end = min(requested_end, start + dt.timedelta(days=MAX_DAYS - 1))
    out_csv = sys.argv[3]
    os.makedirs(os.path.dirname(os.path.abspath(out_csv)), exist_ok=True)

    days = market_days(start, end)
    slots = [(day, hour) for day in days for hour in SESSION_HOURS]
    deadline = time.time() + MAX_DOWNLOAD_SECONDS
    results = fetch_slots(slots, deadline)

    bars: dict[str, list] = {}
    total_ticks = 0
    days_with_ticks: set[dt.date] = set()
    successful_hours = 0
    failed_hours = 0
    missing_404 = 0

    for (day, hour), (raw, status, url) in sorted(results.items()):
        if raw is not None:
            ticks = process_hour(day, hour, raw, bars)
            if ticks > 0:
                total_ticks += ticks
                days_with_ticks.add(day)
                successful_hours += 1
            else:
                failed_hours += 1
                failed_downloads.append(f"{url} | empty_or_invalid_payload")
        elif status == "missing_404":
            missing_404 += 1
            missing_downloads.append(url)
        else:
            failed_hours += 1
            failed_downloads.append(f"{url} | {status}")

    bars_count, dataset_sha256 = write_csv(out_csv, bars)
    denominator = successful_hours + failed_hours
    hour_success_ratio = successful_hours / denominator if denominator else 0.0

    out_dir = Path(out_csv).resolve().parent
    if failed_downloads:
        (out_dir / "failed_downloads.txt").write_text("\n".join(failed_downloads), encoding="utf-8")
    if missing_downloads:
        (out_dir / "missing_404_downloads.txt").write_text("\n".join(missing_downloads), encoding="utf-8")

    diagnostics = {
        "bars": bars_count,
        "ticks": total_ticks,
        "days_with_ticks": len(days_with_ticks),
        "market_days_requested": len(days),
        "successful_hours": successful_hours,
        "failed_hours": failed_hours,
        "missing_404_hours": missing_404,
        "hour_success_ratio": round(hour_success_ratio, 6),
        "min_required_hour_success_ratio": MIN_HOUR_SUCCESS_RATIO,
        "failed_count": len(failed_downloads),
        "status_counts": dict(status_counts),
        "fetch_timeout_seconds": FETCH_TIMEOUT_SECONDS,
        "fetch_retries": FETCH_RETRIES,
        "fetch_retry_rounds": FETCH_RETRY_ROUNDS,
        "fetch_workers": FETCH_WORKERS,
        "session_hours": SESSION_HOURS,
        "cache_dir": CACHE_DIR or "disabled",
        "synthetic_fill_bars": 0,
        "dataset_sha256": dataset_sha256,
        "range_requested": f"{start.isoformat()}..{requested_end.isoformat()}",
        "range_downloaded": f"{start.isoformat()}..{end.isoformat()}",
    }
    (out_dir / "download_diagnostics.json").write_text(
        __import__("json").dumps(diagnostics, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    (out_dir / "download_diagnostics.txt").write_text(
        "\n".join(f"{key}={value}" for key, value in diagnostics.items()),
        encoding="utf-8",
    )

    print(f"PUBLIC_HISTORY_BARS={bars_count}")
    print(f"PUBLIC_HISTORY_DAYS_WITH_TICKS={len(days_with_ticks)}")
    print(f"PUBLIC_HISTORY_SUCCESSFUL_HOURS={successful_hours}")
    print(f"PUBLIC_HISTORY_FAILED_HOURS={failed_hours}")
    print(f"PUBLIC_HISTORY_MISSING_404={missing_404}")
    print(f"PUBLIC_HISTORY_HOUR_SUCCESS_RATIO={hour_success_ratio:.6f}")
    print(f"PUBLIC_HISTORY_SYNTHETIC_FILL_BARS=0")
    print(f"PUBLIC_HISTORY_DATASET_SHA256={dataset_sha256}")

    failures = []
    if bars_count < MIN_REQUIRED_BARS:
        failures.append(f"bars {bars_count} < {MIN_REQUIRED_BARS}")
    if len(days_with_ticks) < MIN_REQUIRED_DAYS_WITH_TICKS:
        failures.append(f"days_with_ticks {len(days_with_ticks)} < {MIN_REQUIRED_DAYS_WITH_TICKS}")
    if hour_success_ratio < MIN_HOUR_SUCCESS_RATIO:
        failures.append(f"hour_success_ratio {hour_success_ratio:.4f} < {MIN_HOUR_SUCCESS_RATIO:.4f}")

    if failures:
        print("PUBLIC_HISTORY_QUALITY_FAIL=" + " | ".join(failures))
        return 20

    print("PUBLIC_HISTORY_QUALITY_PASS=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
