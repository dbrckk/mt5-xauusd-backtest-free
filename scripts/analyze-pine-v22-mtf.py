import argparse
import csv
import json
import math
import re
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

TF_MINUTES = {"M5": 5, "M15": 15, "M30": 30, "H1": 60, "H2": 120, "H4": 240}
TF_RANK = {"M5": 1, "M15": 2, "M30": 3, "H1": 4, "H2": 5, "H4": 6}
TEXT_EXTENSIONS = {".txt", ".log", ".json", ".html", ".htm", ".csv", ".set", ".ini"}

PROFILES = {
    "high_winrate": {"tp": 1.5, "sl": 2.0, "min_score": 84.0, "max_trades_day": 4, "cooldown_min": 90, "be": True, "be_trigger": 0.90, "be_offset": 0.05, "time_stop": True, "max_hold_m5_bars": 18},
    "validated_h1_profit": {"tp": 2.5, "sl": 2.0, "min_score": 78.0, "max_trades_day": 4, "cooldown_min": 90, "be": True, "be_trigger": 0.90, "be_offset": 0.05, "time_stop": True, "max_hold_m5_bars": 18},
    "ultra_selective": {"tp": 1.4, "sl": 2.1, "min_score": 90.0, "max_trades_day": 3, "cooldown_min": 120, "be": True, "be_trigger": 0.80, "be_offset": 0.05, "time_stop": True, "max_hold_m5_bars": 18},
}

PARAMS = {
    "fast_len": 9,
    "slow_len": 21,
    "trend_len": 200,
    "rsi_len": 14,
    "atr_len": 14,
    "vol_len": 20,
    "vol_mult": 0.80,
    "adx_len": 14,
    "adx_smoothing": 14,
    "min_adx": 18.0,
    "min_body_ratio": 0.36,
    "min_atr_pct": 0.035,
    "max_atr_pct": 0.60,
    "long_rsi_min": 52.0,
    "long_rsi_max": 66.0,
    "short_rsi_min": 34.0,
    "short_rsi_max": 48.0,
}


def decode_text(data: bytes) -> str:
    best = None
    for enc in ("utf-8", "utf-16", "utf-16le", "cp1252", "latin1"):
        try:
            text = data.decode(enc, errors="replace")
            score = text[:2000].count("\x00")
            cand = (score, -len(text), text)
            best = cand if best is None or cand < best else best
        except Exception:
            pass
    return best[2] if best else data.decode("utf-8", errors="replace")


def read_blob(root: Path) -> str:
    parts = []
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in TEXT_EXTENSIONS:
            try:
                parts.append(decode_text(path.read_bytes()))
            except Exception:
                pass
    return "\n".join(parts)


def find_file(root: Path, name: str) -> Path | None:
    matches = list(root.rglob(name))
    return matches[0] if matches else None


def parse_day(value: str) -> datetime:
    return datetime.strptime(value, "%Y.%m.%d")


def dates_from_blob(blob: str):
    fm = re.search(r"public_forced_from_date=(\d{4}\.\d{2}\.\d{2})", blob) or re.search(r"input_from_date=(\d{4}\.\d{2}\.\d{2})", blob)
    tm = re.search(r"public_forced_to_date=(\d{4}\.\d{2}\.\d{2})", blob) or re.search(r"input_to_date=(\d{4}\.\d{2}\.\d{2})", blob)
    start = parse_day(fm.group(1)) if fm else None
    end = parse_day(tm.group(1)) + timedelta(days=1) if tm else None
    return start, end


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
    rows.sort(key=lambda item: item["time"])
    return rows


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
    if not values or n <= 0:
        return out
    alpha = 2.0 / (n + 1.0)
    prev = None
    for i, value in enumerate(values):
        prev = value if prev is None else alpha * value + (1.0 - alpha) * prev
        out[i] = prev
    return out


def rma(values, n):
    out = [None] * len(values)
    if n <= 0 or len(values) < n:
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
        chg = closes[i] - closes[i - 1]
        gains.append(max(chg, 0.0))
        losses.append(max(-chg, 0.0))
    ag = rma(gains, n)
    al = rma(losses, n)
    out = [None] * len(closes)
    for i in range(len(closes)):
        if ag[i] is None or al[i] is None:
            continue
        out[i] = 100.0 if al[i] == 0 else 100.0 - 100.0 / (1.0 + ag[i] / al[i])
    return out


