import csv
import datetime as dt
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
MAX_PUBLIC_SPREAD_POINTS = 80


def _int_env(name: str, default: int, min_value: int | None = None, max_value: int | None = None) -> int:
    try:
        value = int(os.environ.get(name, str(default)))
    except Exception:
        value = default
    if min_value is not None:
        value = max(min_value, value)
    if max_value is not None:
        value = min(max_value, value)
    return value


def _hours_env() -> list[int]:
    raw = os.environ.get("PUBLIC_SESSION_HOURS", "8,9,10,11,13,14,15,16")
    hours: list[int] = []
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            hour = int(part)
            if 0 <= hour <= 23 and hour not in hours:
                hours.append(hour)
        except Exception:
            pass
    return hours or [8, 9, 10, 11, 13, 14, 15, 16]


# Public GitHub Actions validation uses Dukascopy's free endpoint.
# The endpoint often returns 502/timeouts on individual hourly .bi5 files.
# This downloader must not let one bad hour kill a 1-year M15 chunk.
SESSION_HOURS = _hours_env()
FETCH_TIMEOUT_SECONDS = _int_env("PUBLIC_FETCH_TIMEOUT_SECONDS", 30, 5, 180)
FETCH_RETRIES = _int_env("PUBLIC_FETCH_RETRIES", 3, 1, 12)
FETCH_WORKERS = _int_env("PUBLIC_FETCH_WORKERS", 8, 1, 24)
MAX_DAYS = _int_env("PUBLIC_MAX_HISTORY_DAYS", 370, 1, 400)
MIN_BARS_TO_STOP = _int_env("PUBLIC_MIN_BARS_TO_STOP", 999999999, 1, None)
MAX_DOWNLOAD_SECONDS = _int_env("PUBLIC_MAX_DOWNLOAD_SECONDS", 10800, 60, None)
MIN_REQUIRED_BARS = _int_env("PUBLIC_MIN_REQUIRED_BARS", 12000, 1, None)
MIN_REQUIRED_DAYS_WITH_TICKS = _int_env("PUBLIC_MIN_REQUIRED_DAYS_WITH_TICKS", 20, 1, None)
CACHE_DIR = os.environ.get("PUBLIC_CACHE_DIR", "").strip()


failed_downloads: list[str] = []
missing_downloads: list[str] = []
status_counts: Counter = Counter()


def parse_ymd(value: str) -> dt.date:
    return dt.datetime.strptime(value, "%Y.%m.%d").date()


def daterange(start: dt.date, end_inclusive: dt.date):
    d = start
    while d <= end_inclusive:
        yield d
        d += dt.timedelta(days=1)


def hour_url(day: dt.date, hour: int) -> str:
    # Dukascopy months are zero-based in the datafeed path.
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
        except Exception as exc:
            print(f"cache read failed for {cache_path}: {exc}")

    last_error = ""
    for attempt in range(1, FETCH_RETRIES + 1):
        try:
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": "Mozilla/5.0 GitHubActions-XAU-Public-Backtest/2.0",
                    "Accept": "*/*",
                    "Connection": "close",
                    "Cache-Control": "no-cache",
                },
            )
            with urllib.request.urlopen(req, timeout=FETCH_TIMEOUT_SECONDS) as resp:
                data = resp.read()
            if data:
                if cache_path is not None:
                    try:
                        cache_path.parent.mkdir(parents=True, exist_ok=True)
                        tmp_path = cache_path.with_suffix(cache_path.suffix + ".tmp")
                        tmp_path.write_bytes(data)
                        tmp_path.replace(cache_path)
                    except Exception as exc:
                        print(f"cache write failed for {cache_path}: {exc}")
                return day, hour, data, "downloaded", url
            last_error = "empty response"
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return day, hour, None, "missing_404", url
            last_error = f"HTTP error {exc.code}"
        except Exception as exc:
            last_error = str(exc)

        print(f"download attempt {attempt}/{FETCH_RETRIES} failed for {url}: {last_error}")
        time.sleep(min(8.0, 1.0 + attempt * 1.5))

    return day, hour, None, f"failed: {last_error}", url


def decompress_bi5(data: bytes) -> bytes | None:
    try:
        return lzma.decompress(data)
    except Exception:
        try:
            return lzma.LZMADecompressor(format=lzma.FORMAT_AUTO).decompress(data)
        except Exception as exc:
            print(f"decompress failed: {exc}")
            return None


