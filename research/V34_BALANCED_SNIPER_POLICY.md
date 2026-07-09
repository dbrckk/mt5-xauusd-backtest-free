# V34 Balanced Sniper Policy

## V33 rejection

Run #121 completed with failure. V33 was merged before evidence existed, then failed validation:

| Period | Verdict | Trades | WR | PF | Net | Notes |
|---|---:|---:|---:|---:|---:|---|
| Y0_OOS | INSUFFICIENT_SAMPLE | 1 | 100.0% | NA | +64 | Too few trades to validate |
| Y1 | INSUFFICIENT_SAMPLE | 1 | 0.0% | 0.00 | -15 | Too few trades, loss |
| Y2 | INSUFFICIENT_SAMPLE | 2 | 0.0% | 0.00 | -48 | Too few trades, losses |
| Y3 | DATA_QUALITY_FAIL | 0 | NA | NA | 0 | Hour success ratio 0.7973 < 0.9000 |

V33 therefore does not validate the new objective. It over-pruned signal eligibility and the Y3 data fetch quality was not acceptable.

## V34 objective

V34 keeps the new research objective but changes the validation path:

- Risk remains `0.20%`.
- `MaxTradesPerWeek=4` and `MaxTradesPerDay=1` remain enforced.
- `MinTargetPips=400.0` remains enforced.
- EDGE routes remain pruned.
- No forced trades.
- Zero overnight remains required.
- H1 must align with direction.
- H4 must not oppose direction; neutral H4 is allowed to avoid the V33 sample collapse.
- Filters are stricter than V32 but less extreme than V33.
- Dukascopy fetch reliability is improved for Y3 by using longer timeout, more retries, more retry rounds, and lower worker concurrency.

## Merge gate

Do not merge unless fresh artifacts prove across Y0_OOS/Y1/Y2/Y3:

- data quality PASS;
- source immutability PASS;
- compile/backtest execution PASS;
- zero overnight;
- no source/data mutation;
- no EDGE route reintroduction;
- no risk increase above 0.20%;
- weekly trade frequency inside the 1-4 objective when zero-trade calendar weeks are handled honestly;
- WR above 80% in each period with enough sample to matter;
- positive net/PF and controlled drawdown;
- route evidence does not depend on one lucky period.

If V34 fails, the next branch should not loosen risk or reintroduce weak route-hour cells. It should either prune losing core routes, add a stronger structure regime filter, or reject the 400-pip objective as incompatible with the available validated intraday evidence.
