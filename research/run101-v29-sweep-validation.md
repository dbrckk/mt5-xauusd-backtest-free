# Run 101 V29 strict sweep-edge validation

Project context: educational, demo-only MT5 research. No real-money deployment. Risk remains unchanged at 0.20% per trade.

## Tested revision

- Workflow run: `#101 / 28845277794`
- Tested merge commit: `148ff757c46c809142c8503a2deeae7e6d42bc3f`
- Branch head before report: `c220b6ebfef90139efc94734dc784292df5ed065`
- Strategy label: V29 strict sweep-edge extension validation
- Added candidate route: `EDGE_SWEEP_SELL_12_15_STRICT`
- Periods: Y0_OOS, Y1, Y2, Y3
- Initial capital reference: $15,000
- Risk: 0.20% per trade

## Infrastructure result

All four jobs completed successfully.

- Y0_OOS: PASS
- Y1: PASS
- Y2: PASS
- Y3: PASS
- compilation: PASS
- V29 identity: PASS
- effective profile: PASS at fixed risk 0.20%
- source immutability: PASS
- analysis step: PASS
- artifact upload: PASS

## Artifact names observed

The run produced one artifact per period:

| Period | Artifact summary |
|---|---|
| Y0_OOS | `INSUFFICIENT_SAMPLE-T19-PF1.93-WR63.2-NET171` |
| Y1 | `INSUFFICIENT_SAMPLE-T14-PF2.80-WR71.4-NET185` |
| Y2 | `INSUFFICIENT_SAMPLE-T21-PF1.15-WR57.1-NET35` |
| Y3 | `INSUFFICIENT_SAMPLE-T23-PF3.86-WR78.3-NET375` |

These summaries are numerically unchanged versus the exact run 96 baseline. The V29 strict sweep-edge route did not add validated net-new closed trades in this fresh four-period run.

## Exact aggregate comparison versus run 96 baseline

| Metric | Run 96 baseline | Run 101 V29 | Delta |
|---|---:|---:|---:|
| Closed trades | 77 | 77 | 0 |
| Wins | 52 | 52 | 0 |
| Losses | 25 | 25 | 0 |
| Win rate | 67.5325% | 67.5325% | 0.0000 pp |
| Profit factor | 2.1723 | 2.1723 | 0.0000 |
| Net profit | +$765.39 | +$765.39 | +$0.00 |
| Max sequential closed-trade DD | 0.8999% | 0.8999% | 0.0000 pp |
| Overnight trades | 0 | 0 | 0 |

## Exact result by period

| Period | Trades | Win rate | PF | Net | Max DD | Overnight | Delta vs run 96 |
|---|---:|---:|---:|---:|---:|---:|---:|
| Y0_OOS | 19 | 63.16% | 1.9322 | +$170.53 | 0.8999% | 0 | unchanged |
| Y1 | 14 | 71.43% | 2.7962 | +$184.63 | 0.3849% | 0 | unchanged |
| Y2 | 21 | 57.14% | 1.1503 | +$35.48 | 0.4655% | 0 | unchanged |
| Y3 | 23 | 78.26% | 3.8589 | +$374.75 | 0.3430% | 0 | unchanged |

All four periods remained net-positive. The structural weakness remains Y2.

## Route-level result

| Route | Trades | Win rate | PF | Net | Verdict |
|---|---:|---:|---:|---:|---|
| CORE_PULLBACK_BUY_15 | 55 | 63.64% | 1.8867 | +$449.82 | retained core route |
| CORE_CONTINUATION_SELL_07_08 | 18 | 72.22% | 2.4166 | +$206.23 | retained core route |
| CORE_SWEEP_SELL_13_14 | 4 | 100.00% | infinite | +$109.34 | retained but tiny sample |
| EDGE_SWEEP_SELL_12_15_STRICT | 0 | n/a | n/a | +$0.00 | rejected: no validated contribution |

## Monthly objective result

Run 101 did not change the monthly profile versus run 96.

| Metric | Run 101 result |
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

The +5% monthly target is still not close to validation. Risk must not be raised to manufacture the target. The only acceptable path remains additional independent, high-quality opportunity modules or better capital efficiency validated by fresh Y0_OOS/Y1/Y2/Y3 runs.

## Objective policy comparison

| Requirement | Result |
|---|---|
| Fresh four-period backtest required | PASS |
| All period jobs complete | PASS |
| All periods net-positive | PASS |
| Data quality must pass | PASS |
| Source immutability must pass | PASS |
| Execution errors must be zero | PASS |
| Strict intraday / zero overnight | PASS |
| Win rate >= 70% | FAIL at 67.5325% |
| Average monthly return >= 5% | FAIL at 0.1276% |
| Do not raise risk to manufacture target | PASS |
| Do not force trades | PASS |
| Prefer independent signal modules | PASS in method, FAIL in observed contribution |

## Verdict

V29 `EDGE_SWEEP_SELL_12_15_STRICT` is rejected as a validated improvement because it produced no net-new validated contribution. The run preserved the V28/V2.88 core result but did not improve trade count, win rate, profit factor, net profit, drawdown, monthly return, or the +5% monthly objective.

The branch should not be merged as a performance improvement. The next experiment should keep the run 96 core intact and test a different independent module with enough expected frequency to improve monthly return without weakening cross-period robustness.

## Next research direction

Recommended next module class:

`EDGE_CONTINUATION_SELL_10_11_STRICT`

Rationale:

- it extends the already profitable continuation-sell family rather than reopening broad weak cells;
- it targets dead time before the current 13-15 sweep window and after the 07-08 continuation window;
- it must remain strictly intraday and risk-normalized;
- it should require H1/H4 bearish alignment, RSI 35-47, ADX >= 28, volume ratio >= 1.15, body ratio >= 0.55, spread within ATR limit, and no relaxation of the validated core.

Acceptance remains fresh Y0_OOS/Y1/Y2/Y3 evidence only.