def update_bar(bars: dict[str, list], minute: dt.datetime, price: float, spread_points: int):
    key = minute.strftime("%Y.%m.%d %H:%M")
    spread_points = max(1, min(MAX_PUBLIC_SPREAD_POINTS, int(spread_points)))
    if key not in bars:
        bars[key] = [price, price, price, price, 0, spread_points, 0]
    bar = bars[key]
    bar[1] = max(bar[1], price)
    bar[2] = min(bar[2], price)
    bar[3] = price
    bar[4] += 1
    if spread_points > 0:
        bar[5] = min(bar[5], spread_points)


def process_hour(day: dt.date, hour: int, raw: bytes, bars: dict[str, list]) -> int:
    decompressed = decompress_bi5(raw)
    if not decompressed or len(decompressed) < 20:
        return 0

    tick_count = 0
    base_time = dt.datetime(day.year, day.month, day.day, hour, tzinfo=dt.timezone.utc)
    for offset in range(0, len(decompressed) - 19, 20):
        chunk = decompressed[offset:offset + 20]
        try:
            ms, ask_i, bid_i, ask_vol, bid_vol = struct.unpack(">IIIff", chunk)
        except Exception:
            continue
        ask = ask_i / SCALE
        bid = bid_i / SCALE
        if ask <= 0 or bid <= 0:
            continue
        price = (ask + bid) / 2.0
        spread_points = max(1, int(round((ask - bid) * SCALE)))
        tick_time = base_time + dt.timedelta(milliseconds=ms)
        minute = tick_time.replace(second=0, microsecond=0, tzinfo=None)
        update_bar(bars, minute, price, spread_points)
        tick_count += 1
    return tick_count


def download_day(day: dt.date, bars: dict[str, list]) -> tuple[int, int]:
    day_ticks = 0
    hours_ok = 0
    max_workers = min(FETCH_WORKERS, len(SESSION_HOURS))

    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        futures = [pool.submit(fetch_hour, day, hour) for hour in SESSION_HOURS]
        for future in as_completed(futures):
            d, hour, raw, status, url = future.result()
            status_counts[status.split(":", 1)[0]] += 1
            if status == "missing_404":
                missing_downloads.append(url)
                continue
            if raw is None:
                failed_downloads.append(f"{url} | {status}")
                print(f"download exhausted for {url}: {status}")
                continue
            ticks = process_hour(d, hour, raw, bars)
            if ticks > 0:
                day_ticks += ticks
                hours_ok += 1

    print(f"{day.isoformat()} session_ticks={day_ticks} session_hours_ok={hours_ok} bars_so_far={len(bars)}")
    return day_ticks, hours_ok


def sort_bars(bars: dict[str, list]) -> OrderedDict:
    return OrderedDict((key, bars[key]) for key in sorted(bars.keys()))


def fill_missing_minutes(bars: OrderedDict):
    if not bars:
        return bars
    keys = list(bars.keys())
    start = dt.datetime.strptime(keys[0], "%Y.%m.%d %H:%M")
    end = dt.datetime.strptime(keys[-1], "%Y.%m.%d %H:%M")
    filled = OrderedDict()
    last_close = None
    current = start
    while current <= end:
        key = current.strftime("%Y.%m.%d %H:%M")
        if key in bars:
            filled[key] = bars[key]
            last_close = bars[key][3]
        elif last_close is not None:
            filled[key] = [last_close, last_close, last_close, last_close, 1, min(30, MAX_PUBLIC_SPREAD_POINTS), 0]
        current += dt.timedelta(minutes=1)
    return filled


def write_diagnostics(out_csv: str, bars_count: int, total_ticks: int, days_with_ticks: int, hours_ok_total: int):
    out_dir = Path(out_csv).resolve().parent
    out_dir.mkdir(parents=True, exist_ok=True)

    if failed_downloads:
        (out_dir / "failed_downloads.txt").write_text("\n".join(failed_downloads), encoding="utf-8")
    if missing_downloads:
        (out_dir / "missing_404_downloads.txt").write_text("\n".join(missing_downloads), encoding="utf-8")

    diag = [
        f"bars={bars_count}",
        f"ticks={total_ticks}",
        f"days_with_ticks={days_with_ticks}",
        f"hours_ok_total={hours_ok_total}",
        f"failed_count={len(failed_downloads)}",
        f"missing_404_count={len(missing_downloads)}",
        f"status_counts={dict(status_counts)}",
        f"fetch_timeout_seconds={FETCH_TIMEOUT_SECONDS}",
        f"fetch_retries={FETCH_RETRIES}",
        f"fetch_workers={FETCH_WORKERS}",
        f"session_hours={SESSION_HOURS}",
        f"cache_dir={CACHE_DIR or 'disabled'}",
    ]
    (out_dir / "download_diagnostics.txt").write_text("\n".join(diag), encoding="utf-8")


