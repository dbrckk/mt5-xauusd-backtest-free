import argparse
import json
import re
from pathlib import Path

TEXT_EXTENSIONS = {".txt", ".log", ".ini", ".set", ".csv", ".html", ".htm", ".json"}


def decode_text(data: bytes) -> str:
    candidates = []
    for enc in ("utf-8", "utf-16", "utf-16le", "cp1252", "latin1"):
        try:
            text = data.decode(enc, errors="replace")
            candidates.append((text[:2000].count("\x00"), -len(text), text))
        except Exception:
            pass
    if not candidates:
        return data.decode("utf-8", errors="replace")
    candidates.sort(key=lambda item: (item[0], item[1]))
    return candidates[0][2]


def read_all_texts(root: Path) -> dict[str, str]:
    out = {}
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in TEXT_EXTENSIONS:
            try:
                out[str(path.relative_to(root))] = decode_text(path.read_bytes())
            except Exception:
                continue
    return out


def final_balance_from_blob(blob: str) -> float | None:
    patterns = [
        r"final balance\s+([0-9]+(?:\.[0-9]+)?)\s+USD",
        r"Final balance</td><td>([0-9]+(?:\.[0-9]+)?)\s+USD",
        r"Final balance.*?([0-9]+(?:\.[0-9]+)?)\s+USD",
    ]
    for pattern in patterns:
        match = re.search(pattern, blob, re.IGNORECASE | re.DOTALL)
        if match:
            return float(match.group(1))
    return None


def extract_journal_lines(texts: dict[str, str]) -> list[str]:
    lines = []
    for name, text in texts.items():
        if "journal" in name.lower() and name.lower().endswith(".csv"):
            lines.extend([line.strip() for line in text.splitlines() if line.strip()])
    return lines


def line_direction(line: str) -> str | None:
    upper = line.upper()
    if "BUY" in upper:
        return "BUY"
    if "SELL" in upper:
        return "SELL"
    return None


def first_timestamp(line: str) -> str | None:
    match = re.search(r"\b20\d{2}[./-]\d{2}[./-]\d{2}\s+\d{2}:\d{2}:\d{2}\b", line)
    return match.group(0) if match else None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reports_dir")
    parser.add_argument("--deposit", type=float, default=10000.0)
    args = parser.parse_args()

    root = Path(args.reports_dir)
    texts = read_all_texts(root)
    blob = "\n".join(texts.values())
    journal_lines = extract_journal_lines(texts)

    open_lines = [line for line in journal_lines if "OPEN_ENTRY" in line]
    recovery_lines = [line for line in journal_lines if "OPEN_RECOVERY" in line]
    exit_lines = [line for line in journal_lines if "_EXIT" in line or "_CLOSE" in line or "BASKET_TP" in line]

    directions = [line_direction(line) for line in open_lines]
    directions = [d for d in directions if d]
    direction_switches = sum(1 for i in range(1, len(directions)) if directions[i] != directions[i - 1])

    invalid_stops = blob.count("Invalid stops")
    failed_modify = blob.count("failed modify")
    failed_orders = blob.count("failed instant buy") + blob.count("failed instant sell")
    balance = final_balance_from_blob(blob)
    net_profit = None if balance is None else round(balance - args.deposit, 2)

    verdict = "UNKNOWN"
    reasons = []

    if not journal_lines:
        verdict = "NO_JOURNAL"
        reasons.append("No CSV journal was found in reports.")
    elif invalid_stops > 50 or failed_modify > 50 or failed_orders > 50:
        verdict = "EXECUTION_QUALITY_FAIL"
        reasons.append(f"Execution noise too high: invalid_stops={invalid_stops}, failed_modify={failed_modify}, failed_orders={failed_orders}.")
    elif len(open_lines) == 0:
        verdict = "NO_ENTRY"
        reasons.append("No OPEN_ENTRY found.")
    elif len(open_lines) > 2:
        verdict = "TOO_MANY_ENTRIES"
        reasons.append(f"Sparse public profile expected <=2 entries, got {len(open_lines)}.")
    elif direction_switches > 0:
        verdict = "DIRECTION_SWITCH"
        reasons.append(f"Sparse validation should avoid direction switching, got {direction_switches} switch(es).")
    elif balance is None:
        verdict = "NO_BALANCE"
        reasons.append("No final balance found.")
    elif balance < args.deposit:
        verdict = "NEGATIVE_RESULT"
        reasons.append(f"Final balance {balance:.2f} below deposit {args.deposit:.2f}.")
    else:
        verdict = "CLEAN_SPARSE_PASS"
        reasons.append(f"Sparse validation passed with {len(open_lines)} entry/entries and net profit {net_profit:.2f}.")

    result = {
        "verdict": verdict,
        "final_balance": balance,
        "net_profit": net_profit,
        "open_entries": len(open_lines),
        "recovery_entries": len(recovery_lines),
        "exit_events": len(exit_lines),
        "directions": directions,
        "direction_switches": direction_switches,
        "first_entry_time": first_timestamp(open_lines[0]) if open_lines else None,
        "last_entry_time": first_timestamp(open_lines[-1]) if open_lines else None,
        "invalid_stops": invalid_stops,
        "failed_modify": failed_modify,
        "failed_orders": failed_orders,
        "journal_lines": len(journal_lines),
        "files_scanned": len(texts),
        "reasons": reasons,
    }

    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
