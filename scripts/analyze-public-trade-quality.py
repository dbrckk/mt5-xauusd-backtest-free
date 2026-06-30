import argparse
import csv
import json
import re
from datetime import datetime, timedelta
from pathlib import Path

TEXT_EXTENSIONS = {".txt", ".log", ".ini", ".set", ".csv", ".html", ".htm", ".json"}
DEAL_RE = re.compile(
    r"(?P<time>20\d{2}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}).*?deal #(?P<id>\d+) (?P<side>buy|sell) (?P<lot>[0-9.]+) XAU_PUBLIC at (?P<price>[0-9.]+) done",
    re.IGNORECASE,
)

PERIOD_MINUTES = {"M15": 15, "M30": 30, "H1": 60, "H2": 120, "H4": 240}


def decode_text(data: bytes) -> str:
    candidates = []
    for enc in ("utf-8", "utf-16", "utf-16le", "cp1252", "latin1"):
        try:
            text = data.decode(enc, errors="replace")
            candidates.append((text[:2000].count("\x00"), -len(text), text))
        except Exception:
            pass
    if not candidates:
        return data.decode("utf-8", errors="replace")
    candidates.sort(key=lambda item: (item[0], item[1]))
    return candidates[0][2]


def read_all_texts(root: Path) -> dict[str, str]:
    out = {}
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in TEXT_EXTENSIONS:
            try:
                out[str(path.relative_to(root))] = decode_text(path.read_bytes())
            except Exception:
                continue
    return out


def final_balance_from_blob(blob: str) -> float | None:
    patterns = [
        r"final balance\s+([0-9]+(?:\.[0-9]+)?)\s+USD",
        r"Final balance</td><td>([0-9]+(?:\.[0-9]+)?)\s+USD",
        r"Final balance.*?([0-9]+(?:\.[0-9]+)?)\s+USD",
    ]
    for pattern in patterns:
        match = re.search(pattern, blob, re.IGNORECASE | re.DOTALL)
        if match:
            return float(match.group(1))
    return None


def extract_journal_lines(texts: dict[str, str]) -> list[str]:
    lines = []
    for name, text in texts.items():
        if "journal" in name.lower() and name.lower().endswith(".csv"):
            lines.extend([line.strip() for line in text.splitlines() if line.strip()])
    return lines


def line_direction(line: str) -> str | None:
    upper = line.upper()
    if "BUY" in upper:
        return "BUY"
    if "SELL" in upper:
        return "SELL"
    return None


def first_timestamp(line: str) -> str | None:
    match = re.search(r"\b20\d{2}[./-]\d{2}[./-]\d{2}\s+\d{2}:\d{2}:\d{2}\b", line)
    return match.group(0) if match else None


def parse_time(value: str) -> datetime:
    return datetime.strptime(value.replace(".", "-", 2), "%Y-%m-%d %H:%M:%S")


def parse_day(value: str) -> datetime:
    return datetime.strptime(value, "%Y.%m.%d")


def find_file(root: Path, name: str) -> Path | None:
    matches = list(root.rglob(name))
    return matches[0] if matches else None


def load_bars(root: Path):
    path = find_file(root, "xau_public_m1.csv")
    if path is None:
        return []
    rows = []
    with path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                rows.append({
                    "time": datetime.strptime(row["time"], "%Y.%m.%d %H:%M"),
                    "high": float(row["high"]),
                    "low": float(row["low"]),
                })
            except Exception:
                continue
    return rows


def load_m1_ohlcv(root: Path):
    path = find_file(root, "xau_public_m1.csv")
    if path is None:
        return []
    rows = []
    with path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                rows.append({
                    "time": datetime.strptime(row["time"], "%Y.%m.%d %H:%M"),
                    "open": float(row["open"]),
                    "high": float(row["high"]),
                    "low": float(row["low"]),
                    "close": float(row["close"]),
                    "volume": float(row.get("tick_volume") or row.get("volume") or 0.0),
                })
            except Exception:
                continue
    rows.sort(key=lambda item: item["time"])
    return rows


