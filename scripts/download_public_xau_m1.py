import csv
import datetime as dt
import lzma
import os
import struct
import sys
import time
import urllib.error
import urllib.request
from collections import OrderedDict

BASE_URL = "https://datafeed.dukascopy.com/datafeed"
INSTRUMENT = "XAUUSD"
SCALE = 1000.0
MAX_PUBLIC_SPREAD_POINTS = 80

# Public GitHub Actions validation uses Dukascopy's free endpoint. This endpoint
# sometimes stalls or returns short 503 bursts. Keep the window compact, but use
# enough timeout/retry budget so a valid test is not rejected as NO_HISTORY.
SESSION_HOURS = [8, 9, 10, 11, 13, 14, 15, 16]
FETCH_TIMEOUT_SECONDS = int(os.environ.get("PUBLIC_FETCH_TIMEOUT_SECONDS", "20"))
FETCH_RETRIES = int(os.environ.get("PUBLIC_FETCH_RETRIES", "2"))
MAX_DAYS = int(os.environ.get("PUBLIC_MAX_HISTORY_DAYS", "6"))
MIN_BARS_TO_STOP = int(os.environ.get("PUBLIC_MIN_BARS_TO_STOP", "2600"))
MAX_DOWNLOAD_SECONDS = int(os.environ.get("PUBLIC_MAX_DOWNLOAD_SECONDS", "720"))
MIN_REQUIRED_BARS = int(os.environ.get("PUBLIC_MIN_REQUIRED_BARS", "700"))


def parse_ymd(value: str) -> dt.date:
    return dt.datetime.strptime(value, "%Y.%m.%d").date()


def daterange(start: dt.date, end_inclusive: dt.date):
    d = start
    while d <= end_inclusive:
        yield d
        d += dt.timedelta(days=1)


def fetch(url: str, retries: int = FETCH_RETRIES) -> bytes | None:
    last_error = None
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) GitHubActions-XAU-Public-Backtest",
                    "Accept": "*/*",
                    "Connection": "close",
                    "Cache-Control": "no-cache",
                },
            )
            with urllib.request.urlopen(req, timeout=FETCH_TIMEOUT_SECONDS) as resp:
                data = resp.read()
            if data:
                return data
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return None
            last_error = f"HTTP error {exc.code}"
            print(f"download attempt {attempt}/{retries} failed for {url}: {last_error}")
        except Exception as exc:
            last_error = str(exc)
            print(f"download attempt {attempt}/{retries} failed for {url}: {last_error}")
        time.sleep(min(3.0, 0.75 * attempt))
    if last_error:
        print(f"download exhausted for {url}: {last_error}")
    return None


def decompress_bi5(data: bytes) -> bytes | None:
    try:
        return lzma.decompress(data)
    except Exception:
        try:
            return lzma.LZMADecompressor(format=lzma.FORMAT_AUTO).decompress(data)
        except Exception as exc:
            print(f"decompress failed: {exc}")
            return None


def update_bar(bars: OrderedDict, minute: dt.datetime, price: float, spread_points: int):
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


def download_day(day: dt.date, bars: OrderedDict):
    day_count = 0
    hours_ok = 0
    for hour in SESSION_HOURS:
        url = f"{BASE_URL}/{INSTRUMENT}/{day.year}/{day.month - 1:02d}/{day.day:02d}/{hour:02d}h_ticks.bi5"
        raw = fetch(url)
        if not raw:
            continue
        decompressed = decompress_bi5(raw)
        if not decompressed or len(decompressed) < 20:
            continue
        hours_ok += 1
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
            tick_time = dt.datetime(day.year, day.month, day.day, hour, tzinfo=dt.timezone.utc) + dt.timedelta(milliseconds=ms)
            minute = tick_time.replace(second=0, microsecond=0, tzinfo=None)
            update_bar(bars, minute, price, spread_points)
            day_count += 1
    print(f"{day.isoformat()} session_ticks={day_count} session_hours_ok={hours_ok} bars_so_far={len(bars)}")
    return day_count


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


def main():
    if len(sys.argv) < 4:
        print("usage: download_public_xau_m1.py FROM_DATE TO_DATE OUT_CSV")
        return 2
    start = parse_ymd(sys.argv[1])
    requested_end = parse_ymd(sys.argv[2])
    end = min(requested_end, start + dt.timedelta(days=MAX_DAYS - 1))
    out_csv = sys.argv[3]
    os.makedirs(os.path.dirname(os.path.abspath(out_csv)), exist_ok=True)

    bars = OrderedDict()
    total_ticks = 0
    started = time.time()
    days_with_ticks = 0
    for day in daterange(start, end):
        day_ticks = download_day(day, bars)
        total_ticks += day_ticks
        if day_ticks > 0:
            days_with_ticks += 1
        if len(bars) >= MIN_BARS_TO_STOP:
            print(f"PUBLIC_HISTORY_FAST_STOP_BARS={len(bars)}")
            break
        if time.time() - started > MAX_DOWNLOAD_SECONDS and len(bars) >= MIN_REQUIRED_BARS:
            print(f"PUBLIC_HISTORY_TIME_BUDGET_STOP_SECONDS={MAX_DOWNLOAD_SECONDS}")
            break

    bars = fill_missing_minutes(bars)
    with open(out_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["time", "open", "high", "low", "close", "tick_volume", "spread", "real_volume"])
        for t, row in bars.items():
            o, h, l, c, tv, spread, rv = row
            writer.writerow([t, f"{o:.3f}", f"{h:.3f}", f"{l:.3f}", f"{c:.3f}", int(tv), int(spread), int(rv)])

    print(f"PUBLIC_HISTORY_CSV={out_csv}")
    print(f"PUBLIC_HISTORY_TICKS={total_ticks}")
    print(f"PUBLIC_HISTORY_BARS={len(bars)}")
    print(f"PUBLIC_HISTORY_DAYS_WITH_TICKS={days_with_ticks}")
    print(f"PUBLIC_HISTORY_RANGE_REQUESTED={start.isoformat()}..{requested_end.isoformat()}")
    print(f"PUBLIC_HISTORY_RANGE_DOWNLOADED={start.isoformat()}..{end.isoformat()}")
    print(f"PUBLIC_HISTORY_SESSION_HOURS={','.join(map(str, SESSION_HOURS))}")
    print(f"PUBLIC_HISTORY_MAX_SPREAD_POINTS={MAX_PUBLIC_SPREAD_POINTS}")
    print(f"PUBLIC_FETCH_TIMEOUT_SECONDS={FETCH_TIMEOUT_SECONDS}")
    print(f"PUBLIC_FETCH_RETRIES={FETCH_RETRIES}")
    print(f"PUBLIC_MAX_DOWNLOAD_SECONDS={MAX_DOWNLOAD_SECONDS}")
    print("PUBLIC_HISTORY_FAST_LONDON_NY_ONLY=true")
    if len(bars) < MIN_REQUIRED_BARS:
        print("NOT_ENOUGH_PUBLIC_HISTORY")
        print("PUBLIC_HISTORY_SOURCE_UNAVAILABLE=true")
        return 20
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
