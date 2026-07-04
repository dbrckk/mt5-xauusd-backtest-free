# V27 execution correction

This validation increment fixes two backtest defects discovered from the first clean 3-year artifacts:

- `XAU_PUBLIC` now explicitly uses a `0.001` trade tick size, matching the imported price precision and preventing valid signals from being rejected as `Invalid price`.
- public OHLC is built from bid prices with average per-minute spread, matching `SYMBOL_CHART_MODE_BID` and improving execution realism.

No forced trades are introduced.