def period_from_blob(blob: str) -> str:
    match = re.search(r"matrix_period=(M15|M30|H1|H2|H4)", blob)
    if match:
        return match.group(1)
    match = re.search(r"BT_PERIOD=(M15|M30|H1|H2|H4)", blob)
    if match:
        return match.group(1)
    match = re.search(r"Period</td><td>(M15|M30|H1|H2|H4)", blob)
    if match:
        return match.group(1)
    return "M15"


def dates_from_blob(blob: str):
    from_match = re.search(r"public_forced_from_date=(\d{4}\.\d{2}\.\d{2})", blob)
    to_match = re.search(r"public_forced_to_date=(\d{4}\.\d{2}\.\d{2})", blob)
    if not from_match:
        from_match = re.search(r"input_from_date=(\d{4}\.\d{2}\.\d{2})", blob)
    if not to_match:
        to_match = re.search(r"input_to_date=(\d{4}\.\d{2}\.\d{2})", blob)
    start = parse_day(from_match.group(1)) if from_match else None
    end = parse_day(to_match.group(1)) + timedelta(days=1) if to_match else None
    return start, end


def floor_bucket(t: datetime, minutes: int) -> datetime:
    total = t.hour * 60 + t.minute
    bucket = (total // minutes) * minutes
    return t.replace(hour=bucket // 60, minute=bucket % 60, second=0, microsecond=0)


def resample_bars(m1_rows, minutes: int):
    bars = []
    current_key = None
    current = None
    for row in m1_rows:
        key = floor_bucket(row["time"], minutes)
        if current_key != key:
            if current is not None:
                bars.append(current)
            current_key = key
            current = {
                "time": key,
                "open": row["open"],
                "high": row["high"],
                "low": row["low"],
                "close": row["close"],
                "volume": row["volume"],
            }
        else:
            current["high"] = max(current["high"], row["high"])
            current["low"] = min(current["low"], row["low"])
            current["close"] = row["close"]
            current["volume"] += row["volume"]
    if current is not None:
        bars.append(current)
    return bars


def ema(values, length: int):
    out = [None] * len(values)
    if not values or length <= 0:
        return out
    alpha = 2.0 / (length + 1.0)
    prev = None
    for i, value in enumerate(values):
        if prev is None:
            prev = value
        else:
            prev = alpha * value + (1.0 - alpha) * prev
        out[i] = prev
    return out


def rma(values, length: int):
    out = [None] * len(values)
    if len(values) < length or length <= 0:
        return out
    seed = sum(values[:length]) / length
    out[length - 1] = seed
    prev = seed
    for i in range(length, len(values)):
        prev = (prev * (length - 1) + values[i]) / length
        out[i] = prev
    return out


def rsi(closes, length: int):
    if len(closes) < length + 1:
        return [None] * len(closes)
    gains = [0.0]
    losses = [0.0]
    for i in range(1, len(closes)):
        change = closes[i] - closes[i - 1]
        gains.append(max(change, 0.0))
        losses.append(max(-change, 0.0))
    avg_gain = rma(gains, length)
    avg_loss = rma(losses, length)
    out = [None] * len(closes)
    for i in range(len(closes)):
        if avg_gain[i] is None or avg_loss[i] is None:
            continue
        if avg_loss[i] == 0:
            out[i] = 100.0
        else:
            rs = avg_gain[i] / avg_loss[i]
            out[i] = 100.0 - (100.0 / (1.0 + rs))
    return out


def atr(bars, length: int):
    trs = []
    prev_close = None
    for bar in bars:
        if prev_close is None:
            tr = bar["high"] - bar["low"]
        else:
            tr = max(bar["high"] - bar["low"], abs(bar["high"] - prev_close), abs(bar["low"] - prev_close))
        trs.append(tr)
        prev_close = bar["close"]
    return rma(trs, length)


def sma(values, length: int, index: int):
    if index + 1 < length:
        return None
    return sum(values[index - length + 1:index + 1]) / length


def session_ok(t: datetime) -> bool:
    return t.weekday() < 5 and 8 <= t.hour < 21


def pine_strict_backtest(root: Path, blob: str, deposit: float):
    period = period_from_blob(blob)
    minutes = PERIOD_MINUTES.get(period, 15)
    m1 = load_m1_ohlcv(root)
    if not m1:
        return {"enabled": True, "verdict": "NO_HISTORY", "period": period, "reason": "xau_public_m1.csv not found"}
    bars = resample_bars(m1, minutes)
    start, end = dates_from_blob(blob)
    closes = [bar["close"] for bar in bars]
    volumes = [bar["volume"] for bar in bars]
    fast = ema(closes, 9)
    slow = ema(closes, 21)
    trend = ema(closes, 200)
    rsis = rsi(closes, 14)
    atrs = atr(bars, 14)

    balance = deposit
    position = None
    trades = []
    signals = 0
    blocked_existing = 0

    for i in range(2, len(bars)):
        bar = bars[i]

        if position is not None and bar["time"] > position["entry_time"]:
            if position["direction"] == "BUY":
                tp_hit = bar["high"] >= position["tp"]
                sl_hit = bar["low"] <= position["sl"]
            else:
                tp_hit = bar["low"] <= position["tp"]
                sl_hit = bar["high"] >= position["sl"]

            exit_reason = None
            exit_price = None
            if tp_hit and sl_hit:
                exit_reason = "SL_CONSERVATIVE_SAME_BAR"
                exit_price = position["sl"]
            elif sl_hit:
                exit_reason = "SL"
                exit_price = position["sl"]
            elif tp_hit:
                exit_reason = "TP"
                exit_price = position["tp"]

            if exit_reason:
                points = (exit_price - position["entry"]) if position["direction"] == "BUY" else (position["entry"] - exit_price)
                profit = points * 0.01 * 100.0
                balance += profit
                trades.append({
                    **position,
                    "exit_time": bar["time"].strftime("%Y-%m-%d %H:%M:%S"),
                    "exit": round(exit_price, 5),
                    "exit_reason": exit_reason,
                    "profit_points": round(points, 3),
                    "profit_money": round(profit, 2),
                    "balance_after": round(balance, 2),
                    "hold_minutes": int((bar["time"] - position["entry_time"]).total_seconds() // 60),
                })
                position = None

        if start is not None and bar["time"] < start:
            continue
        if end is not None and bar["time"] >= end:
            continue

        needed = [fast[i], slow[i], fast[i-1], slow[i-1], trend[i], rsis[i], atrs[i]]
        if any(value is None for value in needed):
            continue
        if not session_ok(bar["time"]):
            continue
        vol_sma = sma(volumes, 20, i)
        if vol_sma is None or not (volumes[i] > vol_sma * 0.8):
            continue

        long_signal = fast[i] > slow[i] and fast[i-1] <= slow[i-1] and bar["close"] > trend[i] and 50.0 < rsis[i] < 68.0
        short_signal = fast[i] < slow[i] and fast[i-1] >= slow[i-1] and bar["close"] < trend[i] and 32.0 < rsis[i] < 50.0
        if not long_signal and not short_signal:
            continue

        signals += 1
        if position is not None:
            blocked_existing += 1
            continue

        direction = "BUY" if long_signal else "SELL"
        entry = bar["close"]
        entry_atr = atrs[i]
        if direction == "BUY":
            tp = entry + entry_atr * 2.0
            sl = entry - entry_atr * 1.5
        else:
            tp = entry - entry_atr * 2.0
            sl = entry + entry_atr * 1.5
        position = {
            "entry_time": bar["time"],
            "direction": direction,
            "entry": round(entry, 5),
            "atr": round(entry_atr, 5),
            "tp": round(tp, 5),
            "sl": round(sl, 5),
        }

    open_trade = None
    if position is not None:
        open_trade = {**position, "entry_time": position["entry_time"].strftime("%Y-%m-%d %H:%M:%S")}

    net_profit = round(balance - deposit, 2)
    wins = sum(1 for trade in trades if trade["profit_money"] > 0)
    losses = sum(1 for trade in trades if trade["profit_money"] < 0)
    verdict = "NO_SIGNAL" if signals == 0 else ("POSITIVE" if net_profit > 0 else ("NEGATIVE" if net_profit < 0 else "FLAT"))

    trade_rows = []
    for trade in trades:
        row = dict(trade)
        row["entry_time"] = trade["entry_time"].strftime("%Y-%m-%d %H:%M:%S")
        trade_rows.append(row)

    return {
        "enabled": True,
        "verdict": verdict,
        "period": period,
        "entry_price_source": "closed_bar_close",
        "signal_logic": "EMA9/EMA21 cross + EMA200 trend + RSI bounds + volume SMA20 x 0.8 + 08-21 session",
        "exit_logic": "TP=entry_close +/- ATR14*2.0, SL=entry_close +/- ATR14*1.5, TP/SL only",
        "same_bar_tp_sl_policy": "conservative_sl_first",
        "final_balance": round(balance, 2),
        "net_profit": net_profit,
        "signals": signals,
        "blocked_existing_position": blocked_existing,
        "closed_trades": len(trades),
        "open_trade": open_trade,
        "wins": wins,
        "losses": losses,
        "win_rate": round(wins / len(trades), 3) if trades else None,
        "trade_details": trade_rows,
    }


def write_pine_strict_files(root: Path, result: dict):
    (root / "PINE_STRICT_BACKTEST.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    with (root / "PINE_STRICT_TRADES.csv").open("w", encoding="utf-8", newline="") as f:
        fields = ["entry_time", "direction", "entry", "atr", "tp", "sl", "exit_time", "exit", "exit_reason", "profit_points", "profit_money", "balance_after", "hold_minutes"]
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for row in result.get("trade_details", []):
            writer.writerow(row)


def load_deals(blob: str):
    seen = set()
    deals = []
    for match in DEAL_RE.finditer(blob):
        deal_id = int(match.group("id"))
        if deal_id in seen:
            continue
        seen.add(deal_id)
        deals.append({
            "id": deal_id,
            "time": parse_time(match.group("time")),
            "side": match.group("side").lower(),
            "lot": float(match.group("lot")),
            "price": float(match.group("price")),
        })
    return sorted(deals, key=lambda item: (item["time"], item["id"]))


def pair_trades(deals):
    trades = []
    open_deal = None
    for deal in deals:
        if open_deal is None:
            open_deal = deal
            continue
        if deal["side"] != open_deal["side"]:
            direction = "SELL" if open_deal["side"] == "sell" else "BUY"
            points = (open_deal["price"] - deal["price"]) if direction == "SELL" else (deal["price"] - open_deal["price"])
            trades.append({
                "entry_time": open_deal["time"],
                "exit_time": deal["time"],
                "direction": direction,
                "entry_price": open_deal["price"],
                "exit_price": deal["price"],
                "lot": open_deal["lot"],
                "profit_points": round(points, 3),
                "hold_minutes": int((deal["time"] - open_deal["time"]).total_seconds() // 60),
            })
            open_deal = None
        else:
            open_deal = deal
    return trades


def enrich_trade(trade, bars):
    if not bars:
        return trade
    start = trade["entry_time"]
    end = trade["exit_time"]
    entry = trade["entry_price"]
    is_sell = trade["direction"] == "SELL"

    def stats(until):
        sample = [bar for bar in bars if start <= bar["time"] <= until]
        if not sample:
            return None, None
        if is_sell:
            mfe = entry - min(bar["low"] for bar in sample)
            mae = max(bar["high"] for bar in sample) - entry
        else:
            mfe = max(bar["high"] for bar in sample) - entry
            mae = entry - min(bar["low"] for bar in sample)
        return round(mfe, 3), round(mae, 3)

    mfe_exit, mae_exit = stats(end)
    mfe_12h, mae_12h = stats(start + timedelta(hours=12))
    mfe_24h, mae_24h = stats(start + timedelta(hours=24))
    capture = None
    if mfe_exit and mfe_exit > 0:
        capture = round(trade["profit_points"] / mfe_exit, 3)
    trade.update({
        "mfe_until_exit_points": mfe_exit,
        "mae_until_exit_points": mae_exit,
        "capture_ratio_until_exit": capture,
        "mfe_12h_points": mfe_12h,
        "mae_12h_points": mae_12h,
        "mfe_24h_points": mfe_24h,
        "mae_24h_points": mae_24h,
    })
    return trade


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reports_dir")
    parser.add_argument("--deposit", type=float, default=10000.0)
    args = parser.parse_args()

    root = Path(args.reports_dir)
    texts = read_all_texts(root)
    blob = "\n".join(texts.values())
    journal_lines = extract_journal_lines(texts)

    open_lines = [line for line in journal_lines if "OPEN_ENTRY" in line]
    recovery_lines = [line for line in journal_lines if "OPEN_RECOVERY" in line]
    exit_lines = [line for line in journal_lines if "_EXIT" in line or "_CLOSE" in line or "BASKET_TP" in line]
    directions = [line_direction(line) for line in open_lines]
    directions = [direction for direction in directions if direction]
    direction_switches = sum(1 for i in range(1, len(directions)) if directions[i] != directions[i - 1])

    invalid_stops = blob.count("Invalid stops")
    failed_modify = blob.count("failed modify")
    failed_orders = blob.count("failed instant buy") + blob.count("failed instant sell")
    balance = final_balance_from_blob(blob)
    net_profit = None if balance is None else round(balance - args.deposit, 2)

    bars = load_bars(root)
    trades = [enrich_trade(trade, bars) for trade in pair_trades(load_deals(blob))]
    capture_values = [trade.get("capture_ratio_until_exit") for trade in trades if trade.get("capture_ratio_until_exit") is not None]
    avg_capture = round(sum(capture_values) / len(capture_values), 3) if capture_values else None

    pine_strict = pine_strict_backtest(root, blob, args.deposit)
    write_pine_strict_files(root, pine_strict)

    verdict = "UNKNOWN"
    reasons = []
    if not journal_lines:
        verdict = "NO_JOURNAL"
        reasons.append("No CSV journal was found in reports.")
    elif invalid_stops > 50 or failed_modify > 50 or failed_orders > 100:
        verdict = "EXECUTION_QUALITY_FAIL"
        reasons.append(f"Execution noise too high: invalid_stops={invalid_stops}, failed_modify={failed_modify}, failed_orders={failed_orders}.")
    elif len(open_lines) == 0:
        verdict = "NO_ENTRY"
        reasons.append("No OPEN_ENTRY found.")
    elif len(open_lines) > 75:
        verdict = "TOO_MANY_ENTRIES"
        reasons.append(f"Controlled intraday profile expected <=75 entries, got {len(open_lines)}.")
    elif balance is None:
        verdict = "NO_BALANCE"
        reasons.append("No final balance found.")
    elif balance < args.deposit:
        verdict = "NEGATIVE_RESULT"
        reasons.append(f"Final balance {balance:.2f} below deposit {args.deposit:.2f}.")
    elif balance == args.deposit:
        verdict = "FLAT_RESULT"
        reasons.append(f"Final balance {balance:.2f} equals deposit {args.deposit:.2f}; no positive edge confirmed.")
    else:
        verdict = "CLEAN_INTRADAY_PASS"
        reasons.append(f"Intraday validation passed with {len(open_lines)} entry/entries and net profit {net_profit:.2f}.")

    result = {
        "verdict": verdict,
        "final_balance": balance,
        "net_profit": net_profit,
        "pine_strict_clone": pine_strict,
        "open_entries": len(open_lines),
        "target_entries_per_day": "2-3",
        "focus_sessions": "London + New York",
        "recovery_entries": len(recovery_lines),
        "exit_events": len(exit_lines),
        "directions": directions,
        "direction_switches": direction_switches,
        "first_entry_time": first_timestamp(open_lines[0]) if open_lines else None,
        "last_entry_time": first_timestamp(open_lines[-1]) if open_lines else None,
        "invalid_stops": invalid_stops,
        "failed_modify": failed_modify,
        "failed_orders": failed_orders,
        "average_capture_ratio_until_exit": avg_capture,
        "trade_details": [
            {
                **trade,
                "entry_time": trade["entry_time"].strftime("%Y-%m-%d %H:%M:%S"),
                "exit_time": trade["exit_time"].strftime("%Y-%m-%d %H:%M:%S"),
            }
            for trade in trades
        ],
        "journal_lines": len(journal_lines),
        "files_scanned": len(texts),
        "reasons": reasons,
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
