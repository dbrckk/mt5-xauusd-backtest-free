# V34 Rejection Evidence

V34 is rejected for the current objective.

## Run

- Run number: 124
- Run ID: 28979172430
- Workflow conclusion: cancelled
- Reason: Y3 cancelled during committed MT5 backtest path, while analysis/export/upload still completed with `DATA_QUALITY_UNKNOWN`.

## Completed period metrics

| Period | Verdict | Trades | Wins | Losses | WR | PF | Net | Max DD | Overnight |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Y0_OOS | INSUFFICIENT_SAMPLE | 9 | 5 | 4 | 55.6% | 1.39 | +36.51 | 87.84 | 0 |
| Y1 | INSUFFICIENT_SAMPLE | 7 | 5 | 2 | 71.4% | 4.21 | +142.45 | 29.55 | 0 |
| Y2 | INSUFFICIENT_SAMPLE | 12 | 8 | 4 | 66.7% | 1.63 | +65.78 | 58.86 | 0 |
| Y3 | DATA_QUALITY_UNKNOWN | 0 | 0 | 0 | NA | NA | 0 | NA | 0 |

## Route evidence

### CORE_PULLBACK_BUY_15

Rejected.

- Y0_OOS: 5 trades, 1 win, 4 losses, WR 20.0%, net -93.09.
- Y1: 7 trades, 5 wins, 2 losses, WR 71.4%, net +142.45.
- Y2: 9 trades, 6 wins, 3 losses, WR 66.7%, net +61.86.

This route is not robust enough for the new objective and is below 80% in every usable multi-trade period.

### CORE_CONTINUATION_SELL_07_08

Retained with stricter filters.

- Y0_OOS: 3 trades, 3 wins, net +84.45.
- Y2: 3 trades, 2 wins, 1 loss, net +3.92.

### CORE_SWEEP_SELL_13_14

Retained with stricter filters.

- Y0_OOS: 1 trade, 1 win, net +45.15.

## V35 response

V35 moves to sell-only structure validation:

- no `CORE_PULLBACK_BUY_15`;
- no EDGE routes;
- only `CORE_CONTINUATION_SELL_07_08` and `CORE_SWEEP_SELL_13_14`;
- H1 and H4 both bearish required;
- tighter ADX, spread, volume, body, score gates;
- 400-pip target floor preserved;
- risk remains 0.20%;
- zero overnight preserved;
- no forced trades.
