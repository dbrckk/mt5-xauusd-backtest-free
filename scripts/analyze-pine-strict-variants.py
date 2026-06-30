import argparse
import csv
import json
import re
from datetime import datetime, timedelta
from pathlib import Path

PERIOD_MINUTES = {"M15": 15, "M30": 30, "H1": 60, "H2": 120, "H4": 240}
TP_VALUES = [1.5, 1.8, 2.0, 2.2, 2.5, 3.0]
SL_VALUES = [0.8, 1.0, 1.2, 1.5, 1.8, 2.0]


def parse_day(value: str) -> datetime:
    return datetime.strptime(value, "%Y.%m.%d")


def decode_text(data: bytes) -> str:
    for enc in ("utf-8", "utf-16", "utf-16le", "cp1252", "latin1"):
        try:
            return data.decode(enc, errors="replace")
        except Exception:
            continue
    return data.decode("utf-8", errors="replace")


def read_blob(root: Path) -> str:
    parts = []
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in {".txt", ".log", ".json", ".html", ".htm", ".csv", ".set", ".ini"}:
            try:
                parts.append(decode_text(path.read_bytes()))
            except Exception:
                pass
    return "\n".join(parts)


def find_file(root: Path, name: str) -> Path | None:
    matches = list(root.rglob(name))
    return matches[0] if matches else None


def load_m1(root: Path):
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
    rows.sort(key=lambda x: x["time"])
    return rows


def period_from_blob(blob: str) -> str:
    for pattern in (r"matrix_period=(M15|M30|H1|H2|H4)", r"BT_PERIOD=(M15|M30|H1|H2|H4)", r"Period</td><td>(M15|M30|H1|H2|H4)"):
        match = re.search(pattern, blob)
        if match:
            return match.group(1)
    return "M15"


def dates_from_blob(blob: str):
    fm = re.search(r"public_forced_from_date=(\d{4}\.\d{2}\.\d{2})", blob) or re.search(r"input_from_date=(\d{4}\.\d{2}\.\d{2})", blob)
    tm = re.search(r"public_forced_to_date=(\d{4}\.\d{2}\.\d{2})", blob) or re.search(r"input_to_date=(\d{4}\.\d{2}\.\d{2})", blob)
    start = parse_day(fm.group(1)) if fm else None
    end = parse_day(tm.group(1)) + timedelta(days=1) if tm else None
    return start, end