def true_range_series(bars):
    out = []
    prev_close = None
    for bar in bars:
        if prev_close is None:
            tr = bar["high"] - bar["low"]
        else:
            tr = max(bar["high"] - bar["low"], abs(bar["high"] - prev_close), abs(bar["low"] - prev_close))
        out.append(tr)
        prev_close = bar["close"]
    return out


def atr(bars, n):
    return rma(true_range_series(bars), n)


def dmi_adx(bars, di_len, adx_len):
    plus_dm = [0.0]
    minus_dm = [0.0]
    tr = true_range_series(bars)
    for i in range(1, len(bars)):
        up = bars[i]["high"] - bars[i - 1]["high"]
        down = bars[i - 1]["low"] - bars[i]["low"]
        plus_dm.append(up if up > down and up > 0 else 0.0)
        minus_dm.append(down if down > up and down > 0 else 0.0)
    sm_tr = rma(tr, di_len)
    sm_plus = rma(plus_dm, di_len)
    sm_minus = rma(minus_dm, di_len)
    di_plus = [None] * len(bars)
    di_minus = [None] * len(bars)
    dx = [0.0] * len(bars)
    for i in range(len(bars)):
        if sm_tr[i] is None or sm_tr[i] == 0 or sm_plus[i] is None or sm_minus[i] is None:
            continue
        di_plus[i] = 100.0 * sm_plus[i] / sm_tr[i]
        di_minus[i] = 100.0 * sm_minus[i] / sm_tr[i]
        denom = di_plus[i] + di_minus[i]
        dx[i] = 0.0 if denom == 0 else 100.0 * abs(di_plus[i] - di_minus[i]) / denom
    adx = rma(dx, adx_len)
    return di_plus, di_minus, adx


def sma_at(values, n, i):
    if i + 1 < n:
        return None
    return sum(values[i - n + 1:i + 1]) / n


def highest(values, start, end):
    sample = values[max(start, 0):max(end, 0)]
    return max(sample) if sample else None


def lowest(values, start, end):
    sample = values[max(start, 0):max(end, 0)]
    return min(sample) if sample else None


def session_ok(t: datetime) -> bool:
    weekday = t.weekday() < 5
    in_hour = 8 <= t.hour < 21
    not_late_friday = t.weekday() != 4 or t.hour < 16
    return weekday and in_hour and not_late_friday


