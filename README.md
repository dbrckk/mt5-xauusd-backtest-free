# mt5-xauusd-backtest-free

Deterministic MT5 backtesting for XAUUSD using free public market data and GitHub Actions.

## Current strategy: V27 Clean Multi-Setup

`MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5`

V27 replaces the invalid V26 validation profile.

### Removed

- forced daily trades;
- forced 15:45 fallback entries;
- arbitrary 16:00 position closes;
- runtime PowerShell mutation of the EA source;
- synthetic minute bars inserted into missing history;
- full-notional custom-symbol margin that broke Y3;
- duplicated log counting in the active analyzer.

### Natural entry engine

V27 evaluates four independent M15 setups:

1. `BREAKOUT`
2. `PULLBACK`
3. `CONTINUATION`
4. `SWEEP`

Every candidate is filtered and scored with:

- M15 EMA 9/21/200 structure;
- H1 EMA 50/200 + RSI bias;
- H4 EMA 50/200 + RSI context;
- M15 RSI;
- M15 ADX;
- tick-volume ratio;
- candle body quality;
- spread relative to ATR.

The EA never opens a trade merely because a day has no trade.

Default controls:

- one open position at a time;
- maximum 4 natural entries per day;
- 45-minute cooldown;
- 07:00-20:00 UTC entry window;
- no new Friday entries after 17:00 UTC;
- weekend protection only;
- setup-specific ATR TP/SL;
- break-even after 0.65 ATR;
- trailing stop after 1.0 ATR;
- no-progress time stop after 20 M15 bars.

## Active 3-year validation

Workflow:

`.github/workflows/ea-v26-3y.yml`

The file path is retained for continuity, but the workflow now runs **V27 Clean Multi-Setup**.

Matrix:

| Chunk | Period |
|---|---|
| Y1 | 2023-06-21 to 2024-06-21 |
| Y2 | 2024-06-21 to 2025-06-21 |
| Y3 | 2025-06-21 to 2026-06-21 |

## Public history rules

`scripts/download_public_xau_m1.py`

The active downloader:

- downloads real Dukascopy XAUUSD ticks;
- uses bounded concurrency and retry rounds;
- caches hourly `.bi5` files;
- writes only minutes containing real ticks;
- never fills missing minutes with flat synthetic OHLC;
- hashes the final CSV dataset;
- records real coverage diagnostics;
- fails the run when minimum coverage is not reached.

Default quality gates:

- at least 150,000 real M1 bars;
- at least 220 days with ticks;
- at least 90% successful non-404 requested hours;
- exactly 0 synthetic fill bars.

## Custom symbol margin fix

`MQL5/Experts/ImportCustomRatesEA.mq5`

`XAU_PUBLIC` now uses `SYMBOL_CALC_MODE_CFDLEVERAGE`.

This fixes the V26 Y3 failure where a 0.04-lot position required nearly the full gold notional despite a 1:100 tester account.

## Deterministic runner

`scripts/run-ea-v27-public-backtest.ps1`

The runner compiles and executes the committed V27 source directly.

It does not:

- patch the EA;
- inject a mandatory trade;
- disable one direction;
- change the session;
- change TP/SL during CI.

The committed source and `V27_CLEAN.set` are the source of truth.

## Result analysis

`scripts/analyze-v27-results.py`

The V27 analyzer:

- deduplicates MT5 deals by deal ID;
- pairs closed trades;
- reconstructs profit from unique fills;
- calculates win rate, profit factor, expectancy and drawdown;
- reports BUY and SELL separately;
- reports every setup separately;
- deduplicates execution errors;
- detects `No money` failures;
- verifies market-data quality.

Main outputs:

- `V27_ANALYSIS.json`
- `V27_TRADES.csv`
- `V27_CLEAN_journal.csv`
- `download_diagnostics.json`

## Validation principle

A green GitHub Actions job means the infrastructure completed correctly.

Strategy quality is judged separately from:

- trade count;
- net profit;
- win rate;
- profit factor;
- expectancy;
- drawdown;
- data quality;
- execution errors;
- consistency across Y1, Y2 and Y3.

No strategy is considered validated from one profitable chunk.
