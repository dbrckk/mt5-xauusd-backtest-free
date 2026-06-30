import argparse, csv, json, re
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

TP_GRID = [1.2, 1.45, 1.8, 2.2, 2.5, 3.0]
SL_GRID = [0.8, 1.0, 1.2, 1.45, 1.8, 2.0]
WINDOW_GRID = [0, 6, 12, 18]
DIR_GRID = ["all", "buy", "sell"]
REGIME_GRID = ["none", "h2", "h2h4"]


def decode(data):
    for enc in ("utf-8", "utf-16", "cp1252", "latin1"):
        try:
            return data.decode(enc, errors="replace")
        except Exception:
            pass
    return data.decode("utf-8", errors="replace")


def read_blob(root):
    out = []
    for p in root.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".txt", ".log", ".json", ".csv", ".html", ".htm"}:
            try:
                out.append(decode(p.read_bytes()))
            except Exception:
                pass
    return "\n".join(out)


def parse_dates(blob):
    fm = re.search(r"public_forced_from_date=(\d{4}\.\d{2}\.\d{2})", blob) or re.search(r"input_from_date=(\d{4}\.\d{2}\.\d{2})", blob)
    tm = re.search(r"public_forced_to_date=(\d{4}\.\d{2}\.\d{2})", blob) or re.search(r"input_to_date=(\d{4}\.\d{2}\.\d{2})", blob)
    start = datetime.strptime(fm.group(1), "%Y.%m.%d") if fm else None
    end = datetime.strptime(tm.group(1), "%Y.%m.%d") + timedelta(days=1) if tm else None
    return start, end


def load_m1(root):
    files = list(root.rglob("xau_public_m1.csv"))
    if not files:
        return []
    rows = []
    with files[0].open("r", encoding="utf-8", newline="") as f:
        for r in csv.DictReader(f):
            try:
                rows.append({"time": datetime.strptime(r["time"], "%Y.%m.%d %H:%M"), "open": float(r["open"]), "high": float(r["high"]), "low": float(r["low"]), "close": float(r["close"]), "volume": float(r.get("tick_volume") or r.get("volume") or 0)})
            except Exception:
                pass
    rows.sort(key=lambda x: x["time"])
    return rows


