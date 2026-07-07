# Run 101 V29 strict sweep-edge validation

Project context: educational, demo-only MT5 research. This report records the fresh PR validation of the V29 strict sweep-edge extension after all four GitHub Actions matrix jobs completed successfully.

## Tested revision

- Workflow run: `#101 / 28845277794`
- Pull request: `#10`
- Head branch: `v29-strict-sweep-validation`
- Head SHA: `c220b6ebfef90139efc94734dc784292df5ed065`
- PR merge test SHA reported by artifacts: `148ff757c46c809142c8503a2deeae7e6d42bc3f`
- Strategy label: V29 strict sweep-edge validation
- Initial capital reference: `$15,000`
- Risk: `0.20%` per trade

## Infrastructure result

All four matrix jobs completed successfully:

| Period | Job result |
|---|---|
| Y0_OOS | success |
| Y1 | success |
| Y2 | success |
| Y3 | success |

Validation steps completed successfully in each matrix job:

- checkout exact source revision
- V29 source identity
- Dukascopy public-history cache step
- source digest capture
- committed MT5 backtest
- source immutability verification
- result analysis
- compact summary export
- artifact upload

No workflow-level failure occurred.

## Artifact-level result

Artifacts published by run #101:

| Period | Artifact summary |
|---|---|
| Y0_OOS | `INSUFFICIENT_SAMPLE-T19-PF1.93-WR63.2-NET171` |
| Y1 | `INSUFFICIENT_SAMPLE-T14-PF2.80-WR71.4-NET185` |
| Y2 | `INSUFFICIENT_SAMPLE-T21-PF1.15-WR57.1-NET35` |
| Y3 | `INSUFFICIENT_SAMPLE-T23-PF3.86-WR78.3-NET375` |

These summaries are numerically identical to the accepted V2.88/run #96 baseline period metrics:

| Period | Run #96 baseline | Run #101 V29 | Change |
|---|---:|---:|---:|
| Y0_OOS trades | 19 | 19 | 0 |
| Y0_OOS WR | 63.16% | 63.2% | unchanged after rounding |
| Y0_OOS PF | 1.93 | 1.93 | 0 |
| Y0_OOS net | +$170.53 | +$171 rounded | unchanged after rounding |
| Y1 trades | 14 | 14 | 0 |
| Y1 WR | 71.43% | 71.4% | unchanged after rounding |
| Y1 PF | 2.80 | 2.80 | 0 |
| Y1 net | +$184.63 | +$185 rounded | unchanged after rounding |
| Y2 trades | 21 | 21 | 0 |
| Y2 WR | 57.14% | 57.1% | unchanged after rounding |
| Y2 PF | 1.15 | 1.15 | 0 |
| Y2 net | +$35.48 | +$35 rounded | unchanged after rounding |
| Y3 trades | 23 | 23 | 0 |
| Y3 WR | 78.26% | 78.3% | unchanged after rounding |
| Y3 PF | 3.86 | 3.86 | 0 |
| Y3 net | +$374.75 | +$375 rounded | unchanged after rounding |

## Aggregate comparison against run #96 baseline

Because every period-level artifact summary is unchanged versus the exact run #96 baseline, the aggregate V29 result is treated as unchanged unless deeper artifact parsing later proves otherwise.

| Metric | Run #96 exact baseline | Run #101 V29 conclusion |
|---|---:|---:|
| Closed trades | 77 | unchanged |
| Wins | 52 | unchanged |
| Losses | 25 | unchanged |
| Win rate | 67.5325% | unchanged |
| Gross profit | $1,418.29 | unchanged |
| Gross loss | $652.90 | unchanged |
| Profit factor | 2.1723 | unchanged |
| Net profit | +$765.39 | unchanged |
| Final reconstructed equity | $15,765.39 | unchanged |
| Maximum sequential closed-trade DD | 0.8999% | unchanged |
| Overnight trades | 0 | unchanged |

## Monthly objective comparison

Run #96 baseline monthly metrics remain the governing comparison because V29 did not create any visible additional accepted trade in the run #101 period summaries.

| Monthly metric | Baseline / inferred V29 result |
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

The monthly-profit objective remains far from validation. The V29 module did not move the average monthly return, trade frequency, or number of months reaching the +5% experimental target.

## Decision

V29 strict sweep-edge extension is not accepted as an improvement.

Reason:

- It preserved the robust core.
- It did not degrade visible period-level metrics.
- But it also did not add visible trade frequency or monthly profit.
- Therefore it does not solve the current primary bottleneck: monthly return percentage versus the initial capital.

This extension should be treated as neutral/no-effect and not promoted as a successful module.

## Next research direction

The next experiment should focus on monthly opportunity count while preserving the V2.88 quality gates.

Recommended next module family:

`EDGE_CONTINUATION_BUY_09_10_STRICT`

Rationale:

- Current accepted core is heavily dependent on `CORE_PULLBACK_BUY_15` and sell-side continuation/sweep routes.
- Monthly return is constrained by low trade count: 77 trades across 40 active months.
- A strict morning continuation-buy module may add independent opportunity density without loosening risk or overnight policy.
- It should require H1/H4 bullish agreement, RSI in a controlled momentum band, ADX strength, volume confirmation, clean body ratio, and no late-session exposure.

Proposed strict gate for a fresh V30 validation:

- setup: `CONTINUATION`
- direction: BUY
- hours: `09` or `10`
- H1 bias: bullish
- H4 bias: bullish or neutral-to-bullish, never bearish
- RSI: `53` to `64`
- ADX: `>= 26`
- volume ratio: `>= 1.10`
- body ratio: `>= 0.50`
- no change to risk: `RiskPercent=0.20`
- no forced trades
- strict intraday only
- reject unless fresh Y0_OOS/Y1/Y2/Y3 validation improves monthly return or trade frequency without material quality degradation

## Status

Run #101 is complete and usable as evidence. The result is a no-effect validation for the V29 sweep-edge extension. Continue research with a new independent opportunity module aimed at monthly return improvement, not with risk inflation.
