# mt5-xauusd-backtest-free

Deterministic MT5 backtesting for XAUUSD using free public market data and GitHub Actions.

This repository is for **educational demo-only EA research**. It is not validated for real-money deployment.

## Fixed objective policy

Policy file:

`research/objective-policy.json`

Current experimental targets:

- symbol: `XAUUSD` / test symbol `XAU_PUBLIC`;
- timeframe: `M15`;
- initial capital reference: `$15,000`;
- validated win rate target: `>= 70%`;
- average monthly return target versus initial capital: `>= 5%`;
- strict intraday operation;
- maximum overnight trades: `0`;
- real-money use: `false`.

Acceptance requires fresh validation across all configured periods and does not treat post-filter estimates as validation.

## Current strategy: V28 Core Edge Router

EA source:

`MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5`

The retained filename is historical. The committed strategy identity is now **V28 Core Edge Router**.

Active route-hour cells:

1. `CORE_PULLBACK_BUY_15`
2. `CORE_CONTINUATION_SELL_07_08`
3. `CORE_SWEEP_SELL_13_14`

The current V28 core deliberately removed weak historical cells such as broad `PULLBACK_BUY_13_16`, `BREAKOUT_BUY_07_08`, and broad `SWEEP_SELL_13_16`.

Default controls:

- one open position at a time;
- maximum 4 natural entries per day;
- 45-minute cooldown;
- 07:00-20:00 UTC session;
- last entry gate: 19:15 UTC;
- hard daily flat gate: 20:45 UTC;
- no new Friday entries after 17:00 UTC;
- weekend protection;
- setup-specific ATR TP/SL;
- risk percent: `0.20%` per trade;
- no forced daily trades;
- no runtime mutation of EA source.

## Latest completed validation

Workflow run:

`#96` / `28795916853`

Validated commit:

`8ec8c6738d21f6cf9152300180d730892de1ef93`

Merge commit:

`b3d2c9d484c9792309196d747fe2d58e9308e4b6`

Fresh four-period artifacts completed successfully for Y0_OOS, Y1, Y2, and Y3.

| Period | Trades | Win rate | Profit factor | Net profit | Artifact verdict |
|---|---:|---:|---:|---:|---|
| Y0_OOS | 19 | 63.2% | 1.93 | +$171 | INSUFFICIENT_SAMPLE |
| Y1 | 14 | 71.4% | 2.80 | +$185 | INSUFFICIENT_SAMPLE |
| Y2 | 21 | 57.1% | 1.15 | +$35 | INSUFFICIENT_SAMPLE |
| Y3 | 23 | 78.3% | 3.86 | +$375 | INSUFFICIENT_SAMPLE |

Approximate aggregate from artifact summaries:

| Metric | Result | Target | Status |
|---|---:|---:|---|
| Trades | 77 | sufficient sample required | fail |
| Wins | 52 | n/a | n/a |
| Win rate | 67.53% | >= 70% | fail |
| Net profit | +$766 | all periods positive | pass |
| Average monthly return vs initial | ~0.106% | >= 5% | fail |
| Overnight trades | not indicated in artifact names; job checks passed | 0 | pending artifact-level audit |
| Job status | all four jobs success | all complete | pass |

Conclusion: the V28 core is materially cleaner and cross-period positive, but the fixed policy objective is **not validated**. The main defects are insufficient sample size, win rate below 70%, and monthly return far below +5%.

## Active validation workflow

Workflow:

`.github/workflows/ea-v26-3y.yml`

The path is retained for continuity, but the workflow now validates V28.

Matrix:

| Chunk | Period |
|---|---|
| Y0_OOS | 2022-06-21 to 2023-06-21 |
| Y1 | 2023-06-21 to 2024-06-21 |
| Y2 | 2024-06-21 to 2025-06-21 |
| Y3 | 2025-06-21 to 2026-06-21 |

Triggering paths are intentionally narrow. Avoid touching workflow-triggering files while a validation run is active because concurrency cancels in-progress tests.

## Public history rules

Downloader:

`scripts/download_public_xau_m1.py`

The active downloader:

- downloads real Dukascopy XAUUSD ticks across the full 24-hour market context;
- uses bounded concurrency and retry rounds;
- caches hourly `.bi5` files;
- processes each downloaded hour immediately to keep memory bounded;
- writes only minutes containing real ticks;
- never fills missing minutes with flat synthetic OHLC;
- hashes the final CSV dataset;
- records real coverage diagnostics;
- fails the run when minimum coverage is not reached.

The EA opens new trades only during its configured intraday entry window. Full-day history is used so M15/H1/H4 indicators are calculated from the real surrounding market context rather than a truncated session.

Default quality gates:

- at least 250,000 real M1 bars;
- at least 220 days with ticks;
- at least 90% successful non-404 requested hours;
- exactly 0 synthetic fill bars.

## Custom symbol margin fix

`MQL5/Experts/ImportCustomRatesEA.mq5`

`XAU_PUBLIC` uses `SYMBOL_CALC_MODE_CFDLEVERAGE` so custom-symbol margin does not consume the full gold notional in the tester account.

## Deterministic runner

`scripts/run-ea-v27-public-backtest.ps1`

The runner compiles and executes the committed source directly.

It does not:

- patch the EA;
- inject a mandatory trade;
- disable one direction;
- change the session;
- change TP/SL during CI.

The committed source and effective `.set` profile must remain aligned before interpreting validation results.

## Next justified research direction

Do not increase risk to manufacture the +5% target.

The next improvement should preserve the robust V28 core and add only independently gated opportunity modules that can increase sample size without reopening historically weak route-hour cells. Candidate work should be validated by fresh Y0_OOS/Y1/Y2/Y3 backtests before being treated as evidence.
