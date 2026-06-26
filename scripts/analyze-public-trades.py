import argparse
import json
import re
from datetime import datetime, timedelta
from pathlib import Path
import csv

DEAL_RE = re.compile(
    r"(?P<time>20\d{2}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}).*?deal #(?P<id>\d+) (?P<side>buy|sell) (?P<lot>[0-9.]+) XAU_PUBLIC at (?P<price>[0-9.]+) done",
    re.IGNORECASE,
)


def parse_time(value: str) -> datetime:
    return datetime.strptime(value.replace(".", "-", 2), "%Y-%m-%d %H:%M:%S")


def find_file(root: Path, name: str) -> Path | None:
    matches = list(root.rglob(name))
    return matches[0] if matches else None


def read_text(path: Path) -> str:
    data = path.read_bytes()
    for enc in ("utf-8", "utf-16", "utf-16le", "latin1"):
        try:
            return data.decode(enc, errors="replace")
        except Exception:
            continue
    return data.decode("utf-8", errors="replace")


def load_bars(path: Path):
    rows = []
    with path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for r in reader:
            try:
                rows.append({
                    "time": datetime.strptime(r["time"], "%Y.%m.%d %H:%M"),
                    "open": float(r["open"]),
                    "high": float(r["high"]),
                    "low": float(r["low"]),
                    "close": float(r["close"]),
                })
            except Exception:
                continue
    return rows


def load_deals(root: Path):
    text_parts = []
    for pattern in ("tester_logs_copy/*.log", "metatester_copy/**/*.log", "QQ_PUBLIC_BACKTEST_FALLBACK_REPORT.html"):
        for p in root.glob(pattern):
            text_parts.append(read_text(p))
    blob = "\n".join(text_parts)
    seen = set()
    deals = []
    for m in DEAL_RE.finditer(blob):
        deal_id = int(m.group("id"))
        if deal_id in seen:
            continue
        seen.add(deal_id)
        deals.append({
            "id": deal_id,
            "time": parse_time(m.group("time")),
            "side": m.group("side").lower(),
            "lot": float(m.group("lot")),
            "price": float(m.group("price")),
        })
    return sorted(deals, key=lambda x: (x["time"], x["id"]))


def pair_trades(deals):
    trades = []
    open_trade = None
    for d in deals:
        if open_trade is None:
            open_trade = d
            continue
        if d["side"] != open_trade["side"]:
            direction = "SELL" if open_trade["side"] == "sell" else "BUY"
            profit_points = (open_trade["price"] - d["price"]) if direction == "SELL" else (d["price"] - open_trade["price"])
            trades.append({
                "entry_time": open_trade["time"],
                "exit_time": d["time"],
                "direction": direction,
                "entry_price": open_trade["price"],
                "exit_price": d["price"],
                "lot": open_trade["lot"],
                "profit_points": round(profit_points, 3),
                "hold_minutes": int((d["time"] - open_trade["time"]).total_seconds() // 60),
            })
            open_trade = None
        else:
            open_trade = d
    return trades


def enrich_trade(trade, bars):
    start = trade["entry_time"]
    end = trade["exit_time"]
    after_12h = start + timedelta(hours=12)
    after_24h = start + timedelta(hours=24)
    entry = trade["entry_price"]
    is_sell = trade["direction"] == "SELL"

    def window(until):
        return [b for b in bars if start <= b["time"] <= until]

    def stats(until):
        ws = window(until)
        if not ws:
            return {"mfe_points": None, "mae_points": None}
        if is_sell:
            mfe = entry - min(b["low"] for b in ws)
            mae = max(b["high"] for b in ws) - entry
        else:
            mfe = max(b["high"] for b in ws) - entry
            mae = entry - min(b["low"] for b in ws)
        return {"mfe_points": round(mfe, 3), "mae_points": round(mae, 3)}

    in_trade = stats(end)
    h12 = stats(after_12h)
    h24 = stats(after_24h)
    captured = None
    if in_trade["mfe_points"] and in_trade["mfe_points"] > 0:
        captured = round(trade["profit_points"] / in_trade["mfe_points"], 3)
    trade.update({
        "mfe_until_exit_points": in_trade["mfe_points"],
        "mae_until_exit_points": in_trade["mae_points"],
        "capture_ratio_until_exit": captured,
        "mfe_12h_points": h12["mfe_points"],
        "mae_12h_points": h12["mae_points"],
        "mfe_24h_points": h24["mfe_points"],
        "mae_24h_points": h24["mae_points"],
    })
    return trade


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reports_dir")
    args = parser.parse_args()
    root = Path(args.reports_dir)

    bars_path = find_file(root, "xau_public_m1.csv")
    if bars_path is None:
        raise SystemExit("xau_public_m1.csv not found")
    bars = load_bars(bars_path)
    deals = load_deals(root)
    trades = [enrich_trade(t, bars) for t in pair_trades(deals)]

    total_points = round(sum(t["profit_points"] for t in trades), 3)
    avg_capture = None
    caps = [t["capture_ratio_until_exit"] for t in trades if t["capture_ratio_until_exit"] is not None]
    if caps:
        avg_capture = round(sum(caps) / len(caps), 3)

    result = {
        "trade_count": len(trades),
        "total_profit_points": total_points,
        "average_capture_ratio_until_exit": avg_capture,
        "trades": [
            {
                **t,
                "entry_time": t["entry_time"].strftime("%Y-%m-%d %H:%M:%S"),
                "exit_time": t["exit_time"].strftime("%Y-%m-%d %H:%M:%S"),
            }
            for t in trades
        ],
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
