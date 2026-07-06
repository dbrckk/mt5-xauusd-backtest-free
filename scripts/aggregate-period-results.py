import argparse
import json
from pathlib import Path
from typing import Any


def parse_named_path(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected NAME=PATH")
    name, raw_path = value.split("=", 1)
    name = name.strip()
    path = Path(raw_path).expanduser()
    if not name:
        raise argparse.ArgumentTypeError("period name is empty")
    if not path.is_file():
        raise argparse.ArgumentTypeError(f"file not found: {path}")
    return name, path


def load_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit(f"cannot read JSON {path}: {exc}") from exc


def as_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def as_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def period_summary(name: str, payload: dict[str, Any]) -> dict[str, Any]:
    overall = payload.get("overall") or {}
    monthly = payload.get("monthly_objective") or {}
    quality = payload.get("data_quality") or {}
    errors = payload.get("execution_errors_unique") or {}
    return {
        "name": name,
        "verdict": payload.get("verdict"),
        "trades": as_int(overall.get("trades")),
        "wins": as_int(overall.get("wins")),
        "losses": as_int(overall.get("losses")),
        "win_rate": overall.get("win_rate"),
        "gross_profit": as_float(overall.get("gross_profit")),
        "gross_loss": as_float(overall.get("gross_loss")),
        "profit_factor": overall.get("profit_factor"),
        "net_profit": as_float(overall.get("net_profit")),
        "return_pct_of_initial": overall.get("return_pct_of_initial"),
        "max_drawdown_pct": overall.get("max_drawdown_pct"),
        "overnight_trades": as_int(overall.get("overnight_trades")),
        "active_months": as_int(monthly.get("active_months")),
        "months_meeting_target": as_int(monthly.get("months_meeting_target")),
        "negative_months": as_int(monthly.get("negative_months")),
        "average_monthly_return_pct_of_initial": monthly.get(
            "average_monthly_return_pct_of_initial"
        ),
        "min_monthly_net_profit": monthly.get("min_monthly_net_profit"),
        "max_monthly_net_profit": monthly.get("max_monthly_net_profit"),
        "data_quality_available": bool(quality.get("available")),
        "synthetic_fill_bars": as_int(quality.get("synthetic_fill_bars"), -1),
        "hour_success_ratio": quality.get("hour_success_ratio"),
        "execution_errors_total": sum(as_int(value) for value in errors.values()),
        "execution_errors": errors,
    }


def aggregate_periods(periods: list[dict[str, Any]], policy: dict[str, Any]) -> dict[str, Any]:
    target_wr = as_float(
        policy.get("experimental_targets", {}).get("minimum_validated_win_rate"),
        0.70,
    )
    target_monthly = as_float(
        policy.get("experimental_targets", {}).get(
            "minimum_average_monthly_return_pct_of_initial"
        ),
        5.0,
    )
    maximum_overnight = as_int(
        policy.get("hard_constraints", {}).get("maximum_overnight_trades"),
        0,
    )
    all_periods_positive_required = bool(
        policy.get("acceptance_rules", {}).get("all_periods_must_be_net_positive", True)
    )

    trades = sum(item["trades"] for item in periods)
    wins = sum(item["wins"] for item in periods)
    gross_profit = sum(item["gross_profit"] for item in periods)
    gross_loss = sum(item["gross_loss"] for item in periods)
    net_profit = sum(item["net_profit"] for item in periods)
    active_months = sum(item["active_months"] for item in periods)
    months_meeting_target = sum(item["months_meeting_target"] for item in periods)
    negative_months = sum(item["negative_months"] for item in periods)
    overnight = sum(item["overnight_trades"] for item in periods)
    execution_errors = sum(item["execution_errors_total"] for item in periods)

    win_rate = wins / trades if trades else None
    profit_factor = gross_profit / gross_loss if gross_loss > 0 else None

    weighted_monthly_numerator = 0.0
    weighted_monthly_denominator = 0
    for item in periods:
        value = item.get("average_monthly_return_pct_of_initial")
        months = item["active_months"]
        if value is None or months <= 0:
            continue
        weighted_monthly_numerator += as_float(value) * months
        weighted_monthly_denominator += months
    average_monthly = (
        weighted_monthly_numerator / weighted_monthly_denominator
        if weighted_monthly_denominator
        else None
    )

    positive_periods = sum(1 for item in periods if item["net_profit"] > 0)
    data_quality_pass = all(
        item["data_quality_available"] and item["synthetic_fill_bars"] == 0
        for item in periods
    )
    all_periods_positive = positive_periods == len(periods)

    checks = {
        "win_rate_target": win_rate is not None and win_rate >= target_wr,
        "monthly_return_target": average_monthly is not None
        and average_monthly >= target_monthly,
        "strict_intraday": overnight <= maximum_overnight,
        "all_periods_positive": (
            all_periods_positive if all_periods_positive_required else True
        ),
        "data_quality": data_quality_pass,
        "execution_errors": execution_errors == 0,
    }
    objective_validated = all(checks.values())

    gaps = {
        "win_rate_percentage_points": None
        if win_rate is None
        else round((target_wr - win_rate) * 100.0, 4),
        "monthly_return_percentage_points": None
        if average_monthly is None
        else round(target_monthly - average_monthly, 4),
    }

    if objective_validated:
        next_action = "freeze_strategy_and_document_validation"
    elif not checks["data_quality"] or not checks["execution_errors"]:
        next_action = "fix_test_infrastructure_before_strategy_changes"
    elif not checks["strict_intraday"]:
        next_action = "fix_intraday_rule_before_strategy_changes"
    elif not checks["all_periods_positive"]:
        next_action = "improve_cross_period_core_robustness"
    elif not checks["win_rate_target"]:
        next_action = "improve_signal_quality_without_increasing_risk"
    else:
        next_action = "increase_independent_opportunity_count_without_relaxing_weak_cells"

    return {
        "targets": {
            "minimum_validated_win_rate": target_wr,
            "minimum_average_monthly_return_pct_of_initial": target_monthly,
            "maximum_overnight_trades": maximum_overnight,
        },
        "aggregate": {
            "period_count": len(periods),
            "trades": trades,
            "wins": wins,
            "win_rate": round(win_rate, 6) if win_rate is not None else None,
            "profit_factor": round(profit_factor, 6)
            if profit_factor is not None
            else None,
            "net_profit": round(net_profit, 2),
            "active_months": active_months,
            "months_meeting_target": months_meeting_target,
            "negative_months": negative_months,
            "average_monthly_return_pct_of_initial": round(average_monthly, 6)
            if average_monthly is not None
            else None,
            "positive_periods": positive_periods,
            "overnight_trades": overnight,
            "execution_errors_total": execution_errors,
        },
        "checks": checks,
        "objective_validated": objective_validated,
        "objective_gaps": gaps,
        "next_action": next_action,
        "periods": periods,
    }


def render_markdown(result: dict[str, Any]) -> str:
    aggregate = result["aggregate"]
    checks = result["checks"]
    lines = [
        "# Cross-period objective summary",
        "",
        f"Objective validated: **{'YES' if result['objective_validated'] else 'NO'}**",
        "",
        "## Aggregate",
        "",
        "| Metric | Result |",
        "|---|---:|",
        f"| Trades | {aggregate['trades']} |",
        f"| Win rate | {aggregate['win_rate']} |",
        f"| Profit factor | {aggregate['profit_factor']} |",
        f"| Net profit | {aggregate['net_profit']} |",
        f"| Active months | {aggregate['active_months']} |",
        f"| Months meeting target | {aggregate['months_meeting_target']} |",
        f"| Negative months | {aggregate['negative_months']} |",
        f"| Average monthly return vs initial capital | {aggregate['average_monthly_return_pct_of_initial']}% |",
        f"| Positive periods | {aggregate['positive_periods']} / {aggregate['period_count']} |",
        f"| Overnight trades | {aggregate['overnight_trades']} |",
        f"| Execution errors | {aggregate['execution_errors_total']} |",
        "",
        "## Validation checks",
        "",
    ]
    for name, passed in checks.items():
        lines.append(f"- {'PASS' if passed else 'FAIL'} — {name}")
    lines.extend(
        [
            "",
            "## Periods",
            "",
            "| Period | Trades | WR | PF | Net | Overnight | Errors |",
            "|---|---:|---:|---:|---:|---:|---:|",
        ]
    )
    for item in result["periods"]:
        lines.append(
            f"| {item['name']} | {item['trades']} | {item['win_rate']} | "
            f"{item['profit_factor']} | {item['net_profit']} | "
            f"{item['overnight_trades']} | {item['execution_errors_total']} |"
        )
    lines.extend(
        [
            "",
            f"Next action: `{result['next_action']}`",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Aggregate independent period analyses against the fixed demo research objective."
    )
    parser.add_argument(
        "--period",
        action="append",
        required=True,
        type=parse_named_path,
        help="Analysis JSON using NAME=PATH. Repeat for every validation period.",
    )
    parser.add_argument(
        "--policy",
        type=Path,
        default=Path("research/objective-policy.json"),
    )
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--markdown-output", type=Path)
    args = parser.parse_args()

    if not args.policy.is_file():
        raise SystemExit(f"policy file not found: {args.policy}")
    policy = load_json(args.policy)

    names = [name for name, _ in args.period]
    if len(set(names)) != len(names):
        raise SystemExit("period names must be unique")

    periods = [period_summary(name, load_json(path)) for name, path in args.period]
    result = aggregate_periods(periods, policy)

    json_payload = json.dumps(result, indent=2, ensure_ascii=False)
    markdown_payload = render_markdown(result)

    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json_payload, encoding="utf-8")
    if args.markdown_output:
        args.markdown_output.parent.mkdir(parents=True, exist_ok=True)
        args.markdown_output.write_text(markdown_payload, encoding="utf-8")

    print(json_payload)
    return 0 if result["objective_validated"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