def bucket(t, minutes):
    total = t.hour * 60 + t.minute
    b = (total // minutes) * minutes
    return t.replace(hour=b // 60, minute=b % 60, second=0, microsecond=0)


def resample(rows, minutes):
    out, key, cur = [], None, None
    for r in rows:
        k = bucket(r["time"], minutes)
        if k != key:
            if cur:
                out.append(cur)
            key = k
            cur = {"time": k, "open": r["open"], "high": r["high"], "low": r["low"], "close": r["close"], "volume": r["volume"]}
        else:
            cur["high"] = max(cur["high"], r["high"])
            cur["low"] = min(cur["low"], r["low"])
            cur["close"] = r["close"]
            cur["volume"] += r["volume"]
    if cur:
        out.append(cur)
    return out


def ema(vals, n):
    out = [None] * len(vals)
    a, prev = 2 / (n + 1), None
    for i, v in enumerate(vals):
        prev = v if prev is None else a * v + (1 - a) * prev
        out[i] = prev
    return out


def rma(vals, n):
    out = [None] * len(vals)
    if len(vals) < n:
        return out
    prev = sum(vals[:n]) / n
    out[n - 1] = prev
    for i in range(n, len(vals)):
        prev = (prev * (n - 1) + vals[i]) / n
        out[i] = prev
    return out


def rsi(closes, n):
    gains, losses = [0], [0]
    for i in range(1, len(closes)):
        c = closes[i] - closes[i - 1]
        gains.append(max(c, 0)); losses.append(max(-c, 0))
    ag, al = rma(gains, n), rma(losses, n)
    out = [None] * len(closes)
    for i in range(len(closes)):
        if ag[i] is not None and al[i] is not None:
            out[i] = 100 if al[i] == 0 else 100 - 100 / (1 + ag[i] / al[i])
    return out


def atr(bars, n):
    trs, prev = [], None
    for b in bars:
        tr = b["high"] - b["low"] if prev is None else max(b["high"] - b["low"], abs(b["high"] - prev), abs(b["low"] - prev))
        trs.append(tr); prev = b["close"]
    return rma(trs, n)


def sma(vals, n, i):
    return None if i + 1 < n else sum(vals[i - n + 1:i + 1]) / n


def session_ok(t):
    return t.weekday() < 5 and 8 <= t.hour < 21 and (t.weekday() != 4 or t.hour < 16)


def h1_signals(h1, start, end):
    c = [b["close"] for b in h1]; v = [b["volume"] for b in h1]
    f, s, tr, rs, at = ema(c, 9), ema(c, 21), ema(c, 200), rsi(c, 14), atr(h1, 14)
    sigs = []
    for i in range(2, len(h1)):
        t = h1[i]["time"] + timedelta(minutes=55)
        if start and t < start: continue
        if end and t >= end: continue
        vals = [f[i], s[i], f[i-1], s[i-1], tr[i], rs[i], at[i]]
        if any(x is None for x in vals) or not session_ok(t): continue
        sv = sma(v, 20, i)
        if sv is None or v[i] <= sv * 0.8: continue
        long = f[i] > s[i] and f[i-1] <= s[i-1] and h1[i]["close"] > tr[i] and 50 < rs[i] < 68
        sell = f[i] < s[i] and f[i-1] >= s[i-1] and h1[i]["close"] < tr[i] and 32 < rs[i] < 50
        if long or sell:
            sigs.append({"time": t, "src": h1[i]["time"], "dir": "BUY" if long else "SELL", "ref": h1[i]["close"], "atr": at[i]})
    return sigs


def state_map(bars, minutes):
    c = [b["close"] for b in bars]
    f, s, tr, rs = ema(c, 9), ema(c, 21), ema(c, 200), rsi(c, 14)
    mp = {}
    for i in range(3, len(bars)):
        if any(x is None for x in [f[i], s[i], tr[i], tr[i-3], rs[i]]): continue
        slope = tr[i] - tr[i-3]
        bull = bars[i]["close"] > tr[i] and f[i] > s[i] and slope > 0 and rs[i] > 50
        bear = bars[i]["close"] < tr[i] and f[i] < s[i] and slope < 0 and rs[i] < 50
        mp[bars[i]["time"] + timedelta(minutes=minutes-5)] = 1 if bull else -1 if bear else 0
    return mp


def m5_context(m5):
    c = [b["close"] for b in m5]
    return {"fast": ema(c, 9), "slow": ema(c, 21), "rsi": rsi(c, 14)}


def m5_ok(i, m5, ctx, sig):
    if i < 1 or any(ctx[k][i] is None for k in ctx):
        return False
    b = m5[i]
    rng = b["high"] - b["low"]
    body_ok = rng > 0 and abs(b["close"] - b["open"]) / rng >= 0.30
    if sig["dir"] == "BUY":
        return body_ok and b["close"] > ctx["fast"][i] > ctx["slow"][i] and b["close"] > b["open"] and 50 < ctx["rsi"][i] < 70 and b["close"] >= sig["ref"] - sig["atr"] * 0.70
    return body_ok and b["close"] < ctx["fast"][i] < ctx["slow"][i] and b["close"] < b["open"] and 30 < ctx["rsi"][i] < 50 and b["close"] <= sig["ref"] + sig["atr"] * 0.70


def allowed(sig, h2, h4, mode):
    d = 1 if sig["dir"] == "BUY" else -1
    if mode == "h2" and h2 == -d: return False
    if mode == "h2h4" and (h2 == -d or h4 == -d): return False
    return True


def run_variant(m5, sigs, ctx, h2, h4, var, deposit):
    sig_by_time = defaultdict(list)
    for s in sigs:
        if var["dir"] == "buy" and s["dir"] != "BUY": continue
        if var["dir"] == "sell" and s["dir"] != "SELL": continue
        if not allowed(s, h2.get(s["time"], 0), h4.get(s["time"], 0), var["regime"]): continue
        sig_by_time[s["time"]].append(s)
    bal, balances, trades = deposit, [deposit], []
    pos, pending = None, None
    trades_today, day, last_entry = 0, None, None
    for i, b in enumerate(m5):
        dkey = b["time"].strftime("%Y%m%d")
        if dkey != day:
            day, trades_today = dkey, 0
        if pos:
            if pos["dir"] == "BUY":
                tp, sl = pos["entry"] + pos["atr"] * var["tp"], pos["entry"] - pos["atr"] * var["sl"]
                tp_hit, sl_hit = b["high"] >= tp, b["low"] <= sl
            else:
                tp, sl = pos["entry"] - pos["atr"] * var["tp"], pos["entry"] + pos["atr"] * var["sl"]
                tp_hit, sl_hit = b["low"] <= tp, b["high"] >= sl
            reason, price = None, None
            if tp_hit and sl_hit: reason, price = "SL_CONSERVATIVE", sl
            elif sl_hit: reason, price = "SL", sl
            elif tp_hit: reason, price = "TP", tp
            if reason:
                pts = price - pos["entry"] if pos["dir"] == "BUY" else pos["entry"] - price
                profit = pts
                bal += profit
                balances.append(bal)
                row = {**pos, "exit_time": b["time"], "exit": round(price, 5), "exit_reason": reason, "profit_money": round(profit, 2), "balance_after": round(bal, 2), "hold_minutes": int((b["time"] - pos["entry_time"]).total_seconds() // 60)}
                trades.append(row); pos = None
        if b["time"] in sig_by_time:
            pending = {**sig_by_time[b["time"]][0], "start": i, "end": i + var["window"]}
        if pending and i > pending["end"]:
            pending = None
        if not pending or pos or trades_today >= 2:
            continue
        if last_entry and (b["time"] - last_entry).total_seconds() < 180 * 60:
            continue
        entry = None
        if var["window"] == 0 and i == pending["start"]:
            entry = pending["ref"]
        elif var["window"] > 0 and m5_ok(i, m5, ctx, pending):
            entry = b["close"]
        if entry is None:
            continue
        pos = {"entry_time": b["time"], "source_time": pending["src"], "dir": pending["dir"], "entry": round(entry, 5), "atr": round(pending["atr"], 5), "mode": "h1_close" if var["window"] == 0 else "m5_refine", "regime": var["regime"], "dir_filter": var["dir"]}
        pending, trades_today, last_entry = None, trades_today + 1, b["time"]
    wins = sum(1 for t in trades if t["profit_money"] > 0)
    gp = sum(t["profit_money"] for t in trades if t["profit_money"] > 0)
    gl = sum(t["profit_money"] for t in trades if t["profit_money"] < 0)
    peak, dd = balances[0], 0
    for x in balances:
        peak = max(peak, x); dd = min(dd, x - peak)
    days = len(set(t["entry_time"].strftime("%Y-%m-%d") for t in trades))
    out_trades = []
    for t in trades:
        r = dict(t); r["entry_time"] = t["entry_time"].strftime("%Y-%m-%d %H:%M:%S"); r["source_time"] = t["source_time"].strftime("%Y-%m-%d %H:%M:%S"); r["exit_time"] = t["exit_time"].strftime("%Y-%m-%d %H:%M:%S"); out_trades.append(r)
    return {**var, "net_profit": round(bal - deposit, 2), "final_balance": round(bal, 2), "closed_trades": len(trades), "wins": wins, "losses": len(trades)-wins, "win_rate": round(wins/len(trades), 3) if trades else None, "profit_factor": round(gp/abs(gl), 3) if gl else None, "max_closed_drawdown_money": round(dd, 2), "avg_trades_per_trade_day": round(len(trades)/days, 2) if days else None, "trades": out_trades}


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("reports_dir"); ap.add_argument("--deposit", type=float, default=10000.0); args = ap.parse_args()
    root = Path(args.reports_dir); blob = read_blob(root); start, end = parse_dates(blob); m1 = load_m1(root)
    if not m1:
        print(json.dumps({"verdict": "NO_HISTORY"})); return 0
    m5 = resample(m1, 5); h1 = resample(m1, 60)
    m5 = [b for b in m5 if (not start or b["time"] >= start) and (not end or b["time"] < end)]
    sigs = h1_signals(h1, start, end); ctx = m5_context(m5); h2 = state_map(resample(m1, 120), 120); h4 = state_map(resample(m1, 240), 240)
    variants = [{"window": w, "dir": d, "regime": r, "tp": tp, "sl": sl} for w in WINDOW_GRID for d in DIR_GRID for r in REGIME_GRID for tp in TP_GRID for sl in SL_GRID]
    results = [run_variant(m5, sigs, ctx, h2, h4, v, args.deposit) for v in variants]
    results.sort(key=lambda x: (x["net_profit"], x.get("profit_factor") or 0, x.get("win_rate") or 0), reverse=True)
    clean = lambda x: {k:v for k,v in x.items() if k != "trades"}
    final = {"verdict": "DONE", "engine": "V24_H1_CORE_M5_REFINED", "baseline_to_beat": {"net_profit": 117.66, "win_rate": 0.583, "profit_factor_est": 2.82}, "h1_signals": len(sigs), "variant_count": len(results), "best_by_profit": clean(results[0]), "top_20": [clean(x) for x in results[:20]]}
    (root / "PINE_V24_H1_CORE_OPTIMIZATION.json").write_text(json.dumps(final, indent=2), encoding="utf-8")
    with (root / "PINE_V24_H1_CORE_VARIANTS.csv").open("w", encoding="utf-8", newline="") as f:
        fields = ["rank", "window", "dir", "regime", "tp", "sl", "net_profit", "final_balance", "closed_trades", "wins", "losses", "win_rate", "profit_factor", "max_closed_drawdown_money", "avg_trades_per_trade_day"]
        wr = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore"); wr.writeheader()
        for i, r in enumerate(results, 1): wr.writerow({"rank": i, **r})
    with (root / "PINE_V24_H1_CORE_BEST_TRADES.csv").open("w", encoding="utf-8", newline="") as f:
        fields = ["entry_time", "source_time", "dir", "entry", "atr", "mode", "regime", "dir_filter", "exit_time", "exit", "exit_reason", "profit_money", "balance_after", "hold_minutes"]
        wr = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore"); wr.writeheader(); [wr.writerow(t) for t in results[0].get("trades", [])]
    print(json.dumps(final, indent=2))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