def analyze_tf(tf_name, bars, profile):
    p = PARAMS
    closes = [b["close"] for b in bars]
    highs = [b["high"] for b in bars]
    lows = [b["low"] for b in bars]
    volumes = [b["volume"] for b in bars]
    fast = ema(closes, p["fast_len"])
    slow = ema(closes, p["slow_len"])
    trend = ema(closes, p["trend_len"])
    rsis = rsi(closes, p["rsi_len"])
    atrs = atr(bars, p["atr_len"])
    di_plus, di_minus, adx = dmi_adx(bars, p["adx_len"], p["adx_smoothing"])
    out = []
    tf_minutes = TF_MINUTES[tf_name]
    for i in range(3, len(bars)):
        needed = [fast[i], fast[i - 1], slow[i], slow[i - 1], trend[i], trend[i - 3], rsis[i], atrs[i], di_plus[i], di_minus[i], adx[i]]
        if any(v is None for v in needed):
            continue
        bar = bars[i]
        if not session_ok(bar["time"]):
            continue
        vol_sma = sma_at(volumes, p["vol_len"], i)
        if vol_sma is None:
            continue
        rng = bar["high"] - bar["low"]
        body = abs(bar["close"] - bar["open"])
        body_ok = rng > 0 and body / rng >= p["min_body_ratio"]
        atr_pct = atrs[i] / bar["close"] * 100.0 if bar["close"] else 0.0
        atr_ok = p["min_atr_pct"] <= atr_pct <= p["max_atr_pct"]
        vol_ok = bar["volume"] > vol_sma * p["vol_mult"]
        candle_long = bar["close"] > bar["open"] and bar["close"] > (bar["high"] + bar["low"]) / 2.0
        candle_short = bar["close"] < bar["open"] and bar["close"] < (bar["high"] + bar["low"]) / 2.0
        long_cross = fast[i] > slow[i] and fast[i - 1] <= slow[i - 1]
        short_cross = fast[i] < slow[i] and fast[i - 1] >= slow[i - 1]
        long_trend = bar["close"] > trend[i] and trend[i] - trend[i - 3] > 0
        short_trend = bar["close"] < trend[i] and trend[i] - trend[i - 3] < 0
        long_rsi = p["long_rsi_min"] < rsis[i] < p["long_rsi_max"]
        short_rsi = p["short_rsi_min"] < rsis[i] < p["short_rsi_max"]
        hi3 = highest(highs, i - 3, i)
        lo3 = lowest(lows, i - 3, i)
        long_structure = bar["close"] > bars[i - 1]["high"] or (hi3 is not None and bar["close"] > hi3)
        short_structure = bar["close"] < bars[i - 1]["low"] or (lo3 is not None and bar["close"] < lo3)
        long_di = di_plus[i] > di_minus[i]
        short_di = di_minus[i] > di_plus[i]
        long_score = 0.0
        long_score += 20.0 if long_cross else 0.0
        long_score += 18.0 if long_trend else 0.0
        long_score += 14.0 if long_rsi else 0.0
        long_score += 9.0 if vol_ok else 0.0
        long_score += 9.0 if adx[i] >= p["min_adx"] else 0.0
        long_score += 7.0 if long_di else 0.0
        long_score += 7.0 if body_ok else 0.0
        long_score += 6.0 if candle_long else 0.0
        long_score += 5.0 if atr_ok else 0.0
        long_score += 5.0 if long_structure else 0.0
        short_score = 0.0
        short_score += 20.0 if short_cross else 0.0
        short_score += 18.0 if short_trend else 0.0
        short_score += 14.0 if short_rsi else 0.0
        short_score += 9.0 if vol_ok else 0.0
        short_score += 9.0 if adx[i] >= p["min_adx"] else 0.0
        short_score += 7.0 if short_di else 0.0
        short_score += 7.0 if body_ok else 0.0
        short_score += 6.0 if candle_short else 0.0
        short_score += 5.0 if atr_ok else 0.0
        short_score += 5.0 if short_structure else 0.0
        long_ok = long_cross and long_trend and long_rsi and vol_ok and adx[i] >= p["min_adx"] and body_ok and atr_ok and long_di and long_score >= profile["min_score"]
        short_ok = short_cross and short_trend and short_rsi and vol_ok and adx[i] >= p["min_adx"] and body_ok and atr_ok and short_di and short_score >= profile["min_score"]
        if not long_ok and not short_ok:
            continue
        direction = "BUY" if long_ok else "SELL"
        score = long_score if long_ok else short_score
        # On a 5m execution chart, an HTF signal is tradable on the final 5m bar of that HTF candle.
        event_time = bar["time"] + timedelta(minutes=tf_minutes - 5)
        out.append({
            "tf": tf_name,
            "tf_rank": TF_RANK[tf_name],
            "source_time": bar["time"],
            "event_time": event_time,
            "direction": direction,
            "entry": bar["close"],
            "atr": atrs[i],
            "score": round(score, 3),
            "rsi": round(rsis[i], 3),
            "adx": round(adx[i], 3),
            "atr_pct": round(atr_pct, 5),
        })
    return out


def build_signal_events(m1_rows, start, end, profile):
    signals = []
    for tf, minutes in TF_MINUTES.items():
        bars = resample(m1_rows, minutes)
        tf_signals = analyze_tf(tf, bars, profile)
        for sig in tf_signals:
            if start and sig["event_time"] < start:
                continue
            if end and sig["event_time"] >= end:
                continue
            signals.append(sig)
    return sorted(signals, key=lambda s: (s["event_time"], -s["score"], -s["tf_rank"]))


def max_drawdown_from_balances(balances):
    peak = balances[0] if balances else 0.0
    max_dd = 0.0
    for b in balances:
        peak = max(peak, b)
        max_dd = min(max_dd, b - peak)
    return round(max_dd, 2)


