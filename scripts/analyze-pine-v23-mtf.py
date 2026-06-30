import argparse
import csv
import json
import re
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

TEXT_EXTENSIONS = {".txt", ".log", ".json", ".html", ".htm", ".csv", ".set", ".ini"}
TF_MINUTES = {"M5": 5, "M15": 15, "M30": 30, "H1": 60, "H2": 120, "H4": 240}

PARAMS = {
    "fast_len": 9,
    "slow_len": 21,
    "trend_len": 200,
    "rsi_len": 14,
    "atr_len": 14,
    "vol_len": 20,
    "vol_mult": 0.85,
    "di_len": 14,
    "adx_smooth": 14,
    "min_adx": 18.0,
    "min_body_ratio": 0.38,
    "min_atr_pct": 0.035,
    "max_atr_pct": 0.34,
    "long_rsi_min": 51.0,
    "long_rsi_max": 64.0,
    "short_rsi_min": 36.0,
    "short_rsi_max": 49.0,
}

PROFILES = {
    "v23_balanced": {
        "tp": 1.60, "sl": 0.90, "min_score": 82.0, "min_confirm": 3,
        "max_trades_day": 4, "cooldown_min": 90, "be": True,
        "be_trigger": 1.15, "be_offset": 0.03, "time_stop": True,
        "max_hold_m5_bars": 24, "weakness_exit": True, "weakness_bars": 12,
        "require_h1": True, "block_h2_opp": True, "block_h4_opp": True,
    },
    "v23_high_winrate": {
        "tp": 1.25, "sl": 0.75, "min_score": 88.0, "min_confirm": 3,
        "max_trades_day": 4, "cooldown_min": 90, "be": True,
        "be_trigger": 1.00, "be_offset": 0.03, "time_stop": True,
        "max_hold_m5_bars": 24, "weakness_exit": True, "weakness_bars": 12,
        "require_h1": True, "block_h2_opp": True, "block_h4_opp": True,
    },
    "v23_expectancy": {
        "tp": 2.00, "sl": 1.00, "min_score": 84.0, "min_confirm": 2,
        "max_trades_day": 4, "cooldown_min": 90, "be": False,
        "be_trigger": 1.35, "be_offset": 0.03, "time_stop": True,
        "max_hold_m5_bars": 30, "weakness_exit": True, "weakness_bars": 14,
        "require_h1": True, "block_h2_opp": True, "block_h4_opp": True,
    },
    "v23_m5_h1_clean": {
        "tp": 1.80, "sl": 0.85, "min_score": 86.0, "min_confirm": 2,
        "max_trades_day": 3, "cooldown_min": 120, "be": False,
        "be_trigger": 1.25, "be_offset": 0.03, "time_stop": True,
        "max_hold_m5_bars": 30, "weakness_exit": True, "weakness_bars": 14,
        "require_h1": True, "block_h2_opp": True, "block_h4_opp": True,
    },
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


def session_ok(t: datetime) -> bool:
    return t.weekday() < 5 and 8 <= t.hour < 18 and (t.weekday() != 4 or t.hour < 16)


def max_drawdown(balances):
    peak = balances[0] if balances else 0.0
    dd = 0.0
    for value in balances:
        peak = max(peak, value)
        dd = min(dd, value - peak)
    return round(dd, 2)


def tf_state_series(bars, tf_minutes):
    p = PARAMS
    closes = [b["close"] for b in bars]
    fast = ema(closes, p["fast_len"])
    slow = ema(closes, p["slow_len"])
    trend = ema(closes, p["trend_len"])
    rsis = rsi(closes, p["rsi_len"])
    di_plus, di_minus, adx = dmi_adx(bars, p["di_len"], p["adx_smooth"])
    states = {}
    for i in range(3, len(bars)):
        needed = [fast[i], slow[i], trend[i], trend[i - 3], rsis[i], di_plus[i], di_minus[i], adx[i]]
        if any(v is None for v in needed):
            continue
        slope = trend[i] - trend[i - 3]
        bull = bars[i]["close"] > trend[i] and fast[i] > slow[i] and slope > 0 and rsis[i] > 50 and di_plus[i] > di_minus[i] and adx[i] >= p["min_adx"]
        bear = bars[i]["close"] < trend[i] and fast[i] < slow[i] and slope < 0 and rsis[i] < 50 and di_minus[i] > di_plus[i] and adx[i] >= p["min_adx"]
        state = 1 if bull else -1 if bear else 0
        event_time = bars[i]["time"] + timedelta(minutes=tf_minutes - 5)
        states[event_time] = state
    return states


def m5_signal_context(m5):
    p = PARAMS
    closes = [b["close"] for b in m5]
    highs = [b["high"] for b in m5]
    lows = [b["low"] for b in m5]
    volumes = [b["volume"] for b in m5]
    fast = ema(closes, p["fast_len"])
    slow = ema(closes, p["slow_len"])
    trend = ema(closes, p["trend_len"])
    rsis = rsi(closes, p["rsi_len"])
    atrs = atr(m5, p["atr_len"])
    di_plus, di_minus, adx = dmi_adx(m5, p["di_len"], p["adx_smooth"])
    return {"closes": closes, "highs": highs, "lows": lows, "volumes": volumes, "fast": fast, "slow": slow, "trend": trend, "rsi": rsis, "atr": atrs, "di_plus": di_plus, "di_minus": di_minus, "adx": adx}


def generate_m5_candidate(i, m5, ctx, states, profile):
    p = PARAMS
    if i < 203:
        return None
    bar = m5[i]
    if not session_ok(bar["time"]):
        return None
    fast, slow, trend = ctx["fast"], ctx["slow"], ctx["trend"]
    rsis, atrs = ctx["rsi"], ctx["atr"]
    di_plus, di_minus, adx = ctx["di_plus"], ctx["di_minus"], ctx["adx"]
    needed = [fast[i], fast[i - 1], slow[i], slow[i - 1], trend[i], trend[i - 3], rsis[i], atrs[i], di_plus[i], di_minus[i], adx[i]]
    if any(v is None for v in needed):
        return None
    vol_sma = sma_at(ctx["volumes"], p["vol_len"], i)
    if vol_sma is None:
        return None
    rng = bar["high"] - bar["low"]
    body = abs(bar["close"] - bar["open"])
    body_ok = rng > 0 and body / rng >= p["min_body_ratio"]
    atr_pct = atrs[i] / bar["close"] * 100.0 if bar["close"] else 0.0
    atr_ok = p["min_atr_pct"] <= atr_pct <= p["max_atr_pct"]
    vol_ok = bar["volume"] > vol_sma * p["vol_mult"]
    ema_slope = trend[i] - trend[i - 3]
    prev_high3 = max(ctx["highs"][i - 3:i])
    prev_low3 = min(ctx["lows"][i - 3:i])
    break_long = bar["close"] > prev_high3
    break_short = bar["close"] < prev_low3
    pullback_long = bar["close"] > fast[i] and fast[i] > slow[i] and bar["low"] <= fast[i] and bar["close"] > bar["open"]
    pullback_short = bar["close"] < fast[i] and fast[i] < slow[i] and bar["high"] >= fast[i] and bar["close"] < bar["open"]
    cross_long = fast[i] > slow[i] and fast[i - 1] <= slow[i - 1]
    cross_short = fast[i] < slow[i] and fast[i - 1] >= slow[i - 1]
    long_trigger = break_long or pullback_long or cross_long
    short_trigger = break_short or pullback_short or cross_short
    m5_long = bar["close"] > trend[i] and fast[i] > slow[i] and ema_slope > 0 and p["long_rsi_min"] < rsis[i] < p["long_rsi_max"] and di_plus[i] > di_minus[i]
    m5_short = bar["close"] < trend[i] and fast[i] < slow[i] and ema_slope < 0 and p["short_rsi_min"] < rsis[i] < p["short_rsi_max"] and di_minus[i] > di_plus[i]
    st15 = states["M15"]
    st30 = states["M30"]
    st60 = states["H1"]
    st120 = states["H2"]
    st240 = states["H4"]
    long_confirm = (1 if st15 == 1 else 0) + (1 if st30 == 1 else 0) + (1 if st60 == 1 else 0)
    short_confirm = (1 if st15 == -1 else 0) + (1 if st30 == -1 else 0) + (1 if st60 == -1 else 0)
    long_htf = long_confirm >= profile["min_confirm"] and (not profile["require_h1"] or st60 == 1) and (not profile["block_h2_opp"] or st120 >= 0) and (not profile["block_h4_opp"] or st240 >= 0)
    short_htf = short_confirm >= profile["min_confirm"] and (not profile["require_h1"] or st60 == -1) and (not profile["block_h2_opp"] or st120 <= 0) and (not profile["block_h4_opp"] or st240 <= 0)
    long_score = 0.0
    long_score += 18.0 if long_trigger else 0.0
    long_score += 18.0 if m5_long else 0.0
    long_score += 8.0 if vol_ok else 0.0
    long_score += 7.0 if body_ok else 0.0
    long_score += 7.0 if atr_ok else 0.0
    long_score += 8.0 if adx[i] >= p["min_adx"] else 0.0
    long_score += long_confirm * 8.0
    long_score += 5.0 if st120 == 1 else 0.0
    long_score += 5.0 if st240 == 1 else 0.0
    long_score += 6.0 if break_long else 0.0
    short_score = 0.0
    short_score += 18.0 if short_trigger else 0.0
    short_score += 18.0 if m5_short else 0.0
    short_score += 8.0 if vol_ok else 0.0
    short_score += 7.0 if body_ok else 0.0
    short_score += 7.0 if atr_ok else 0.0
    short_score += 8.0 if adx[i] >= p["min_adx"] else 0.0
    short_score += short_confirm * 8.0
    short_score += 5.0 if st120 == -1 else 0.0
    short_score += 5.0 if st240 == -1 else 0.0
    short_score += 6.0 if break_short else 0.0
    long_ok = long_trigger and m5_long and long_htf and vol_ok and body_ok and atr_ok and adx[i] >= p["min_adx"] and long_score >= profile["min_score"]
    short_ok = short_trigger and m5_short and short_htf and vol_ok and body_ok and atr_ok and adx[i] >= p["min_adx"] and short_score >= profile["min_score"]
    if not long_ok and not short_ok:
        return None
    if long_ok and (not short_ok or long_score >= short_score):
        return {"direction": "BUY", "score": round(long_score, 3), "entry": bar["close"], "atr": atrs[i], "confirm": long_confirm, "st15": st15, "st30": st30, "st60": st60, "st120": st120, "st240": st240, "rsi": round(rsis[i], 3), "adx": round(adx[i], 3)}
    return {"direction": "SELL", "score": round(short_score, 3), "entry": bar["close"], "atr": atrs[i], "confirm": short_confirm, "st15": st15, "st30": st30, "st60": st60, "st120": st120, "st240": st240, "rsi": round(rsis[i], 3), "adx": round(adx[i], 3)}


def simulate_profile(m1_rows, start, end, deposit, profile_name, profile):
    m5_all = resample(m1_rows, 5)
    m5 = [b for b in m5_all if (start is None or b["time"] >= start) and (end is None or b["time"] < end)]
    if not m5:
        return {"profile": profile_name, "verdict": "NO_M5_BARS"}
    ctx = m5_signal_context(m5)
    state_maps = {tf: tf_state_series(resample(m1_rows, minutes), minutes) for tf, minutes in TF_MINUTES.items() if tf != "M5"}
    current_states = {"M15": 0, "M30": 0, "H1": 0, "H2": 0, "H4": 0}
    balance = deposit
    balances = [deposit]
    trades = []
    position = None
    trades_today = 0
    day_key = None
    last_entry_time = None
    blocked = {"cooldown": 0, "daily_limit": 0, "existing_position": 0}
    signals = 0
    for i, bar in enumerate(m5):
        for tf, mp in state_maps.items():
            if bar["time"] in mp:
                current_states[tf] = mp[bar["time"]]
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
                if reason is None and profile["weakness_exit"] and hold_bars >= profile["weakness_bars"]:
                    fast = ctx["fast"][i]
                    slow = ctx["slow"][i]
                    st15 = current_states["M15"]
                    if position["direction"] == "BUY" and bar["close"] < position["entry"] and (fast is not None and slow is not None and fast < slow or st15 == -1):
                        reason, exit_price = "WEAKNESS_CUT", bar["close"]
                    elif position["direction"] == "SELL" and bar["close"] > position["entry"] and (fast is not None and slow is not None and fast > slow or st15 == 1):
                        reason, exit_price = "WEAKNESS_CUT", bar["close"]
            if reason:
                points = exit_price - position["entry"] if position["direction"] == "BUY" else position["entry"] - exit_price
                profit = points * 0.01 * 100.0
                balance += profit
                balances.append(balance)
                trade = {**position}
                trade.update({
                    "exit_time": bar["time"], "exit": round(exit_price, 5), "exit_reason": reason,
                    "profit_points": round(points, 3), "profit_money": round(profit, 2),
                    "balance_after": round(balance, 2),
                    "hold_minutes": int((bar["time"] - position["entry_time"]).total_seconds() // 60),
                })
                trades.append(trade)
                position = None
        candidate = generate_m5_candidate(i, m5, ctx, current_states, profile)
        if candidate is None:
            continue
        signals += 1
        if position is not None:
            blocked["existing_position"] += 1
            continue
        if trades_today >= profile["max_trades_day"]:
            blocked["daily_limit"] += 1
            continue
        if last_entry_time and (bar["time"] - last_entry_time).total_seconds() < profile["cooldown_min"] * 60:
            blocked["cooldown"] += 1
            continue
        position = {
            "entry_time": bar["time"], "entry_bar": i, "tf": "M5", "direction": candidate["direction"],
            "entry": round(candidate["entry"], 5), "atr": round(candidate["atr"], 5),
            "score": candidate["score"], "confirm": candidate["confirm"], "rsi": candidate["rsi"], "adx": candidate["adx"],
            "st15": candidate["st15"], "st30": candidate["st30"], "st60": candidate["st60"], "st120": candidate["st120"], "st240": candidate["st240"],
        }
        trades_today += 1
        last_entry_time = bar["time"]
    open_trade = None
    if position:
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
        row["exit_time"] = t["exit_time"].strftime("%Y-%m-%d %H:%M:%S")
        result_trades.append(row)
    return {
        "profile": profile_name,
        "verdict": "POSITIVE" if net > 0 else "NEGATIVE" if net < 0 else "FLAT",
        "tp_atr": profile["tp"], "sl_atr": profile["sl"], "min_score": profile["min_score"],
        "min_confirm": profile["min_confirm"], "final_balance": round(balance, 2), "net_profit": net,
        "signals": signals, "closed_trades": len(trades), "open_trade": open_trade,
        "wins": wins, "losses": losses, "win_rate": round(wins / len(trades), 3) if trades else None,
        "gross_profit": round(gross_profit, 2), "gross_loss": round(gross_loss, 2),
        "profit_factor": round(gross_profit / abs(gross_loss), 3) if gross_loss else None,
        "max_closed_drawdown_money": max_drawdown(balances),
        "avg_hold_minutes": round(sum(t["hold_minutes"] for t in trades) / len(trades), 1) if trades else None,
        "trade_days": trade_days,
        "avg_trades_per_trade_day": round(len(trades) / trade_days, 2) if trade_days else None,
        "blocked_signals": blocked,
        "trades": result_trades,
    }


def write_outputs(root: Path, results):
    profiles = {k: {kk: vv for kk, vv in v.items() if kk != "trades"} for k, v in results.items()}
    ranked_expectancy = sorted(profiles.values(), key=lambda x: (x.get("profit_factor") or 0.0, x.get("net_profit") or -999999, x.get("win_rate") or 0.0), reverse=True)
    ranked_winrate = sorted(profiles.values(), key=lambda x: (x.get("win_rate") or 0.0, x.get("profit_factor") or 0.0, x.get("net_profit") or -999999), reverse=True)
    final = {
        "verdict": "DONE",
        "engine": "XAUUSD_Master_V23_Expectancy_MTF_python_clone",
        "design": "M5 entries only; M15/M30/H1 confirmations; H2/H4 filters only; optimized for expectancy, not winrate alone",
        "best_by_expectancy": ranked_expectancy[0] if ranked_expectancy else None,
        "best_by_winrate": ranked_winrate[0] if ranked_winrate else None,
        "profiles": profiles,
    }
    (root / "PINE_V23_MTF_BACKTEST.json").write_text(json.dumps(final, indent=2, ensure_ascii=False), encoding="utf-8")
    for name, result in results.items():
        with (root / f"PINE_V23_MTF_TRADES_{name}.csv").open("w", encoding="utf-8", newline="") as f:
            fields = ["entry_time", "tf", "direction", "entry", "atr", "score", "confirm", "rsi", "adx", "st15", "st30", "st60", "st120", "st240", "exit_time", "exit", "exit_reason", "profit_points", "profit_money", "balance_after", "hold_minutes"]
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
        (root / "PINE_V23_MTF_BACKTEST.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps(result, indent=2))
        return 0
    results = {name: simulate_profile(m1_rows, start, end, args.deposit, name, profile) for name, profile in PROFILES.items()}
    write_outputs(root, results)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
