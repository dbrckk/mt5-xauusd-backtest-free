# Run 86 research analysis

Project context: educational, demo-only MT5 research. Experimental targets are at least 70% validated win rate, at least +5% monthly progress versus the initial capital, and strict intraday operation with zero overnight trades.

## Tested revision

- EA commit: `2c630c148146539e3965c2b5edf2c9c0af6adc56`
- Workflow run: `28775505695` / run #86
- Periods: Y0_OOS, Y1, Y2, Y3
- Initial capital per period: $15,000

## Aggregate result

| Metric | Result |
|---|---:|
| Closed trades | 309 |
| Win rate | 55.99% |
| Profit factor | 1.089 |
| Net profit | +$325.19 |
| Expectancy | +$1.05/trade |
| Overnight trades | 0 |
| Maximum observed hold | 300 minutes |
| Hard-daily-flat closes | 3 |
| Active months | 47 |
| Positive months | 24 |
| Negative months | 23 |
| Months reaching +5% | 0 |
| Best month | +1.1677% of initial capital |
| Worst month | -1.4620% of initial capital |
| Average active-month return | +0.0461% of initial capital |

Compilation, source immutability, data-quality gates and artifact upload completed successfully on all four periods. No execution-error category was detected in the exported analyses. Data quality passed with no synthetic fill bars.

## Results by period

| Period | Trades | Win rate | PF | Net |
|---|---:|---:|---:|---:|
| Y0_OOS | 58 | 63.79% | 1.608 | +$359.56 |
| Y1 | 56 | 50.00% | 0.875 | -$97.67 |
| Y2 | 101 | 50.50% | 0.696 | -$403.86 |
| Y3 | 94 | 60.64% | 1.481 | +$467.16 |

The current strategy does not meet either primary target. Its main robustness failure is Y2, while Y1 is also negative.

## Route-level result

| Route | Trades | Win rate | PF | Net |
|---|---:|---:|---:|---:|
| BREAKOUT_BUY_07_08 | 48 | 54.17% | 0.943 | -$35.28 |
| CONTINUATION_SELL_07_08 | 18 | 72.22% | 2.436 | +$209.02 |
| PULLBACK_BUY_13_16 | 239 | 54.39% | 1.016 | +$47.81 |
| SWEEP_SELL_13_16 | 4 | 100.00% | infinite | +$103.64 |

The sweep route is too small to validate independently. The continuation-sell route is the strongest validated route by win rate and PF, but its sample is still small.

## Entry-hour result

| Hour | Trades | Win rate | PF | Net |
|---|---:|---:|---:|---:|
| 07 | 27 | 66.67% | 1.749 | +$191.23 |
| 08 | 39 | 53.85% | 0.966 | -$17.49 |
| 13 | 87 | 54.02% | 0.828 | -$188.27 |
| 14 | 88 | 56.82% | 1.087 | +$90.11 |
| 15 | 49 | 65.31% | 2.203 | +$513.29 |
| 16 | 19 | 26.32% | 0.254 | -$263.68 |

The 16:00 cell is the clearest systematic defect: it is negative in all four periods. The 13:00 pullback cell and 08:00 breakout cell are also weak.

## Strongest route-hour cells

### Pullback buy at 15:00

- 49 trades
- 65.31% win rate
- PF 2.203
- +$513.29
- Positive in all four periods

Period detail:

| Period | Trades | Win rate | PF | Net |
|---|---:|---:|---:|---:|
| Y0_OOS | 10 | 60.0% | 1.65 | +$60.40 |
| Y1 | 10 | 70.0% | 3.55 | +$185.28 |
| Y2 | 16 | 56.25% | 1.09 | +$16.11 |
| Y3 | 13 | 76.92% | 4.37 | +$251.50 |

### Continuation sell at 07:00-08:59

- 18 trades
- 72.22% win rate
- PF 2.436
- +$209.02

### Sweep sell at 13:00-14:59

- 4 trades
- 100% win rate
- +$103.64
- Sample is insufficient for independent validation.

## Candidate core portfolio hypothesis

A post-filter of already executed trades was tested as a research hypothesis only. It is not a substitute for a fresh strategy backtest.

Candidate cells:

1. `CONTINUATION_SELL_07_08` at 07:00-08:59
2. `PULLBACK_BUY_13_16` only at 15:00-15:59
3. `SWEEP_SELL_13_16` at 13:00-14:59

Estimated historical result from the run #86 trade export:

- 71 trades
- 69.01% win rate
- PF 2.44
- +$825.95 net
- Positive in all four periods

| Period | Trades | Win rate | PF | Net |
|---|---:|---:|---:|---:|
| Y0_OOS | 17 | 70.59% | 2.87 | +$229.91 |
| Y1 | 13 | 69.23% | 2.69 | +$173.89 |
| Y2 | 20 | 60.00% | 1.26 | +$56.40 |
| Y3 | 21 | 76.19% | 3.79 | +$365.75 |

This candidate is much closer to the win-rate target and materially improves PF, but frequency is far too low for the +5% monthly target. The correct next step is to validate the core in a fresh backtest, not to increase risk. If the core validates, additional independent signal modules should be researched to increase opportunity count without reintroducing the weak route-hour cells.

## Comparison with run 84

| Metric | Run 84 | Run 86 |
|---|---:|---:|
| Trades | 284 | 309 |
| Win rate | 56.69% | 55.99% |
| PF | 1.126 | 1.089 |
| Net | +$421.52 | +$325.19 |

Run 86 increased activity but degraded aggregate quality. The balanced rollback did not solve the strategy.

## Next research sequence

1. Validate the candidate core as an actual fresh backtest while preserving strict daily flat and unchanged risk.
2. Require zero overnight trades and positive results across Y0_OOS, Y1, Y2 and Y3.
3. Do not increase risk to manufacture the monthly target.
4. If the core validates, add independent higher-frequency modules and retest each contribution separately.
5. Fix source-versus-runner profile drift before interpreting further changes to EA input defaults.

This document records empirical research findings only. It does not claim that the experimental objectives are achieved.
