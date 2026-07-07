# Run 96 exact cross-period analysis

Project context: educational, demo-only MT5 research. Experimental targets remain at least 70% validated win rate, at least +5% average monthly progress versus the initial capital, strict intraday operation, and zero overnight trades.

## Tested revision

- Workflow run: `#96 / 28795916853`
- Tested head: `8ec8c6738d21f6cf9152300180d730892de1ef93`
- Strategy: V2.88 core-edge route-hour validation
- Periods: Y0_OOS, Y1, Y2, Y3
- Initial capital reference: $15,000
- Risk: 0.20% per trade

## Infrastructure result

All four jobs completed successfully.

- compilation: PASS, 0 errors and 0 warnings
- source identity: PASS
- source immutability: PASS
- data quality: PASS
- synthetic fill bars: 0 in every period
- execution errors: 0
- overnight trades: 0

Public-history hour success ratios:

| Period | Hour success ratio | Days with ticks |
|---|---:|---:|
| Y0_OOS | 0.930980 | 261 |
| Y1 | 0.930767 | 262 |
| Y2 | 0.930236 | 260 |
| Y3 | 0.929808 | 259 |

All ratios exceeded the required 0.90 threshold.

## Exact aggregate result

| Metric | Result |
|---|---:|
| Closed trades | 77 |
| Wins | 52 |
| Losses | 25 |
| Win rate | 67.5325% |
| Gross profit | $1,418.29 |
| Gross loss | $652.90 |
| Profit factor | 2.1723 |
| Net profit | +$765.39 |
| Final reconstructed equity | $15,765.39 |
| Maximum sequential closed-trade drawdown | $137.09 |
| Maximum sequential closed-trade drawdown | 0.8999% |
| Median hold | 36 minutes |
| Average hold | 58.99 minutes |
| Maximum hold | 300 minutes |
| Overnight trades | 0 |

## Exact result by period

| Period | Trades | Win rate | PF | Net | Max DD | Overnight |
|---|---:|---:|---:|---:|---:|---:|
| Y0_OOS | 19 | 63.16% | 1.9322 | +$170.53 | 0.8999% | 0 |
| Y1 | 14 | 71.43% | 2.7962 | +$184.63 | 0.3849% | 0 |
| Y2 | 21 | 57.14% | 1.1503 | +$35.48 | 0.4655% | 0 |
| Y3 | 23 | 78.26% | 3.8589 | +$374.75 | 0.3430% | 0 |

All four periods were net-positive. The main weakness remains Y2.

## Exact route result

| Route | Trades | Win rate | PF | Net |
|---|---:|---:|---:|---:|
| CORE_PULLBACK_BUY_15 | 55 | 63.64% | 1.8867 | +$449.82 |
| CORE_CONTINUATION_SELL_07_08 | 18 | 72.22% | 2.4166 | +$206.23 |
| CORE_SWEEP_SELL_13_14 | 4 | 100.00% | infinite | +$109.34 |

The pullback route provides most of the sample but remains below the 70% win-rate target. The continuation-sell route is above 70% but has only 18 trades. The sweep route is too small to validate independently.

## Monthly objective result

| Metric | Result |
|---|---:|
| Active months | 40 |
| Positive months | 31 |
| Negative months | 9 |
| Average monthly net | +$19.13 |
| Average monthly return vs initial capital | +0.1276% |
| Median monthly return | +0.1473% |
| Months reaching +5% | 0 |
| Best month | 2023-12, +0.5337% |
| Worst month | 2022-12, -0.5901% |

The +5% monthly target is not close to validation. The correct response is not to increase risk. The strategy first needs more independent, high-quality opportunities.

## Objective verdict

- fresh four-period backtest: PASS
- all period jobs complete: PASS
- all periods net-positive: PASS
- data quality: PASS
- source immutability: PASS
- execution errors: PASS
- strict intraday / zero overnight: PASS
- win rate >= 70%: FAIL at 67.5325%
- average monthly progress >= 5%: FAIL at 0.1276%

The objective is not validated.

## Next experiment

The next experiment preserves the positive core and adds only one independent, strictly gated opportunity module:

`EDGE_SWEEP_SELL_12_15_STRICT`

The extension is allowed only for sweep sells at 12:00 or 15:00 and requires:

- H1 bearish bias
- H4 bearish bias
- RSI between 36 and 46
- ADX >= 28
- volume ratio >= 1.20
- candle body ratio >= 0.60

Risk remains unchanged at 0.20%. No forced trades are added. Intraday controls remain unchanged. The extension must be validated in a fresh Y0_OOS/Y1/Y2/Y3 run before it can be accepted.
