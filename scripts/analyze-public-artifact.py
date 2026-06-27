import argparse
import json
import re
import zipfile
from pathlib import Path

ENTRY_PATTERNS = ["OPEN BUY", "OPEN SELL", "OPEN_ENTRY"]
ERROR_PATTERNS = ["Invalid stops", "Invalid price", "failed instant buy", "failed instant sell", "failed modify"]
EXIT_PATTERNS = [
    "PUBLIC_20_POINT_PROFIT_EXIT",
    "PUBLIC_RISK_CUT",
    "TIMED_PROFIT_EXIT",
    "BASKET_TP",
    "EMERGENCY_ATR_CLOSE",
]

REQUIRED_MARKERS = [
    "CURRENT_PUBLIC_XAU_ONLY",
    "compile_safe_patch_script=applied",
    "tester_setlines_warmup_injection=true",
    "public_no_sl_orders=true",
    "public_intraday_frequency_profile=true",
    "public_focus_sessions=london_ny",
]

PROFILE_MARKERS = [
    "public_20_30_point_runtime_set=true",
    "public_20_30_point_profile=true",
    "public_20_30_point_exit=true",
    "public_risk_cut=true",
    "public_start_end_session_locked=true",
]

IMPORTANT_SET_VALUES = [
    "InpMaxNewEntriesPerDay=4",
    "InpUseBasketTimeProfitExit=true",
    "InpBasketTimeProfitMinutes=180",
    "InpMinTimedExitProfitPct=0.20",
    "InpUseATRAccelerationFilter=false",
    "InpMaxATRAccelerationRatio=9.99",
]


def decode_text(data: bytes) -> str:
    candidates = []
    for enc in ("utf-8", "utf-16", "utf-16le", "latin1"):
        try:
            txt = data.decode(enc, errors="replace")
            candidates.append((txt[:2000].count("\x00"), -len(txt), txt))
        except Exception:
            continue
    if not candidates:
        return data.decode("utf-8", errors="replace")
    candidates.sort(key=lambda x: (x[0], x[1]))
    return candidates[0][2]


def read_zip_texts(path: Path) -> dict[str, str]:
    out = {}
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if name.lower().endswith((".txt", ".log", ".ini", ".set", ".csv", ".html", ".htm", ".json")):
                out[name] = decode_text(z.read(name))
    return out


def find_final_balance(blob: str) -> float | None:
    for pat in (
        r"final balance\s+([0-9]+(?:\.[0-9]+)?)\s+USD",
        r"Final balance</td><td>([0-9]+(?:\.[0-9]+)?)\s+USD",
        r"Final balance.*?([0-9]+(?:\.[0-9]+)?)\s+USD",
    ):
        m = re.search(pat, blob, re.IGNORECASE | re.DOTALL)
        if m:
            return float(m.group(1))
    return None


def count_hits(blob: str, patterns: list[str]) -> dict[str, int]:
    return {p: blob.count(p) for p in patterns if blob.count(p) > 0}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("zip_path")
    parser.add_argument("--deposit", type=float, default=10000.0)
    args = parser.parse_args()

    texts = read_zip_texts(Path(args.zip_path))
    blob = "\n".join(texts.values())

    marker_status = {m: (m in blob) for m in REQUIRED_MARKERS}
    profile_status = {m: (m in blob) for m in PROFILE_MARKERS}
    set_status = {m: (m in blob) for m in IMPORTANT_SET_VALUES}
    exits = count_hits(blob, EXIT_PATTERNS)
    entries = count_hits(blob, ENTRY_PATTERNS)
    errors = count_hits(blob, ERROR_PATTERNS)
    balance = find_final_balance(blob)

    deal_count = len(re.findall(r"\bdeal #\d+\b", blob))
    failed_orders = errors.get("failed instant buy", 0) + errors.get("failed instant sell", 0)
    failed_modify = errors.get("failed modify", 0)
    invalid_stops = errors.get("Invalid stops", 0)
    open_entries = entries.get("OPEN_ENTRY", 0)
    run_completed = "run_public_backtest_exit_code=0" in blob or "Test passed" in blob or balance is not None

    verdict = "UNKNOWN"
    reasons = []
    if not all(marker_status.values()):
        verdict = "STALE_OR_WRONG_ARTIFACT"
        reasons.append("Required workflow markers are missing: " + ", ".join(k for k, v in marker_status.items() if not v))
    elif not run_completed:
        verdict = "RUN_NOT_COMPLETED"
        reasons.append("MT5 run did not complete; no final balance/test result was found.")
    elif not entries and deal_count == 0:
        verdict = "NO_TRADES"
        reasons.append("No entry or deal markers found.")
    elif open_entries < 10:
        verdict = "UNDERTRADING"
        reasons.append(f"Too few entries for the intraday objective: {open_entries}.")
    elif failed_orders > 160 or failed_modify > 50 or invalid_stops > 50:
        verdict = "EXECUTION_NOISE_TOO_HIGH"
        reasons.append(f"Execution noise too high: failed_orders={failed_orders}, failed_modify={failed_modify}, invalid_stops={invalid_stops}.")
    elif balance is not None and balance < args.deposit:
        verdict = "TRADES_NEGATIVE"
        reasons.append(f"Final balance {balance:.2f} is below deposit {args.deposit:.2f}.")
    elif balance is not None and balance >= args.deposit:
        verdict = "PASSABLE"
        reasons.append(f"Final balance {balance:.2f} is at or above deposit {args.deposit:.2f}.")

    print(json.dumps({
        "verdict": verdict,
        "final_balance": balance,
        "deal_count": deal_count,
        "failed_orders": failed_orders,
        "failed_modify": failed_modify,
        "invalid_stops": invalid_stops,
        "open_entries": open_entries,
        "target_entries_per_day": "2-3",
        "target_profit_points": "20-30",
        "focus_sessions": "London + New York",
        "entries": entries,
        "exits": exits,
        "errors": errors,
        "markers": marker_status,
        "profile_markers": profile_status,
        "important_tester_inputs": set_status,
        "reasons": reasons,
        "files_scanned": len(texts),
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
