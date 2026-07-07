# Run 105 V30 strict continuation-sell validation

Project context: educational, demo-only MT5 research. No real-money deployment. Risk remains unchanged at `0.20%` per trade.

## Tested revision

- Workflow run: `#105 / 28852304356`
- Pull request: `#11`
- Head branch: `v30-strict-continuation-sell-validation`
- Head SHA: `f8475ee7cff73d49a9e962c115f6254fd1b73da4`
- PR merge test SHA: `8fdd18b4a0ceb9e5f06b7d7e130b598bb4b0478b`
- Strategy label: V30 strict continuation-sell 10-11 validation
- Added candidate route: `EDGE_CONTINUATION_SELL_10_11_STRICT`
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
- V30 source identity
- Dukascopy public-history cache step
- committed source digest capture
- committed MT5 backtest
- source immutability verification
- result analysis
- compact summary export
- artifact upload

No workflow-level failure occurred.

## Artifact-level result

Artifacts published by run #105:

| Period | Artifact summary |
|---|---|
| Y0_OOS | `INSUFFICIENT_SAMPLE-T20-PF1.94-WR65.0-NET171` |
| Y1 | `INSUFFICIENT_SAMPLE-T15-PF3.16-WR73.3-NET222` |
| Y2 | `INSUFFICIENT_SAMPLE-T21-PF1.15-WR57.1-NET35` |
| Y3 | `INSUFFICIENT_SAMPLE-T25-PF3.46-WR76.0-NET378` |

The compact summaries show a small positive contribution versus run #96 baseline, but the result remains marked `INSUFFICIENT_SAMPLE` in every period.

## Comparison against run #96 baseline

Run #96 exact baseline:

| Period | Trades | Win rate | PF | Net |
|---|---:|---:|---:|---:|
| Y0_OOS | 19 | 63.16% | 1.9322 | +$170.53 |
| Y1 | 14 | 71.43% | 2.7962 | +$184.63 |
| Y2 | 21 | 57.14% | 1.1503 | +$35.48 |
| Y3 | 23 | 78.26% | 3.8589 | +$374.75 |

Run #105 compact V30 result:

| Period | Trades | Win rate | PF | Net rounded | Delta vs run #96 |
|---|---:|---:|---:|---:|---|
| Y0_OOS | 20 | 65.0% | 1.94 | +$171 | +1 trade, effectively flat net |
| Y1 | 15 | 73.3% | 3.16 | +$222 | +1 trade, improved PF/net |
| Y2 | 21 | 57.1% | 1.15 | +$35 | unchanged; still weakest period |
| Y3 | 25 | 76.0% | 3.46 | +$378 | +2 trades, roughly flat net, lower PF/WR |

Aggregate from artifact summaries:

| Metric | Run #96 exact baseline | Run #105 V30 compact result | Delta |
|---|---:|---:|---:|
| Closed trades | 77 | 81 | +4 |
| Wins | 52 | 55 inferred from period WR/trade counts | +3 |
| Losses | 25 | 26 inferred | +1 |
| Win rate | 67.5325% | ~67.90% inferred | +0.37 pp |
| Net profit | +$765.39 | ~$806 rounded artifact aggregate | about +$40.6 |
| Overnight trades | 0 | 0 expected by strict intraday controls | 0 |

Because artifact names round net, PF and WR, these aggregate V30 figures are compact-summary level, not full ledger precision. Full acceptance still requires keeping the downloaded artifact ledgers as the source of exact route-level proof.

## Route-level inference

Run #96 route baseline:

| Route | Trades | Win rate | PF | Net |
|---|---:|---:|---:|---:|
| CORE_PULLBACK_BUY_15 | 55 | 63.64% | 1.8867 | +$449.82 |
| CORE_CONTINUATION_SELL_07_08 | 18 | 72.22% | 2.4166 | +$206.23 |
| CORE_SWEEP_SELL_13_14 | 4 | 100.00% | infinite | +$109.34 |

V30 route contribution inferred from period trade deltas:

| Route | Inferred trades | Inferred result | Verdict |
|---|---:|---|---|
| EDGE_CONTINUATION_SELL_10_11_STRICT | 4 | approximately 3 wins / 1 loss, about +$40 net from compact summaries | positive but too small to validate independently |

## Monthly objective comparison

The monthly objective remains far from validation.

| Metric | Run #96 baseline | Run #105 V30 compact estimate |
|---|---:|---:|
| Active months | 40 | 40 assumed unchanged validation span |
| Average monthly net | +$19.13 | about +$20.15 |
| Average monthly return vs initial capital | +0.1276% | about +0.1343% |
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
| Win rate >= 70% | FAIL, ~67.90% inferred |
| Average monthly return >= 5% | FAIL, about 0.1343% inferred |
| Do not raise risk to manufacture target | PASS |
| Do not force trades | PASS |
| Prefer independent signal modules | PASS in method |
| Reject changes that improve one period but break cross-period robustness | No hard break observed, but sample remains insufficient |

## Decision

V30 `EDGE_CONTINUATION_SELL_10_11_STRICT` is not accepted as a validated improvement yet.

Reason:

- It appears to add four trades across the full four-period validation.
- It appears mildly positive in compact summaries.
- It does not degrade Y0_OOS or Y1.
- It does not fix Y2, which remains unchanged and structurally weak.
- It slightly lowers Y3 PF/win rate despite a small net increase.
- It still fails the validated 70% win-rate target.
- It still fails the +5% average monthly return target by a very large margin.
- The new route sample is too small for independent acceptance.

Status: positive/no-reject-by-damage, but rejected as a validated performance improvement.

## Next research direction

Do not raise risk. Do not loosen the existing weak cells. The next module should target independent opportunity density with strict filters, especially where Y2 can improve.

Recommended next candidate for V31:

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
- pullback touch of slow EMA or controlled ATR proximity
- risk remains `0.20%`
- no forced trades
- strict intraday only
- reject unless fresh Y0_OOS/Y1/Y2/Y3 validation improves frequency/monthly profile without material degradation

## Status

Run #105 is complete and usable as compact evidence. The module is not robust enough for promotion. Continue research with a new independent strict module rather than risk inflation or broad relaxation.
