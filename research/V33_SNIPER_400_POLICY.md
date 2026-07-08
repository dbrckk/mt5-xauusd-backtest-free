# V33 Sniper 400 validation policy

Objective for this research branch:

- 1 to 4 trades per week maximum by source-level weekly cap.
- Target win rate above 80% only if validated across all chunks: Y0_OOS, Y1, Y2, Y3.
- Minimum configured target distance: 400 XAU pips using `PipSize=0.01` and `MinTargetPips=400.0`.
- Smaller controlled losses through compressed ATR stop multipliers and risk-normalized position sizing.
- Risk remains capped by `RiskPercent=0.20`.
- Zero overnight policy remains enforced by hard daily flat logic.
- No forced trades.
- No source/data mutation after canonical V33 transform.
- No reintroduction of previously rejected EDGE route-hour cells.

The branch must not be merged unless the CI artifacts show objective improvement against the V2.88 baseline and the objective policy is respected out-of-sample.