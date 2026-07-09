# V35 Sell Structure Policy

## Reason for V35

V34 did not validate the new objective.

Run #124 completed with a cancelled overall conclusion because Y3 cancelled during the committed MT5 backtest path, but Y0_OOS/Y1/Y2 artifacts were sufficient to reject the trading policy:

| Period | Verdict | Trades | WR | PF | Net | Overnight |
|---|---:|---:|---:|---:|---:|---:|
| Y0_OOS | INSUFFICIENT_SAMPLE | 9 | 55.6% | 1.39 | +37 | 0 |
| Y1 | INSUFFICIENT_SAMPLE | 7 | 71.4% | 4.21 | +142 | 0 |
| Y2 | INSUFFICIENT_SAMPLE | 12 | 66.7% | 1.63 | +66 | 0 |
| Y3 | DATA_QUALITY_UNKNOWN | 0 | NA | NA | 0 | 0 |

The objective is not met:

- win rate is below 80% in every completed period;
- sample is insufficient;
- Y3 was not executable to a valid result;
- the unstable long pullback route remains a cross-period weakness.

## Evidence used

Route evidence from V34 completed artifacts:

- `CORE_PULLBACK_BUY_15`
  - Y0_OOS: 5 trades, 1 win, 4 losses, WR 20.0%, PF 0.00, net -93.09.
  - Y1: 7 trades, 5 wins, 2 losses, WR 71.4%, PF 4.21, net +142.45.
  - Y2: 9 trades, 6 wins, 3 losses, WR 66.7%, PF 1.83, net +61.86.
  - Conclusion: unstable, below objective, rejected for V35.

- `CORE_CONTINUATION_SELL_07_08`
  - Y0_OOS: 3 trades, 3 wins, PF infinite, net +84.45.
  - Y2: 3 trades, 2 wins, 1 loss, PF 1.13, net +3.92.
  - Conclusion: retained but tightened.

- `CORE_SWEEP_SELL_13_14`
  - Y0_OOS: 1 trade, 1 win, net +45.15.
  - Conclusion: retained but tightened; insufficient evidence alone.

## V35 changes

V35 is intentionally conservative:

- removes `CORE_PULLBACK_BUY_15` entirely;
- keeps only `CORE_CONTINUATION_SELL_07_08` and `CORE_SWEEP_SELL_13_14`;
- requires both H1 and H4 bearish alignment for all retained sell setups;
- tightens signal score, ADX, spread, body, and volume gates;
- keeps `MaxTradesPerWeek=4` and `MaxTradesPerDay=1`;
- keeps `MinTargetPips=400.0`;
- keeps `RiskPercent=0.20`;
- keeps zero overnight behavior;
- does not force trades;
- keeps source immutability checks.

## Execution reliability changes

The V35 workflow reduces Y3 instability risk:

- `max-parallel: 1` to reduce runner resource contention;
- MT5 timeout raised to 430 minutes;
- job timeout raised to 500 minutes;
- public fetch timeout/retry budget increased;
- fetch workers reduced from 8 to 4 for lower transient failure pressure.

## Merge policy

Do not merge V35 unless fresh artifacts prove across Y0_OOS/Y1/Y2/Y3:

- compilation PASS;
- data quality PASS;
- source identity PASS;
- source immutability PASS;
- zero overnight;
- no forced trades;
- no source/data mutation;
- no risk increase above 0.20%;
- no weak route reintroduction;
- objective evidence valid out-of-sample;
- target win rate above 80% honestly validated, not produced by one lucky period;
- 1 to 4 trades/week objective evaluated with zero-trade calendar weeks/months counted honestly;
- positive PF/net and controlled drawdown per period.
