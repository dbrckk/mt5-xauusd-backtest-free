import argparse
import csv
import json
import math
import re
from collections import defaultdict
from datetime import datetime
from pathlib import Path

TEXT_EXTENSIONS = {".txt", ".log", ".ini", ".set", ".csv", ".html", ".htm", ".json"}

DEAL_RE = re.compile(
    r"(?P<time>20\d{2}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}).*?deal #(?P<id>\d+) "
    r"(?P<side>buy|sell) (?P<lot>[0-9.]+) XAU_PUBLIC at (?P<price>[0-9.]+) done",
    re.IGNORECASE,
)
FINAL_BALANCE_PATTERNS = [
    re.compile(r"final balance\s+([0-9]+(?:\.[0-9]+)?)\s+USD", re.IGNORECASE),
    re.compile(r"Final balance</td>\s*<td[^>]*>([0-9]+(?:\.[0-9]+)?)\s+USD", re.IGNORECASE),
]


def decode_text(data: bytes) -> str:
    candidates = []
    for encoding in ("utf-8", "utf-16", "utf-16le", "cp1252", "latin1"):
        try:
            text = data.decode(encoding, errors="replace")
            candidates.append((text[:3000].count("\x00"), -len(text), text))
        except Exception:
            continue
    if not candidates:
        return data.decode("utf-8", errors="replace")
    candidates.sort(key=lambda item: (item[0], item[1]))
    return candidates[0][2]


def read_texts(root: Path) -> dict[str, str]:
    texts: dict[str, str] = {}
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in TEXT_EXTENSIONS:
            continue
        try:
            texts[str(path.relative_to(root))] = decode_text(path.read_bytes())
        except Exception:
            continue
    return texts


def parse_time(value: str) -> datetime:
    return datetime.strptime(value, "%Y.%m.%d %H:%M:%S")


def find_final_balance(blob: str) -> float | None:
    values = []
    for pattern in FINAL_BALANCE_PATTERNS:
        values.extend(float(match.group(1)) for match in pattern.finditer(blob))
    return values[-1] if values else None


def load_unique_deals(blob: str) -> list[dict]:
    by_id: dict[int, dict] = {}
    for match in DEAL_RE.finditer(blob):
        deal_id = int(match.group("id"))
        by_id.setdefault(
            deal_id,
            {
                "id": deal_id,
                "time": parse_time(match.group("time")),
                "side": match.group("side").lower(),
                "lot": float(match.group("lot")),
                "price": float(match.group("price")),
            },
        )
    return sorted(by_id.values(), key=lambda item: (item["time"], item["id"]))