def main():
    if len(sys.argv) < 4:
        print("usage: download_public_xau_m1.py FROM_DATE TO_DATE OUT_CSV")
        return 2

    start = parse_ymd(sys.argv[1])
    requested_end = parse_ymd(sys.argv[2])
    end = min(requested_end, start + dt.timedelta(days=MAX_DAYS - 1))
    out_csv = sys.argv[3]
    os.makedirs(os.path.dirname(os.path.abspath(out_csv)), exist_ok=True)

    bars: dict[str, list] = {}
    total_ticks = 0
    hours_ok_total = 0
    started = time.time()
    days_with_ticks = 0

    for day in daterange(start, end):
        day_ticks, hours_ok = download_day(day, bars)
        total_ticks += day_ticks
        hours_ok_total += hours_ok
        if day_ticks > 0:
            days_with_ticks += 1

        if len(bars) >= MIN_BARS_TO_STOP:
            print(f"PUBLIC_HISTORY_FAST_STOP_BARS={len(bars)}")
            break

        elapsed = time.time() - started
        if elapsed > MAX_DOWNLOAD_SECONDS and len(bars) >= MIN_REQUIRED_BARS:
            print(f"PUBLIC_HISTORY_TIME_BUDGET_STOP_SECONDS={MAX_DOWNLOAD_SECONDS}")
            break
        if elapsed > MAX_DOWNLOAD_SECONDS and len(bars) < MIN_REQUIRED_BARS:
            print(f"PUBLIC_HISTORY_TIME_BUDGET_EXHAUSTED_SECONDS={MAX_DOWNLOAD_SECONDS}")
            break

    ordered = sort_bars(bars)
    filled = fill_missing_minutes(ordered)

    with open(out_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["time", "open", "high", "low", "close", "tick_volume", "spread", "real_volume"])
        for t, row in filled.items():
            o, h, l, c, tv, spread, rv = row
            writer.writerow([t, f"{o:.3f}", f"{h:.3f}", f"{l:.3f}", f"{c:.3f}", int(tv), int(spread), int(rv)])

    write_diagnostics(out_csv, len(filled), total_ticks, days_with_ticks, hours_ok_total)

    print(f"PUBLIC_HISTORY_CSV={out_csv}")
    print(f"PUBLIC_HISTORY_TICKS={total_ticks}")
    print(f"PUBLIC_HISTORY_BARS={len(filled)}")
    print(f"PUBLIC_HISTORY_DAYS_WITH_TICKS={days_with_ticks}")
    print(f"PUBLIC_HISTORY_HOURS_OK={hours_ok_total}")
    print(f"PUBLIC_HISTORY_FAILED_DOWNLOADS={len(failed_downloads)}")
    print(f"PUBLIC_HISTORY_MISSING_404={len(missing_downloads)}")
    print(f"PUBLIC_HISTORY_RANGE_REQUESTED={start.isoformat()}..{requested_end.isoformat()}")
    print(f"PUBLIC_HISTORY_RANGE_DOWNLOADED={start.isoformat()}..{end.isoformat()}")
    print(f"PUBLIC_HISTORY_SESSION_HOURS={','.join(map(str, SESSION_HOURS))}")
    print(f"PUBLIC_HISTORY_MAX_SPREAD_POINTS={MAX_PUBLIC_SPREAD_POINTS}")
    print(f"PUBLIC_FETCH_TIMEOUT_SECONDS={FETCH_TIMEOUT_SECONDS}")
    print(f"PUBLIC_FETCH_RETRIES={FETCH_RETRIES}")
    print(f"PUBLIC_FETCH_WORKERS={FETCH_WORKERS}")
    print(f"PUBLIC_MAX_DOWNLOAD_SECONDS={MAX_DOWNLOAD_SECONDS}")
    print("PUBLIC_HISTORY_FAST_LONDON_NY_ONLY=true")

    if len(filled) < MIN_REQUIRED_BARS or days_with_ticks < MIN_REQUIRED_DAYS_WITH_TICKS:
        print("NOT_ENOUGH_PUBLIC_HISTORY")
        print("PUBLIC_HISTORY_SOURCE_UNAVAILABLE=true")
        return 20
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
