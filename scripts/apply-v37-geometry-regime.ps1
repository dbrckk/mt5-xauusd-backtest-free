$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$eaPath = "MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5"
if (!(Test-Path $eaPath)) { throw "EA source missing: $eaPath" }

# Rebuild deterministically from the committed V35 sell-only profile.
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/apply-v35-sell-structure.ps1
$ea = Get-Content $eaPath -Raw

# Identity.
$ea = $ea.Replace('#property version "2.94"', '#property version "3.08"')
$ea = $ea.Replace('V35 Sell Structure Quality Gate: weak pullback route pruned', 'V50 Hour-8 Pullback Rejection and Break-Retest State Machine')
$ea = $ea.Replace('input string CSVJournalName="V35_SELL_STRUCTURE_journal.csv";', 'input string CSVJournalName="V50_H8_PULLBACK_BREAK_RETEST_journal.csv";')

# Use only hour 08. Rejected hours 07/10/11/12/13/14 remain absent, and rejected V49 hour-09 states are removed.
$routeOld = @'
   if(setup=="CONTINUATION" && dir<0 && hour>=7 && hour<9)
   {
      name="CORE_CONTINUATION_SELL_07_08";
      return true;
   }
   if(setup=="SWEEP" && dir<0 && hour>=13 && hour<15)
   {
      name="CORE_SWEEP_SELL_13_14";
      return true;
   }
'@
$routeNew = @'
   if(setup=="PULLBACK_REJECTION" && dir<0 && hour==8)
   {
      name="STATE_PULLBACK_REJECTION_SELL_08";
      return true;
   }
   if(setup=="BREAK_RETEST" && dir<0 && hour==8)
   {
      name="STATE_BREAK_RETEST_SELL_08";
      return true;
   }
'@
if (!$ea.Contains($routeOld)) { throw "V50 cannot find V35 sell route block." }
$ea = $ea.Replace($routeOld, $routeNew)

$routeQualityV35 = @'
bool RouteQuality(string setup,int dir,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if(dir>=0)
      return false;
   if(h1Bias>=0 || h4Bias>=0)
      return false;
   if(adx<MinADX || volumeRatio<MinVolumeRatio || bodyRatio<MinBodyRatio)
      return false;

   if(setup=="CONTINUATION" && dir<0)
      return rsi>=36 && rsi<=45 && adx>=28 && volumeRatio>=1.18 && bodyRatio>=0.48;
   if(setup=="SWEEP" && dir<0)
      return rsi>=36 && rsi<=48 && adx>=28 && volumeRatio>=1.20 && bodyRatio>=0.50;

   return false;
}
'@
$routeQualityV50 = @'
bool RouteQuality(string setup,int dir,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if(dir>=0 || (setup!="PULLBACK_REJECTION" && setup!="BREAK_RETEST"))
      return false;
   if(h1Bias>=0 || h4Bias>0)
      return false;
   if(adx<MinADX || volumeRatio<MinVolumeRatio || bodyRatio<MinBodyRatio)
      return false;

   if(setup=="PULLBACK_REJECTION")
      return rsi>=34 && rsi<=58 && adx>=15 && volumeRatio>=0.70 && bodyRatio>=0.16;
   if(setup=="BREAK_RETEST")
      return rsi>=30 && rsi<=54 && adx>=16 && volumeRatio>=0.72 && bodyRatio>=0.18;

   return false;
}
'@
if (!$ea.Contains($routeQualityV35)) { throw "V50 cannot find V35 RouteQuality block." }
$ea = $ea.Replace($routeQualityV35, $routeQualityV50)

# Preserve asymmetric structural exits, with deterministic risk and strict intraday controls unchanged.
$ea = $ea.Replace('input double MinSignalScore=91.0;', 'input double MinSignalScore=68.0;')
$ea = $ea.Replace('input double MinADX=28.0;', 'input double MinADX=15.0;')
$ea = $ea.Replace('input double MaxSpreadATRFraction=0.045;', 'input double MaxSpreadATRFraction=0.075;')
$ea = $ea.Replace('input double MinBodyRatio=0.48;', 'input double MinBodyRatio=0.12;')
$ea = $ea.Replace('input double MinVolumeRatio=1.18;', 'input double MinVolumeRatio=0.65;')
$ea = $ea.Replace('input double ContinuationTP_ATR=3.75;', 'input double ContinuationTP_ATR=4.20;')
$ea = $ea.Replace('input double ContinuationSL_ATR=0.74;', 'input double ContinuationSL_ATR=0.66;')
$ea = $ea.Replace('input double BreakEvenTriggerATR=0.90;', 'input double BreakEvenTriggerATR=1.15;')
$ea = $ea.Replace('input double TrailStartATR=2.75;', 'input double TrailStartATR=3.00;')
$ea = $ea.Replace('input double TrailDistanceATR=1.10;', 'input double TrailDistanceATR=1.20;')
$ea = $ea.Replace('input int MaxHoldBars=28;', 'input int MaxHoldBars=24;')
$ea = $ea.Replace('input double TimeExitMinProgressATR=0.45;', 'input double TimeExitMinProgressATR=0.30;')

# Deterministic architecture: bearish HTF regime, local trend, then either a pullback rejection or a break/retest.
$biasAnchor = @'
   int h1Bias=Bias(PERIOD_H1);
   int h4Bias=Bias(PERIOD_H4);