def pair_trades(deals: list[dict]) -> list[dict]:
    trades = []
    open_deal = None
    for deal in deals:
        if open_deal is None:
            open_deal = deal
            continue

        if deal["side"] == open_deal["side"]:
            continue

        direction = "BUY" if open_deal["side"] == "buy" else "SELL"
        price_delta = deal["price"] - open_deal["price"]
        if direction == "SELL":
            price_delta = -price_delta
        money = price_delta * 100.0 * open_deal["lot"]

        trades.append(
            {
                "entry_deal_id": open_deal["id"],
                "exit_deal_id": deal["id"],
                "entry_time": open_deal["time"],
                "exit_time": deal["time"],
                "direction": direction,
                "lot": open_deal["lot"],
                "entry_price": open_deal["price"],
                "exit_price": deal["price"],
                "price_delta": round(price_delta, 5),
                "profit_money": round(money, 2),
                "hold_minutes": int((deal["time"] - open_deal["time"]).total_seconds() // 60),
            }
        )
        open_deal = None
    return trades


def load_journal_entries(root: Path) -> list[dict]:
    entries = []
    for path in root.rglob("*.csv"):
        if "journal" not in path.name.lower():
            continue
        try:
            with path.open("r", encoding="utf-8", errors="replace", newline="") as handle:
                reader = csv.DictReader(handle)
                for row in reader:
                    if str(row.get("event", "")).upper() != "OPEN_ENTRY":
                        continue
                    try:
                        timestamp = datetime.strptime(str(row["time"]), "%Y.%m.%d %H:%M:%S")
                    except Exception:
                        continue
                    entries.append(
                        {
                            "time": timestamp,
                            "direction": str(row.get("direction", "")).upper(),
                            "setup": str(row.get("setup", "UNKNOWN")).upper() or "UNKNOWN",
                            "score": float(row.get("score") or 0.0),
                        }
                    )
        except Exception:
            continue

    unique = {}
    for item in entries:
        key = (item["time"], item["direction"], item["setup"], item["score"])
        unique[key] = item
    return sorted(unique.values(), key=lambda item: item["time"])


def attach_setups(trades: list[dict], journal_entries: list[dict]) -> None:
    for trade in trades:
        candidates = [
            entry
            for entry in journal_entries
            if entry["direction"] == trade["direction"]
            and abs((entry["time"] - trade["entry_time"]).total_seconds()) <= 300
        ]
        if not candidates:
            trade["setup"] = "UNKNOWN"
            trade["score"] = None
            continue
        match = min(candidates, key=lambda item: abs((item["time"] - trade["entry_time"]).total_seconds()))
        trade["setup"] = match["setup"]
        trade["score"] = match["score"]


def stats_for(trades: list[dict], deposit: float) -> dict:
    if not trades:
        return {
            "trades": 0,
            "wins": 0,
            "losses": 0,
            "win_rate": None,
            "gross_profit": 0.0,
            "gross_loss": 0.0,
            "profit_factor": None,
            "net_profit": 0.0,
            "expectancy": None,
            "average_win": None,
            "average_loss": None,
            "max_drawdown_money": 0.0,
            "max_drawdown_pct": 0.0,
        }

    profits = [float(trade["profit_money"]) for trade in trades]
    wins = [value for value in profits if value > 0]
    losses = [value for value in profits if value < 0]
    gross_profit = sum(wins)
    gross_loss = abs(sum(losses))
    net_profit = sum(profits)
    profit_factor = gross_profit / gross_loss if gross_loss > 0 else math.inf

    equity = deposit
    peak = deposit
    max_dd = 0.0
    max_dd_pct = 0.0
    for profit in profits:
        equity += profit
        peak = max(peak, equity)
        drawdown = peak - equity
        drawdown_pct = drawdown / peak if peak > 0 else 0.0
        max_dd = max(max_dd, drawdown)
        max_dd_pct = max(max_dd_pct, drawdown_pct)

    return {
        "trades": len(trades),
        "wins": len(wins),
        "losses": len(losses),
        "win_rate": round(len(wins) / len(trades), 4),
        "gross_profit": round(gross_profit, 2),
        "gross_loss": round(gross_loss, 2),
        "profit_factor": None if math.isinf(profit_factor) else round(profit_factor, 4),
        "profit_factor_infinite": math.isinf(profit_factor),
        "net_profit": round(net_profit, 2),
        "expectancy": round(net_profit / len(trades), 4),
        "average_win": round(sum(wins) / len(wins), 4) if wins else None,
        "average_loss": round(sum(losses) / len(losses), 4) if losses else None,
        "max_drawdown_money": round(max_dd, 2),
        "max_drawdown_pct": round(max_dd_pct * 100.0, 4),
    }


def group_stats(trades: list[dict], field: str, deposit: float) -> dict:
    grouped = defaultdict(list)
    for trade in trades:
        grouped[str(trade.get(field, "UNKNOWN"))].append(trade)
    return {key: stats_for(value, deposit) for key, value in sorted(grouped.items())}


def unique_error_lines(blob: str) -> dict:
    categories = {
        "no_money": re.compile(r"No money", re.IGNORECASE),
        "invalid_price": re.compile(r"Invalid price", re.IGNORECASE),
        "invalid_stops": re.compile(r"Invalid stops", re.IGNORECASE),
        "failed_order": re.compile(r"failed (?:market|instant) (?:buy|sell)", re.IGNORECASE),
        "failed_modify": re.compile(r"failed modify", re.IGNORECASE),
    }
    unique_by_category = {key: set() for key in categories}

    for line in blob.splitlines():
        normalized = line.strip()
        if not normalized:
            continue
        for key, pattern in categories.items():
            if pattern.search(normalized):
                match = re.search(r"(20\d{2}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}.*)", normalized)
                unique_by_category[key].add(match.group(1) if match else normalized[-500:])

    return {key: len(values) for key, values in unique_by_category.items()}


def load_data_quality(root: Path) -> dict:
    matches = list(root.rglob("download_diagnostics.json"))
    if not matches:
        return {"available": False}
    try:
        data = json.loads(matches[0].read_text(encoding="utf-8"))
        data["available"] = True
        return data
    except Exception:
        return {"available": False}


def classify(overall: dict, errors: dict, quality: dict) -> tuple[str, list[str]]:
    reasons = []

    if not quality.get("available"):
        return "DATA_QUALITY_UNKNOWN", ["download_diagnostics.json missing"]

    if int(quality.get("synthetic_fill_bars", -1)) != 0:
        return "DATA_QUALITY_FAIL", ["synthetic bars detected"]

    ratio = float(quality.get("hour_success_ratio", 0.0))
    required_ratio = float(quality.get("min_required_hour_success_ratio", 0.90))
    if ratio < required_ratio:
        return "DATA_QUALITY_FAIL", [f"hour success ratio {ratio:.4f} below {required_ratio:.4f}"]

    if errors["no_money"] > 0:
        return "EXECUTION_FAIL", [f"{errors['no_money']} unique no-money rejection(s)"]

    trades = overall["trades"]
    if trades < 60:
        return "INSUFFICIENT_SAMPLE", [f"only {trades} closed trades"]

    pf = overall.get("profit_factor")
    wr = overall.get("win_rate")
    net = overall.get("net_profit", 0.0)
    dd = overall.get("max_drawdown_pct", 100.0)

    if net > 0 and pf is not None and pf >= 1.25 and wr is not None and wr >= 0.52 and dd <= 10.0 and trades >= 120:
        reasons.append("positive edge threshold met")
        return "CLEAN_PASS", reasons

    if net > 0 and pf is not None and pf >= 1.10 and wr is not None and wr >= 0.48:
        reasons.append("positive result, but robustness threshold not fully met")
        return "PROMISING_RETEST", reasons

    reasons.append("no validated positive edge on this chunk")
    return "STRATEGY_REWORK_REQUIRED", reasons


def write_trades(root: Path, trades: list[dict]) -> None:
    output = root / "V27_TRADES.csv"
    fields = [
        "entry_deal_id",
        "exit_deal_id",
        "entry_time",
        "exit_time",
        "direction",
        "setup",
        "score",
        "lot",
        "entry_price",
        "exit_price",
        "price_delta",
        "profit_money",
        "hold_minutes",
    ]
    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for trade in trades:
            row = dict(trade)
            row["entry_time"] = trade["entry_time"].strftime("%Y.%m.%d %H:%M:%S")
            row["exit_time"] = trade["exit_time"].strftime("%Y.%m.%d %H:%M:%S")
            writer.writerow(row)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reports_dir")
    parser.add_argument("--deposit", type=float, default=15000.0)
    args = parser.parse_args()

    root = Path(args.reports_dir)
    texts = read_texts(root)
    blob = "\n".join(texts.values())

    deals = load_unique_deals(blob)
    trades = pair_trades(deals)
    attach_setups(trades, load_journal_entries(root))

    overall = stats_for(trades, args.deposit)
    errors = unique_error_lines(blob)
    data_quality = load_data_quality(root)
    final_balance = find_final_balance(blob)
    verdict, reasons = classify(overall, errors, data_quality)

    result = {
        "strategy": "XAUUSD_V27_Clean_MultiSetup",
        "verdict": verdict,
        "reasons": reasons,
        "deposit": args.deposit,
        "final_balance_reported": final_balance,
        "final_balance_reconstructed": round(args.deposit + overall["net_profit"], 2),
        "unique_deals": len(deals),
        "overall": overall,
        "by_direction": group_stats(trades, "direction", args.deposit),
        "by_setup": group_stats(trades, "setup", args.deposit),
        "execution_errors_unique": errors,
        "data_quality": data_quality,
        "files_scanned": len(texts),
    }

    write_trades(root, trades)
    (root / "V27_ANALYSIS.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