def floor_bucket(t: datetime, minutes: int) -> datetime:
    total = t.hour * 60 + t.minute
    bucket = (total // minutes) * minutes
    return t.replace(hour=bucket // 60, minute=bucket % 60, second=0, microsecond=0)


def resample(rows, minutes: int):
    out = []
    key = None
    cur = None
    for row in rows:
        k = floor_bucket(row["time"], minutes)
        if k != key:
            if cur:
                out.append(cur)
            key = k
            cur = {"time": k, "open": row["open"], "high": row["high"], "low": row["low"], "close": row["close"], "volume": row["volume"]}
        else:
            cur["high"] = max(cur["high"], row["high"])
            cur["low"] = min(cur["low"], row["low"])
            cur["close"] = row["close"]
            cur["volume"] += row["volume"]
    if cur:
        out.append(cur)
    return out


def ema(values, n):
    out = [None] * len(values)
    a = 2.0 / (n + 1.0)
    prev = None
    for i, v in enumerate(values):
        prev = v if prev is None else a * v + (1.0 - a) * prev
        out[i] = prev
    return out


def rma(values, n):
    out = [None] * len(values)
    if len(values) < n:
        return out
    prev = sum(values[:n]) / n
    out[n - 1] = prev
    for i in range(n, len(values)):
        prev = (prev * (n - 1) + values[i]) / n
        out[i] = prev
    return out


def rsi(closes, n):
    gains = [0.0]
    losses = [0.0]
    for i in range(1, len(closes)):
        c = closes[i] - closes[i - 1]
        gains.append(max(c, 0.0))
        losses.append(max(-c, 0.0))
    ag = rma(gains, n)
    al = rma(losses, n)
    out = [None] * len(closes)
    for i in range(len(closes)):
        if ag[i] is None or al[i] is None:
            continue
        out[i] = 100.0 if al[i] == 0 else 100.0 - 100.0 / (1.0 + ag[i] / al[i])
    return out


def atr(bars, n):
    trs = []
    prev = None
    for b in bars:
        tr = b["high"] - b["low"] if prev is None else max(b["high"] - b["low"], abs(b["high"] - prev), abs(b["low"] - prev))
        trs.append(tr)
        prev = b["close"]
    return rma(trs, n)


def sma(values, n, i):
    if i + 1 < n:
        return None
    return sum(values[i - n + 1:i + 1]) / n


def session_ok(t: datetime) -> bool:
    return t.weekday() < 5 and 8 <= t.hour < 21


def build_signals(bars, start, end):
    closes = [b["close"] for b in bars]
    volumes = [b["volume"] for b in bars]
    fast = ema(closes, 9)
    slow = ema(closes, 21)
    trend = ema(closes, 200)
    rsis = rsi(closes, 14)
    atrs = atr(bars, 14)
    signals = []
    for i in range(2, len(bars)):
        b = bars[i]
        if start and b["time"] < start:
            continue
        if end and b["time"] >= end:
            continue
        needed = [fast[i], slow[i], fast[i - 1], slow[i - 1], trend[i], rsis[i], atrs[i]]
        if any(v is None for v in needed):
            continue
        if not session_ok(b["time"]):
            continue
        vol_sma = sma(volumes, 20, i)
        if vol_sma is None or volumes[i] <= vol_sma * 0.8:
            continue
        long_sig = fast[i] > slow[i] and fast[i - 1] <= slow[i - 1] and b["close"] > trend[i] and 50.0 < rsis[i] < 68.0
        short_sig = fast[i] < slow[i] and fast[i - 1] >= slow[i - 1] and b["close"] < trend[i] and 32.0 < rsis[i] < 50.0
        if long_sig or short_sig:
            signals.append({"index": i, "time": b["time"], "direction": "BUY" if long_sig else "SELL", "entry": b["close"], "atr": atrs[i]})
    return signals


def simulate_variant(bars, signals, deposit, tp_mult, sl_mult):
    balance = deposit
    trades = []
    pos = None
    sig_by_index = {s["index"]: s for s in signals}
    blocked = 0
    for i, b in enumerate(bars):
        if pos and b["time"] > pos["entry_time"]:
            if pos["direction"] == "BUY":
                tp_hit = b["high"] >= pos["tp"]
                sl_hit = b["low"] <= pos["sl"]
            else:
                tp_hit = b["low"] <= pos["tp"]
                sl_hit = b["high"] >= pos["sl"]
            reason = None
            price = None
            if tp_hit and sl_hit:
                reason, price = "SL_CONSERVATIVE_SAME_BAR", pos["sl"]
            elif sl_hit:
                reason, price = "SL", pos["sl"]
            elif tp_hit:
                reason, price = "TP", pos["tp"]
            if reason:
                points = price - pos["entry"] if pos["direction"] == "BUY" else pos["entry"] - price
                profit = points * 0.01 * 100.0
                balance += profit
                trades.append({**pos, "exit_time": b["time"], "exit": price, "exit_reason": reason, "profit_points": points, "profit_money": profit, "balance_after": balance, "hold_minutes": int((b["time"] - pos["entry_time"]).total_seconds() // 60)})
                pos = None
        sig = sig_by_index.get(i)
        if not sig:
            continue
        if pos:
            blocked += 1
            continue
        entry = sig["entry"]
        a = sig["atr"]
        if sig["direction"] == "BUY":
            tp = entry + a * tp_mult
            sl = entry - a * sl_mult
        else:
            tp = entry - a * tp_mult
            sl = entry + a * sl_mult
        pos = {"entry_time": sig["time"], "direction": sig["direction"], "entry": entry, "atr": a, "tp": tp, "sl": sl}
    net = round(balance - deposit, 2)
    wins = sum(1 for t in trades if t["profit_money"] > 0)
    losses = sum(1 for t in trades if t["profit_money"] < 0)
    avg_hold = round(sum(t["hold_minutes"] for t in trades) / len(trades), 1) if trades else None
    return {
        "tp_atr": tp_mult,
        "sl_atr": sl_mult,
        "final_balance": round(balance, 2),
        "net_profit": net,
        "signals": len(signals),
        "closed_trades": len(trades),
        "open_trade": bool(pos),
        "blocked_existing_position": blocked,
        "wins": wins,
        "losses": losses,
        "win_rate": round(wins / len(trades), 3) if trades else None,
        "avg_hold_minutes": avg_hold,
        "trades": trades,
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("reports_dir")
    p.add_argument("--deposit", type=float, default=10000.0)
    args = p.parse_args()
    root = Path(args.reports_dir)
    blob = read_blob(root)
    period = period_from_blob(blob)
    start, end = dates_from_blob(blob)
    m1 = load_m1(root)
    if not m1:
        result = {"verdict": "NO_HISTORY", "period": period, "reason": "xau_public_m1.csv not found"}
        (root / "PINE_STRICT_VARIANTS.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps(result, indent=2))
        return 0
    bars = resample(m1, PERIOD_MINUTES.get(period, 15))
    signals = build_signals(bars, start, end)
    variants = [simulate_variant(bars, signals, args.deposit, tp, sl) for tp in TP_VALUES for sl in SL_VALUES]
    variants.sort(key=lambda x: (x["net_profit"], x["closed_trades"], x["win_rate"] or 0), reverse=True)
    best = variants[0] if variants else None
    result = {
        "verdict": "DONE",
        "period": period,
        "range_start": start.strftime("%Y-%m-%d") if start else None,
        "range_end_exclusive": end.strftime("%Y-%m-%d") if end else None,
        "entry_price_source": "closed_bar_close",
        "signal_logic": "same Pine strict signal; only TP/SL ATR multipliers vary",
        "same_bar_tp_sl_policy": "conservative_sl_first",
        "variant_count": len(variants),
        "best_variant": {k: v for k, v in best.items() if k != "trades"} if best else None,
        "top_10": [{k: v for k, v in item.items() if k != "trades"} for item in variants[:10]],
    }
    (root / "PINE_STRICT_VARIANTS.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    if best:
        (root / "PINE_STRICT_BEST_VARIANT_TRADES.json").write_text(json.dumps(best["trades"], indent=2, default=str, ensure_ascii=False), encoding="utf-8")
    with (root / "PINE_STRICT_VARIANTS.csv").open("w", encoding="utf-8", newline="") as f:
        fields = ["rank", "tp_atr", "sl_atr", "net_profit", "final_balance", "signals", "closed_trades", "wins", "losses", "win_rate", "open_trade", "avg_hold_minutes", "blocked_existing_position"]
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for rank, item in enumerate(variants, 1):
            writer.writerow({"rank": rank, **{k: item.get(k) for k in fields if k != "rank"}})
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