def simulate_profile(m1_rows, start, end, deposit, profile_name, profile):
    m5 = resample(m1_rows, 5)
    if start:
        m5 = [b for b in m5 if b["time"] >= start]
    if end:
        m5 = [b for b in m5 if b["time"] < end]
    if not m5:
        return {"profile": profile_name, "verdict": "NO_M5_BARS"}
    signals = build_signal_events(m1_rows, start, end, profile)
    event_map = defaultdict(list)
    for sig in signals:
        event_map[sig["event_time"]].append(sig)
    balance = deposit
    balances = [deposit]
    trades = []
    position = None
    trades_today = 0
    day_key = None
    last_entry_time = None
    blocked = {"cooldown": 0, "daily_limit": 0, "existing_position": 0}
    signal_counts_by_tf = defaultdict(int)
    entry_counts_by_tf = defaultdict(int)
    for i, bar in enumerate(m5):
        current_day = bar["time"].strftime("%Y%m%d")
        if current_day != day_key:
            day_key = current_day
            trades_today = 0
        if position is not None:
            if position["direction"] == "BUY":
                base_stop = position["entry"] - position["atr"] * profile["sl"]
                tp = position["entry"] + position["atr"] * profile["tp"]
                be_active = profile["be"] and bar["high"] >= position["entry"] + position["atr"] * profile["be_trigger"]
                stop = max(base_stop, position["entry"] + position["atr"] * profile["be_offset"]) if be_active else base_stop
                tp_hit = bar["high"] >= tp
                sl_hit = bar["low"] <= stop
            else:
                base_stop = position["entry"] + position["atr"] * profile["sl"]
                tp = position["entry"] - position["atr"] * profile["tp"]
                be_active = profile["be"] and bar["low"] <= position["entry"] - position["atr"] * profile["be_trigger"]
                stop = min(base_stop, position["entry"] - position["atr"] * profile["be_offset"]) if be_active else base_stop
                tp_hit = bar["low"] <= tp
                sl_hit = bar["high"] >= stop
            reason = None
            exit_price = None
            if tp_hit and sl_hit:
                reason, exit_price = "SL_CONSERVATIVE_SAME_BAR", stop
            elif sl_hit:
                reason, exit_price = "SL", stop
            elif tp_hit:
                reason, exit_price = "TP", tp
            else:
                hold_bars = i - position["entry_bar"]
                if profile["time_stop"] and hold_bars >= profile["max_hold_m5_bars"]:
                    if position["direction"] == "BUY" and bar["close"] > position["entry"]:
                        reason, exit_price = "TIME_PROFIT_EXIT", bar["close"]
                    elif position["direction"] == "SELL" and bar["close"] < position["entry"]:
                        reason, exit_price = "TIME_PROFIT_EXIT", bar["close"]
            if reason:
                points = exit_price - position["entry"] if position["direction"] == "BUY" else position["entry"] - exit_price
                profit = points * 0.01 * 100.0
                balance += profit
                balances.append(balance)
                trade = {**position}
                trade.update({
                    "exit_time": bar["time"],
                    "exit": round(exit_price, 5),
                    "exit_reason": reason,
                    "profit_points": round(points, 3),
                    "profit_money": round(profit, 2),
                    "balance_after": round(balance, 2),
                    "hold_minutes": int((bar["time"] - position["entry_time"]).total_seconds() // 60),
                })
                trades.append(trade)
                position = None
        candidates = event_map.get(bar["time"], [])
        if not candidates:
            continue
        for sig in candidates:
            signal_counts_by_tf[sig["tf"]] += 1
        candidates = sorted(candidates, key=lambda s: (s["score"], s["tf_rank"]), reverse=True)
        selected = candidates[0]
        if position is not None:
            blocked["existing_position"] += len(candidates)
            continue
        if trades_today >= profile["max_trades_day"]:
            blocked["daily_limit"] += len(candidates)
            continue
        if last_entry_time is not None and (bar["time"] - last_entry_time).total_seconds() < profile["cooldown_min"] * 60:
            blocked["cooldown"] += len(candidates)
            continue
        position = {
            "entry_time": bar["time"],
            "entry_bar": i,
            "source_time": selected["source_time"],
            "tf": selected["tf"],
            "direction": selected["direction"],
            "entry": round(selected["entry"], 5),
            "atr": round(selected["atr"], 5),
            "score": selected["score"],
            "rsi": selected["rsi"],
            "adx": selected["adx"],
        }
        trades_today += 1
        last_entry_time = bar["time"]
        entry_counts_by_tf[selected["tf"]] += 1
    open_trade = None
    if position is not None:
        open_trade = {k: (v.strftime("%Y-%m-%d %H:%M:%S") if isinstance(v, datetime) else v) for k, v in position.items() if k != "entry_bar"}
    wins = sum(1 for t in trades if t["profit_money"] > 0)
    losses = sum(1 for t in trades if t["profit_money"] < 0)
    gross_profit = sum(t["profit_money"] for t in trades if t["profit_money"] > 0)
    gross_loss = sum(t["profit_money"] for t in trades if t["profit_money"] < 0)
    net = round(balance - deposit, 2)
    trade_days = len(set(t["entry_time"].strftime("%Y-%m-%d") for t in trades))
    result_trades = []
    for t in trades:
        row = {k: v for k, v in t.items() if k != "entry_bar"}
        row["entry_time"] = t["entry_time"].strftime("%Y-%m-%d %H:%M:%S")
        row["source_time"] = t["source_time"].strftime("%Y-%m-%d %H:%M:%S")
        row["exit_time"] = t["exit_time"].strftime("%Y-%m-%d %H:%M:%S")
        result_trades.append(row)
    verdict = "POSITIVE" if net > 0 else "NEGATIVE" if net < 0 else "FLAT"
    return {
        "profile": profile_name,
        "verdict": verdict,
        "tp_atr": profile["tp"],
        "sl_atr": profile["sl"],
        "min_score": profile["min_score"],
        "final_balance": round(balance, 2),
        "net_profit": net,
        "closed_trades": len(trades),
        "open_trade": open_trade,
        "wins": wins,
        "losses": losses,
        "win_rate": round(wins / len(trades), 3) if trades else None,
        "gross_profit": round(gross_profit, 2),
        "gross_loss": round(gross_loss, 2),
        "profit_factor": round(gross_profit / abs(gross_loss), 3) if gross_loss else None,
        "max_closed_drawdown_money": max_drawdown_from_balances(balances),
        "avg_hold_minutes": round(sum(t["hold_minutes"] for t in trades) / len(trades), 1) if trades else None,
        "trade_days": trade_days,
        "avg_trades_per_trade_day": round(len(trades) / trade_days, 2) if trade_days else None,
        "signals_by_tf": dict(sorted(signal_counts_by_tf.items(), key=lambda kv: TF_RANK[kv[0]])),
        "entries_by_tf": dict(sorted(entry_counts_by_tf.items(), key=lambda kv: TF_RANK[kv[0]])),
        "blocked_signals": blocked,
        "trades": result_trades,
    }


def write_outputs(root: Path, results):
    summary = {k: ({kk: vv for kk, vv in v.items() if kk != "trades"}) for k, v in results.items()}
    ranked = sorted(summary.values(), key=lambda x: (x.get("win_rate") or 0.0, x.get("net_profit") or 0.0, -(x.get("closed_trades") or 0)), reverse=True)
    final = {
        "verdict": "DONE",
        "engine": "XAUUSD_Master_V22_MTF_HighWinrate_Strategy_python_clone",
        "selection_priority": "highest win_rate, then net_profit, then fewer trades",
        "best_by_winrate": ranked[0] if ranked else None,
        "profiles": summary,
    }
    (root / "PINE_V22_MTF_BACKTEST.json").write_text(json.dumps(final, indent=2, ensure_ascii=False), encoding="utf-8")
    for name, result in results.items():
        with (root / f"PINE_V22_MTF_TRADES_{name}.csv").open("w", encoding="utf-8", newline="") as f:
            fields = ["entry_time", "source_time", "tf", "direction", "entry", "atr", "score", "rsi", "adx", "exit_time", "exit", "exit_reason", "profit_points", "profit_money", "balance_after", "hold_minutes"]
            writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
            writer.writeheader()
            for row in result.get("trades", []):
                writer.writerow(row)
    print(json.dumps(final, indent=2, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("reports_dir")
    parser.add_argument("--deposit", type=float, default=10000.0)
    args = parser.parse_args()
    root = Path(args.reports_dir)
    blob = read_blob(root)
    start, end = dates_from_blob(blob)
    m1_rows = load_m1(root)
    if not m1_rows:
        result = {"verdict": "NO_HISTORY", "reason": "xau_public_m1.csv not found"}
        (root / "PINE_V22_MTF_BACKTEST.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps(result, indent=2))
        return 0
    results = {name: simulate_profile(m1_rows, start, end, args.deposit, name, profile) for name, profile in PROFILES.items()}
    write_outputs(root, results)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