'@
$stateLines = @'
   int h1Bias=Bias(PERIOD_H1);
   int h4Bias=Bias(PERIOD_H4);
   double closeLocation=(rates[1].close-rates[1].low)/range;
   double bearishDisplacement=(rates[1].open-rates[1].close)/atr;
   double priorStructureLow=LL(rates,3,6);
   bool regimeBearish=(h1Bias<0 && h4Bias<=0);
   bool localBearish=(fast1<slow1 && fast1<=fast2 && rates[1].close<trend);
   bool spreadSafe=(spread<=atr*MaxSpreadATRFraction);
   bool rejectionClose=(rates[1].close<rates[1].open && closeLocation<=0.42 && bearishDisplacement>=0.14);
   bool pullbackTouched=(rates[2].high>=fast2 && rates[2].high<=slow2+atr*0.35);
   bool pullbackHeld=(rates[2].close<=slow2 && rates[1].close<fast1 && rates[1].close<rates[2].low);
   bool pullbackRejectionState=(regimeBearish && localBearish && spreadSafe && pullbackTouched && pullbackHeld && rejectionClose);
   bool priorBreak=(rates[2].close<priorStructureLow && rates[2].close<rates[2].open);
   bool retestTouched=(rates[1].high>=priorStructureLow && rates[1].high<=priorStructureLow+atr*0.30);
   bool retestRejected=(rates[1].close<priorStructureLow && rates[1].close<rates[1].open && closeLocation<=0.45);
   bool breakRetestState=(regimeBearish && localBearish && spreadSafe && priorBreak && retestTouched && retestRejected);
'@
if (!$ea.Contains($biasAnchor)) { throw "V50 cannot find HTF bias insertion point." }
$ea = $ea.Replace($biasAnchor, $stateLines.TrimEnd())

$continuationPattern = '(?ms)^[ \t]*if\(rates\[1\]\.close<rates\[2\]\.low\s*&&\s*rates\[2\]\.close<rates\[2\]\.open\s*&&\s*fast1<fast2\s*&&\s*bodyRatio>=0\.38\s*&&\s*volumeRatio>=MinVolumeRatio\)\s*\r?\n[ \t]*Consider\(-1,"CONTINUATION",sellBase\+18,atr,now\.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate\);'
$stateEntry = @'
      if(pullbackRejectionState && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio)
         Consider(-1,"PULLBACK_REJECTION",sellBase+22,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate);

      if(breakRetestState && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio)
         Consider(-1,"BREAK_RETEST",sellBase+24,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate);
'@
$continuationMatches = [regex]::Matches($ea, $continuationPattern)
if ($continuationMatches.Count -ne 1) { throw "V50 expected exactly one continuation sell condition, found $($continuationMatches.Count)." }
$ea = [regex]::Replace($ea, $continuationPattern, $stateEntry.TrimEnd(), 1)

$ea = $ea.Replace('string comment="V35 "+direction+" "+candidate.setup;', 'string comment="V50 "+direction+" "+candidate.setup;')
$ea = $ea.Replace('"v35_sell_structure route="+activeRoute', '"v50_h8_pullback_break_retest route="+activeRoute')
$ea = $ea.Replace('V35_SELL_STRUCTURE_QUALITY_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_aligned_h4_aligned=true weak_pullback_buy_pruned=true routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true', 'V50_H8_PULLBACK_BREAK_RETEST_STATE_MACHINE risk_normalized=true max_trades_week=4 min_target_pips=400 deterministic_state_machine=true h1_bearish_h4_not_bullish=true routes=STATE_PULLBACK_REJECTION_SELL_08|STATE_BREAK_RETEST_SELL_08 rejected_cells_pruned=07|10|11|12|13|14 rejected_v49_hour09_states=true structural_exits=true')

$required = @(
   'V50_H8_PULLBACK_BREAK_RETEST_STATE_MACHINE',
   'deterministic_state_machine=true',
   'pullbackRejectionState',
   'breakRetestState',
   'pullbackTouched',
   'priorBreak',
   'STATE_PULLBACK_REJECTION_SELL_08',
   'STATE_BREAK_RETEST_SELL_08',
   'MaxTradesPerWeek=4',
   'MinTargetPips=400.0',
   'RiskPercent=0.20'
)
foreach ($marker in $required) {
   if (!$ea.Contains($marker)) { throw "V50 marker missing: $marker" }
}

# Reject only legacy identifiers that cannot collide with valid V50 state names.
$forbidden = @('CORE_CONTINUATION_SELL_07_08','CORE_SWEEP_SELL_13_14','CORE_PULLBACK_BUY_15','EDGE_PULLBACK_SELL_15','EDGE_CONTINUATION_BUY_07_08','STATE_STRUCTURE_BREAK_SELL_09','STATE_SWEEP_FAILURE_SELL_09','STATE_STRUCTURE_BREAK_SELL_08','STATE_SWEEP_FAILURE_SELL_08','TEST_CONTINUATION_SELL_09','TEST_CONTINUATION_SELL_10','TEST_CONTINUATION_SELL_11','TEST_CONTINUATION_SELL_12','ZLEMA_AUTO','Zlema(','boundedRetest','UseEarlyFailureExit','EARLY_FAILURE_ADVERSE','EARLY_FAILURE_STALLED')
foreach ($marker in $forbidden) {
   if ($ea.Contains($marker)) { throw "V50 forbidden marker present: $marker" }
}

Set-Content -Path $eaPath -Value $ea -Encoding UTF8
Write-Host "V50 hour-8 pullback rejection and break-retest transform applied to $eaPath"
