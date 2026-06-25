import argparse
import json
import re
import zipfile
from pathlib import Path

EXIT_PATTERNS = [
    "FAST_LOSER_CUT",
    "SCORE_DIVERGENCE_EXIT",
    "SIGNAL_DECAY_EXIT",
    "RUNNER_EXHAUSTED",
    "BASKET_PROFIT_LOCK",
    "V17_ELASTIC_PROFIT_LOCK",
    "V14_RUNNER_MFE_GUARD",
]

ENTRY_PATTERNS = [
    "OPEN BUY",
    "OPEN SELL",
    "OPEN_ENTRY",
]

REQUIRED_MARKERS = [
    "CURRENT_PUBLIC_XAU_ONLY",
    "compile_safe_patch_script=applied",
    "tester_setlines_warmup_injection=true",
]

REQUIRED_SET_VALUES = [
    "InpMacroTF=16385",
    "InpTrendTF=16385",
    "InpSlowEMA=34",
    "InpMacroEMA=34",
    "InpSignalEMA=20",
    "InpOneDecisionPerBar=false",
    "InpUseScoreDivergenceExit=false",
    "InpUseSignalDecayExit=false",
    "InpCloseOnRunnerExhaustion=false",
]


def read_zip_texts(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            lower = name.lower()
            if lower.endswith((".txt", ".log", ".ini", ".set", ".csv", ".html", ".htm")):
                try:
                    out[name] = z.read(name).decode("utf-8", errors="replace")
                except Exception:
                    out[name] = z.read(name).decode("utf-16", errors="replace")
    return out


def find_final_balance(blob: str) -> float | None:
    patterns = [
        r"final balance\s+([0-9]+(?:\.[0-9]+)?)\s+USD",
        r"Final balance</td><td>([0-9]+(?:\.[0-9]+)?)\s+USD",
        r"Final balance.*?([0-9]+(?:\.[0-9]+)?)\s+USD",
    ]
    for pat in patterns:
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
    set_status = {m: (m in blob) for m in REQUIRED_SET_VALUES}
    exits = count_hits(blob, EXIT_PATTERNS)
    entries = count_hits(blob, ENTRY_PATTERNS)
    balance = find_final_balance(blob)

    verdict = "UNKNOWN"
    reasons: list[str] = []

    if not all(marker_status.values()):
        verdict = "STALE_OR_WRONG_ARTIFACT"
        reasons.append("Required workflow markers are missing.")
    elif not all(set_status.values()):
        verdict = "SET_NOT_PATCHED"
        reasons.append("Required Strategy Tester inputs are missing from the artifact.")
    elif not entries:
        verdict = "NO_TRADES"
        reasons.append("No entry markers found.")
    elif exits:
        verdict = "EXITS_TOO_AGGRESSIVE"
        reasons.append("Exit markers found: " + ", ".join(f"{k}={v}" for k, v in exits.items()))
    elif balance is not None and balance < args.deposit:
        verdict = "TRADES_NEGATIVE"
        reasons.append(f"Final balance {balance:.2f} is below deposit {args.deposit:.2f}.")
    elif balance is not None and balance >= args.deposit:
        verdict = "PASSABLE"
        reasons.append(f"Final balance {balance:.2f} is at or above deposit {args.deposit:.2f}.")

    result = {
        "verdict": verdict,
        "final_balance": balance,
        "entries": entries,
        "exits": exits,
        "markers": marker_status,
        "tester_inputs": set_status,
        "reasons": reasons,
        "files_scanned": len(texts),
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
