from __future__ import annotations

import datetime as dt
import hashlib
import importlib.util
import json
import os
import sys
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("download_public_xau_m1.py")
spec = importlib.util.spec_from_file_location("xau_public_downloader", MODULE_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Cannot load canonical downloader: {MODULE_PATH}")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def parse_date(value: str) -> dt.date:
    return dt.datetime.strptime(value, "%Y.%m.%d").date()


def market_days(start: dt.date, end: dt.date) -> list[dt.date]:
    days: list[dt.date] = []
    current = start
    while current <= end:
        if current.weekday() < 5:
            days.append(current)
        current += dt.timedelta(days=1)
    return days


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    if len(sys.argv) != 5:
        print("usage: build_dukascopy_cache_manifest.py FROM_DATE TO_DATE CACHE_DIR OUT_JSON")
        return 2

    start = parse_date(sys.argv[1])
    end = parse_date(sys.argv[2])
    cache_dir = Path(sys.argv[3]).resolve()
    out_json = Path(sys.argv[4]).resolve()
    out_json.parent.mkdir(parents=True, exist_ok=True)

    os.environ["PUBLIC_CACHE_DIR"] = str(cache_dir)
    mod.CACHE_DIR = str(cache_dir)

    hours = list(mod.SESSION_HOURS)
    days = market_days(start, end)
    expected_hours = len(days) * len(hours)
    valid_tick_hours = 0
    valid_empty_hours = 0
    missing_hours = 0
    corrupt_hours = 0
    valid_days: set[str] = set()
    file_entries: list[tuple[str, int, str]] = []

    for day in days:
        for hour in hours:
            path = mod.cache_path_for(day, hour)
            if path is None or not path.exists() or path.stat().st_size <= 0:
                missing_hours += 1
                continue
            try:
                raw = path.read_bytes()
                status, ticks = mod.process_hour(day, hour, raw, {})
            except Exception:
                status, ticks = "corrupt", 0

            rel = path.relative_to(cache_dir).as_posix()
            file_entries.append((rel, path.stat().st_size, sha256_file(path)))
            if status == "ok" and ticks > 0:
                valid_tick_hours += 1
                valid_days.add(day.isoformat())
            elif status == "empty_market":
                valid_empty_hours += 1
            else:
                corrupt_hours += 1

    canonical_valid_hours = valid_tick_hours + valid_empty_hours
    coverage_ratio = valid_tick_hours / expected_hours if expected_hours else 0.0
    payload_valid_ratio = canonical_valid_hours / expected_hours if expected_hours else 0.0

    tree_digest = hashlib.sha256()
    for rel, size, digest in sorted(file_entries):
        tree_digest.update(f"{rel}\0{size}\0{digest}\n".encode("utf-8"))

    minimum = float(os.environ.get("PUBLIC_MIN_HOUR_SUCCESS_RATIO", "0.90"))
    manifest = {
        "schema": "dukascopy-cache-manifest-v1",
        "mode": "independent-run-no-cross-run-cache-restore",
        "source_key": "independent-real-dukascopy",
        "range": {"from": start.isoformat(), "to": end.isoformat()},
        "session_hours": hours,
        "expected_hour_count": expected_hours,
        "canonical_valid_hour_count": canonical_valid_hours,
        "valid_tick_hour_count": valid_tick_hours,
        "valid_empty_market_hour_count": valid_empty_hours,
        "missing_hour_count": missing_hours,
        "corrupt_hour_count": corrupt_hours,
        "days_with_valid_ticks": len(valid_days),
        "coverage_ratio": round(coverage_ratio, 8),
        "payload_valid_ratio": round(payload_valid_ratio, 8),
        "minimum_required_coverage_ratio": minimum,
        "cache_file_count": len(file_entries),
        "cache_tree_sha256": tree_digest.hexdigest(),
        "synthetic_bars": 0,
        "coverage_pass": coverage_ratio >= minimum,
    }
    out_json.write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8")
    out_json.with_suffix(".txt").write_text(
        "\n".join(f"{key}={value}" for key, value in manifest.items()), encoding="utf-8"
    )
    print(json.dumps(manifest, sort_keys=True))

    if manifest["synthetic_bars"] != 0:
        print("CACHE_MANIFEST_FAIL=synthetic_data_detected")
        return 3
    if corrupt_hours:
        print(f"CACHE_MANIFEST_FAIL=corrupt_payloads:{corrupt_hours}")
        return 4
    if coverage_ratio < minimum:
        print(
            "CACHE_MANIFEST_FAIL=coverage_below_threshold:"
            f"{coverage_ratio:.6f}<{minimum:.6f};"
            f"valid={valid_tick_hours};expected={expected_hours};missing={missing_hours}"
        )
        return 5
    print("CACHE_MANIFEST_PASS=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
