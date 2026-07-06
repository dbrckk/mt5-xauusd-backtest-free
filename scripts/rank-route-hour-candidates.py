import argparse
import csv
import itertools
import json
import math
from collections import defaultdict
from pathlib import Path


def parse_period_arg(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("period must use NAME=PATH")
    name, raw_path = value.split("=", 1)
    name = name.strip()
    path = Path(raw_path).expanduser()
    if not name:
        raise argparse.ArgumentTypeError("period name is empty")
    if not path.is_file():
        raise argparse.ArgumentTypeError(f"trade CSV not found: {path}")
    return name, path


def load_rows(periods: list[tuple[str, Path]]) -> list[dict]:
    rows: list[dict] = []
    for period, path in periods:
        with path.open("r", encoding="utf-8", errors="replace", newline="") as handle:
            for row in csv.DictReader(handle):
                try:
                    profit = float(row["profit_money"])
                    hour = int(row["entry_hour"])
                except (KeyError, TypeError, ValueError):
                    continue
                rows.append(
                    {
                        "period": period,
                        "route": str(row.get("route") or "UNKNOWN"),
                        "hour": hour,
                        "profit": profit,
                    }
                )
    return rows


def stats(rows: list[dict]) -> dict:
    count = len(rows)
    if count == 0:
        return {
            "trades": 0,
            "wins": 0,
            "win_rate": None,
            "profit_factor": None,
            "net_profit": 0.0,
        }
    wins = sum(1 for row in rows if row["profit"] > 0)
    gross_profit = sum(max(0.0, row["profit"]) for row in rows)
    gross_loss = -sum(min(0.0, row["profit"]) for row in rows)
    profit_factor = gross_profit / gross_loss if gross_loss > 0 else None
    return {
        "trades": count,
        "wins": wins,
        "win_rate": round(wins / count, 6),
        "profit_factor": round(profit_factor, 6) if profit_factor is not None else None,
        "net_profit": round(sum(row["profit"] for row in rows), 2),
    }


def evaluate_combo(
    rows: list[dict],
    cells: tuple[tuple[str, int], ...],
    period_names: list[str],
) -> dict:
    selected = [row for row in rows if (row["route"], row["hour"]) in cells]
    overall = stats(selected)
    by_period = {
        period: stats([row for row in selected if row["period"] == period])
        for period in period_names
    }
    active_periods = sum(1 for item in by_period.values() if item["trades"] > 0)
    positive_periods = sum(1 for item in by_period.values() if item["net_profit"] > 0)
    period_win_rates = [
        item["win_rate"] for item in by_period.values() if item["win_rate"] is not None
    ]
    period_profit_factors = [
        item["profit_factor"]
        for item in by_period.values()
        if item["profit_factor"] is not None
    ]
    minimum_period_win_rate = min(period_win_rates) if period_win_rates else None
    minimum_period_profit_factor = min(period_profit_factors) if period_profit_factors else None

    overall_wr = overall["win_rate"] or 0.0
    overall_pf = overall["profit_factor"] or 5.0
    minimum_wr = minimum_period_win_rate or 0.0
    sample_bonus = math.log1p(overall["trades"])
    robustness_score = (
        positive_periods * 100.0
        + active_periods * 20.0
        + overall_wr * 50.0
        + minimum_wr * 30.0
        + min(overall_pf, 5.0) * 10.0
        + sample_bonus
    )

    return {
        "cells": [{"route": route, "entry_hour": hour} for route, hour in cells],
        "overall": overall,
        "by_period": by_period,
        "active_periods": active_periods,
        "positive_periods": positive_periods,
        "minimum_period_win_rate": minimum_period_win_rate,
        "minimum_period_profit_factor": minimum_period_profit_factor,
        "robustness_score": round(robustness_score, 6),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Rank route-hour subsets across independent backtest periods."
    )
    parser.add_argument(
        "--period",
        action="append",
        required=True,
        type=parse_period_arg,
        help="Period trade CSV using NAME=PATH. Repeat for each period.",
    )
    parser.add_argument("--minimum-trades", type=int, default=50)
    parser.add_argument("--top", type=int, default=25)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    period_names = [name for name, _ in args.period]
    if len(set(period_names)) != len(period_names):
        raise SystemExit("period names must be unique")

    rows = load_rows(args.period)
    if not rows:
        raise SystemExit("no valid trades found")

    cells = sorted({(row["route"], row["hour"]) for row in rows})
    candidates: list[dict] = []
    for size in range(1, len(cells) + 1):
        for combination in itertools.combinations(cells, size):
            result = evaluate_combo(rows, combination, period_names)
            if result["overall"]["trades"] < args.minimum_trades:
                continue
            candidates.append(result)

    candidates.sort(
        key=lambda item: (
            item["positive_periods"],
            item["active_periods"],
            item["robustness_score"],
            item["overall"]["profit_factor"] or 999.0,
            item["overall"]["win_rate"] or 0.0,
        ),
        reverse=True,
    )

    result = {
        "periods": period_names,
        "trades_loaded": len(rows),
        "route_hour_cells": [
            {"route": route, "entry_hour": hour} for route, hour in cells
        ],
        "minimum_trades": args.minimum_trades,
        "candidate_count": len(candidates),
        "top_candidates": candidates[: max(1, args.top)],
    }

    payload = json.dumps(result, indent=2, ensure_ascii=False)
    if args.output:
        args.output.write_text(payload, encoding="utf-8")
    print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
