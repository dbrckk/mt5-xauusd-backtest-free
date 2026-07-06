# mt5-xauusd-backtest-free

Deterministic MT5 backtesting for XAUUSD using free public market data and GitHub Actions.

## Research scope

This repository is an educational, demo-only research project. It is not a real-money trading system and must not be used for live deployment.

The fixed objective policy is stored in:

`research/objective-policy.json`

Fixed experimental targets:

- XAUUSD / `XAU_PUBLIC`
- M15 execution timeframe
- initial capital reference: 15,000 USD
- strict intraday operation
- zero overnight trades
- no weekend positions
- validated win rate >= 70%
- average monthly progress versus initial capital >= 5%
- all validation periods net-positive
- data quality pass
- source immutability pass
- zero execution errors
- post-filter estimates are not validation

## Current branch state

Branch: `autonomous-demo-research`

Latest validated strategy source at the current research head:

`MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5`

The filename is historical. The source currently identifies as V2.89 / V28 Contextual Router with a strict sweep-edge extension.

The active workflow path is also historical:

`.github/workflows/ea-v26-3y.yml`

It currently runs the V28 contextual validation matrix over four independent periods:

| Period | Range |
|---|---|
| Y0_OOS | 2022-06-21 to 2023-06-21 |
| Y1 | 2023-06-21 to 2024-06-21 |
| Y2 | 2024-06-21 to 2025-06-21 |
| Y3 | 2025-06-21 to 2026-06-21 |

## Effective strategy profile

The runner creates the effective tester profile at runtime:

`V28_CONTEXTUAL_RISK.set`

The effective profile uses:

- `UseRiskPercent=true`
- `RiskPercent=0.20`
- `MaxTradesPerDay=4`
- `CooldownMinutes=45`
- `SessionStartHour=7`
- `SessionEndHour=20`
- `LastEntryHour=19`
- `LastEntryMinute=15`
- `HardFlatHour=20`
- `HardFlatMinute=45`
- `CloseBeforeWeekend=true`
- `FridayCloseHour=19`
- `UseCSVJournal=true`
- `CSVJournalName=V28_CONTEXTUAL_journal.csv`

Risk must not be increased merely to manufacture the monthly-progress target.

## Current route set

Core validated hypothesis routes:

- `CORE_PULLBACK_BUY_15`
- `CORE_CONTINUATION_SELL_07_08`
- `CORE_SWEEP_SELL_13_14`

Experimental strict extension currently present in source:

- `EDGE_SWEEP_SELL_12_15_STRICT`

The extension is not treated as validated until fresh cross-period artifacts prove it under the fixed objective policy.

## Run 96 validation evidence

Workflow run:

`#96 / 28795916853`

Commit under test:

`8ec8c6738d21f6cf9152300180d730892de1ef93`

Status:

- GitHub Actions run completed successfully.
- Y0_OOS, Y1, Y2 and Y3 artifacts exist.
- All four artifacts are marked `INSUFFICIENT_SAMPLE`.
- Infrastructure success is not strategy validation.

Artifact-level summary from run artifact names:

| Period | Trades | Win rate | Profit factor | Net |
|---|---:|---:|---:|---:|
| Y0_OOS | 19 | 63.2% | 1.93 | +171 |
| Y1 | 14 | 71.4% | 2.80 | +185 |
| Y2 | 21 | 57.1% | 1.15 | +35 |
| Y3 | 23 | 78.3% | 3.86 | +375 |

Approximate aggregate from the same artifact summaries:

| Metric | Result |
|---|---:|
| Trades | 77 |
| Wins | 52 |
| Win rate | 67.53% |
| Net profit | +766 |
| Positive periods | 4 / 4 |

Objective status:

| Check | Status |
|---|---|
| Fresh four-period backtest | PASS |
| All period jobs complete | PASS |
| All periods net-positive | PASS |
| Strict intraday / zero overnight | pending exact aggregate check from JSON |
| Data quality | pending exact aggregate check from JSON |
| Execution errors | pending exact aggregate check from JSON |
| Win rate >= 70% | FAIL |
| Average monthly progress >= 5% | FAIL |

The strategy is therefore not validated.

## Research decision

The next valid research direction is:

1. Do not increase risk.
2. Do not force daily trades.
3. Do not relax historically weak route-hour cells.
4. Preserve the currently positive cross-period core.
5. Add or test only independent, strictly gated opportunity modules.
6. Re-run a fresh Y0_OOS/Y1/Y2/Y3 validation after any strategy change.
7. Accept no result until `scripts/aggregate-period-results.py` confirms the fixed policy.

## Tooling

Cross-period objective aggregation:

`scripts/aggregate-period-results.py`

Route-hour robustness ranking:

`scripts/rank-route-hour-candidates.py`

Both scripts are research aids. Their output must be based on fresh run artifacts, not post-filter assumptions.
