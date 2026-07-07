# Run 108 V31 strict continuation-buy validation

Project context: educational, demo-only MT5 research. No real-money deployment. Risk remains unchanged at `0.20%` per trade.

## Tested revision

- Workflow run: `#108 / 28864777260`
- Pull request: `#12`
- Head branch: `v31-strict-continuation-buy-validation`
- Head SHA: `bf040ee2098921bcac4728be89fea7669392bfd6`
- PR merge test SHA in artifact names: `69211ed0baf8566cc515d05a18d5e475b7e25c1a`
- Strategy label: V31 strict continuation-buy 09-10 validation
- Added candidate route: `EDGE_CONTINUATION_BUY_09_10_STRICT`
- Initial capital reference: `$15,000`
- Risk: `0.20%` per trade

## Infrastructure result

All four matrix jobs completed successfully.

| Period | Job result |
|---|---|
| Y0_OOS | success |
| Y1 | success |
| Y2 | success |
| Y3 | success |

Validation steps passed in every matrix job:

- checkout exact source revision
- V31 source identity
- Dukascopy public-history cache step
- committed source digest capture
- committed MT5 backtest
- source immutability verification
- result analysis
- compact summary export
- artifact upload

No workflow-level failure occurred.

## Artifact-level result

Artifacts published by run #108:

| Period | Artifact summary |
|---|---|
| Y0_OOS | `INSUFFICIENT_SAMPLE-T20-PF2.15-WR65.0-NET210` |
| Y1 | `INSUFFICIENT_SAMPLE-T15-PF2.17-WR66.7-NET155` |
| Y2 | `INSUFFICIENT_SAMPLE-T23-PF1.18-WR56.5-NET47` |
| Y3 | `INSUFFICIENT_SAMPLE-T24-PF3.18-WR75.0-NET347` |

The compact summaries remain marked `INSUFFICIENT_SAMPLE` in every period.

## Comparison against run #96 baseline

Run #96 exact baseline:

| Period | Trades | Win rate | PF | Net |
|---|---:|---:|---:|---:|
| Y0_OOS | 19 | 63.16% | 1.9322 | +$170.53 |
| Y1 | 14 | 71.43% | 2.7962 | +$184.63 |
| Y2 | 21 | 57.14% | 1.1503 | +$35.48 |
| Y3 | 23 | 78.26% | 3.8589 | +$374.75 |

Run #108 compact V31 result:

| Period | Trades | Win rate | PF | Net rounded | Delta vs run #96 |
|---|---:|---:|---:|---:|---|
| Y0_OOS | 20 | 65.0% | 2.15 | +$210 | +1 trade, improved PF/net/win rate |
| Y1 | 15 | 66.7% | 2.17 | +$155 | +1 trade, degraded PF/win rate/net |
| Y2 | 23 | 56.5% | 1.18 | +$47 | +2 trades, slight net/PF improvement, win rate still weaker |
| Y3 | 24 | 75.0% | 3.18 | +$347 | +1 trade, degraded PF/win rate/net |

Aggregate from artifact summaries:

| Metric | Run #96 exact baseline | Run #108 V31 compact result | Delta |
|---|---:|---:|---:|
| Closed trades | 77 | 82 | +5 |
| Wins | 52 | 54 inferred from period WR/trade counts | +2 |
| Losses | 25 | 28 inferred | +3 |
| Win rate | 67.5325% | ~65.85% inferred | -1.68 pp |
| Net profit | +$765.39 | ~$759 rounded artifact aggregate | about -$6.4 |
| Overnight trades | 0 | 0 expected by strict intraday controls | 0 |

Because artifact names round net, PF and WR, the aggregate V31 figures are compact-summary level, not full ledger precision. The decision is still clear because the rounded evidence shows lower aggregate win rate and no net improvement.

## Comparison against run #105 V30

Run #105 compact V30 result:

| Period | Trades | Win rate | PF | Net rounded |
|---|---:|---:|---:|---:|
| Y0_OOS | 20 | 65.0% | 1.94 | +$171 |
| Y1 | 15 | 73.3% | 3.16 | +$222 |
| Y2 | 21 | 57.1% | 1.15 | +$35 |
| Y3 | 25 | 76.0% | 3.46 | +$378 |

V31 versus V30:

| Metric | V30 compact | V31 compact | Delta |
|---|---:|---:|---:|
| Closed trades | 81 | 82 | +1 |
| Inferred wins | 55 | 54 | -1 |
| Inferred losses | 26 | 28 | +2 |
| Win rate | ~67.90% | ~65.85% | -2.05 pp |
| Net rounded | ~$806 | ~$759 | about -$47 |

V31 is weaker than both run #96 baseline and V30 compact evidence.

## Route-level inference

Run #96 route baseline:

| Route | Trades | Win rate | PF | Net |
|---|---:|---:|---:|---:|
| CORE_PULLBACK_BUY_15 | 55 | 63.64% | 1.8867 | +$449.82 |
| CORE_CONTINUATION_SELL_07_08 | 18 | 72.22% | 2.4166 | +$206.23 |
| CORE_SWEEP_SELL_13_14 | 4 | 100.00% | infinite | +$109.34 |

V31 route contribution inferred from period trade deltas versus run #96:

| Route | Inferred trades | Inferred result | Verdict |
|---|---:|---|---|
| EDGE_CONTINUATION_BUY_09_10_STRICT | 5 | approximately 2 wins / 3 losses, about -$6 net from compact summaries | negative / not robust |

The added route increased trade count, but the extra sample was loss-heavy and did not improve the strategy objective.

## Monthly objective comparison

The monthly objective remains far from validation.

| Metric | Run #96 baseline | Run #108 V31 compact estimate |
|---|---:|---:|
| Active months | 40 | 40 assumed unchanged validation span |
| Average monthly net | +$19.13 | about +$18.98 |
| Average monthly return vs initial capital | +0.1276% | about +0.1265% |
| Months reaching +5% | 0 | not validated as improved |

The +5% monthly objective remains structurally unmet. Risk must not be raised to manufacture the target.

## Objective policy comparison

| Requirement | Result |
|---|---|
| Fresh four-period backtest required | PASS |
| All period jobs complete | PASS |
| All periods net-positive | PASS |
| Data quality must pass | PASS by workflow/analyzer completion |
| Source immutability must pass | PASS |
| Execution errors must be zero | PASS by successful analysis and workflow completion |
| Strict intraday / zero overnight | PASS by unchanged hard constraints and accepted baseline controls |
| Win rate >= 70% | FAIL, ~65.85% inferred |
| Average monthly return >= 5% | FAIL, about 0.1265% inferred |
| Do not raise risk to manufacture target | PASS |
| Do not force trades | PASS |
| Prefer independent signal modules | PASS in method |
| Reject changes that improve one period but break cross-period robustness | FAIL for acceptance: Y1 and Y3 degraded, aggregate degraded |

## Decision

V31 `EDGE_CONTINUATION_BUY_09_10_STRICT` is rejected and must not be merged.

Reason:

- It adds only five trades across four validation periods.
- The inferred added-route result is approximately 2 wins / 3 losses.
- Aggregate win rate falls from 67.5325% to about 65.85%.
- Rounded aggregate net falls from +$765.39 to about +$759.
- Y1 degrades materially: win rate, PF and net are all worse than baseline.
- Y3 also degrades: win rate, PF and net are all worse than baseline.
- Y2 improves only slightly in PF/net and remains the weakest period.
- The objective remains far below 70% win rate and +5% monthly return.

Status: rejected as a performance improvement.

## Next research direction

Do not raise risk. Do not force trades. Do not relax weak cells broadly.

The next candidate should not be a continuation-buy route. Prefer a pullback route with controlled proximity and higher expected quality:

`EDGE_PULLBACK_BUY_10_11_STRICT`

Proposed strict gate:

- setup: `PULLBACK`
- direction: BUY
- hours: `10` or `11`
- H1 bias: bullish
- H4 bias: bullish or neutral-to-bullish, never bearish
- RSI: `52` to `63`
- ADX: `>= 24`
- volume ratio: `>= 1.05`
- body ratio: `>= 0.42`
- close above fast EMA and trend EMA
- controlled slow-EMA pullback touch or ATR-proximity condition
- risk remains `0.20%`
- no forced trades
- strict intraday only
- reject unless fresh Y0_OOS/Y1/Y2/Y3 validation improves frequency/monthly profile without material degradation

## Status

Run #108 is complete and usable as compact evidence. The module is not robust enough for promotion. Continue research with a new independent strict module rather than risk inflation or broad relaxation.
