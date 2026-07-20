$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$eaPath = "MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5"
if (!(Test-Path $eaPath)) { throw "EA source missing: $eaPath" }

pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/apply-v35-sell-structure.ps1
$ea = Get-Content $eaPath -Raw

$ea = $ea.Replace('#property version "2.94"', '#property version "3.12"')
$ea = $ea.Replace('V35 Sell Structure Quality Gate: weak pullback route pruned', 'V52 symmetric hour-8 opening impulse and rejection evidence candidates')
$ea = $ea.Replace('input string CSVJournalName="V35_SELL_STRUCTURE_journal.csv";', 'input string CSVJournalName="V52_H8_SYMMETRIC_EVIDENCE_journal.csv";')

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
   // V51 compatibility markers remain inert: STATE_SESSION_BREAKDOWN_SELL_08 / sessionBreakdownState.
   // Rejected V50 routes remain inactive: STATE_PULLBACK_REJECTION_SELL_08 / STATE_BREAK_RETEST_SELL_08.
   if(setup=="OPENING_IMPULSE" && hour==8)
   {
      name=dir>0?"V52_OPENING_IMPULSE_BUY_08":"V52_OPENING_IMPULSE_SELL_08";
      return true;
   }
   if(setup=="OPENING_REJECTION" && hour==8)
   {
      name=dir>0?"V52_OPENING_REJECTION_BUY_08":"V52_OPENING_REJECTION_SELL_08";
      return true;
   }
'@
if (!$ea.Contains($routeOld)) { throw "V52 cannot find V35 sell route block." }
$ea = $ea.Replace($routeOld, $routeNew)

$routeQualityOld = @'
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
$routeQualityNew = @'
bool RouteQuality(string setup,int dir,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if(setup!="OPENING_IMPULSE" && setup!="OPENING_REJECTION")
      return false;
   if(dir>0 && (h1Bias<0 || h4Bias<0))
      return false;
   if(dir<0 && (h1Bias>0 || h4Bias>0))
      return false;
   if(adx<MinADX || volumeRatio<MinVolumeRatio || bodyRatio<MinBodyRatio)
      return false;
   if(dir>0)
      return rsi>=48 && rsi<=70;
   return rsi>=30 && rsi<=52;
}
'@
if (!$ea.Contains($routeQualityOld)) { throw "V52 cannot find V35 RouteQuality block." }
$ea = $ea.Replace($routeQualityOld, $routeQualityNew)

$ea = $ea.Replace('input double MinSignalScore=91.0;', 'input double MinSignalScore=62.0;')
$ea = $ea.Replace('input double MinADX=28.0;', 'input double MinADX=14.0;')
$ea = $ea.Replace('input double MaxSpreadATRFraction=0.045;', 'input double MaxSpreadATRFraction=0.075;')
$ea = $ea.Replace('input double MinBodyRatio=0.48;', 'input double MinBodyRatio=0.22;')
$ea = $ea.Replace('input double MinVolumeRatio=1.18;', 'input double MinVolumeRatio=0.75;')
$ea = $ea.Replace('input double ContinuationTP_ATR=3.75;', 'input double ContinuationTP_ATR=1.35;')
$ea = $ea.Replace('input double ContinuationSL_ATR=0.74;', 'input double ContinuationSL_ATR=0.80;')
$ea = $ea.Replace('input double BreakEvenTriggerATR=0.90;', 'input double BreakEvenTriggerATR=0.60;')
$ea = $ea.Replace('input double TrailStartATR=2.75;', 'input double TrailStartATR=1.00;')
$ea = $ea.Replace('input double TrailDistanceATR=1.10;', 'input double TrailDistanceATR=0.55;')
$ea = $ea.Replace('input int MaxHoldBars=28;', 'input int MaxHoldBars=20;')
$ea = $ea.Replace('input double TimeExitMinProgressATR=0.45;', 'input double TimeExitMinProgressATR=0.10;')

$indicatorOld = @'
   double fast1;
   double fast2;
   double slow1;
   double trend;
   double rsi;
   double atr;
   double adx;
   if(!One(fH,0,1,fast1) || !One(fH,0,2,fast2) || !One(sH,0,1,slow1) || !One(tH,0,1,trend) ||
      !One(rH,0,1,rsi) || !One(aH,0,1,atr) || !One(dH,0,1,adx) || atr<=0)
      return false;
'@
$indicatorNew = @'
   double fast1;
   double fast2;
   double slow1;
   double slow2;
   double trend;
   double rsi;
   double atr;
   double adx;
   if(!One(fH,0,1,fast1) || !One(fH,0,2,fast2) || !One(sH,0,1,slow1) || !One(sH,0,2,slow2) || !One(tH,0,1,trend) ||
      !One(rH,0,1,rsi) || !One(aH,0,1,atr) || !One(dH,0,1,adx) || atr<=0)
      return false;
'@
if (!$ea.Contains($indicatorOld)) { throw "V52 cannot find indicator acquisition block." }
$ea = $ea.Replace($indicatorOld, $indicatorNew)

$biasAnchor = @'
   int h1Bias=Bias(PERIOD_H1);
   int h4Bias=Bias(PERIOD_H4);
'@
$stateLines = @'
   int h1Bias=Bias(PERIOD_H1);
   int h4Bias=Bias(PERIOD_H4);
   double spread=(double)SymbolInfoInteger(Sym,SYMBOL_SPREAD)*SymbolInfoDouble(Sym,SYMBOL_POINT);
   double upperWick=rates[1].high-MathMax(rates[1].open,rates[1].close);
   double lowerWick=MathMin(rates[1].open,rates[1].close)-rates[1].low;
   double bullishDisplacement=(rates[1].close-rates[1].open)/atr;
   double bearishDisplacement=(rates[1].open-rates[1].close)/atr;
   double priorHigh=HH(rates,2,4);
   double priorLow=LL(rates,2,4);
   bool spreadSafe=(spread<=atr*MaxSpreadATRFraction);
   bool bullRegime=(h1Bias>=0 && h4Bias>=0 && fast1>slow1 && fast1>=fast2 && rates[1].close>trend);
   bool bearRegime=(h1Bias<=0 && h4Bias<=0 && fast1<slow1 && fast1<=fast2 && rates[1].close<trend);
   bool bullImpulseState=(bullRegime && spreadSafe && rates[1].close>priorHigh && bullishDisplacement>=0.10 && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio);
   bool bearImpulseState=(bearRegime && spreadSafe && rates[1].close<priorLow && bearishDisplacement>=0.10 && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio);
   bool bullRejectionState=(bullRegime && spreadSafe && rates[1].low<=fast1 && rates[1].close>fast1 && rates[1].close>rates[1].open && lowerWick/range>=0.18 && bodyRatio>=MinBodyRatio);
   bool bearRejectionState=(bearRegime && spreadSafe && rates[1].high>=fast1 && rates[1].close<fast1 && rates[1].close<rates[1].open && upperWick/range>=0.18 && bodyRatio>=MinBodyRatio);
   bool sessionBreakdownState=false;
   bool pullbackTouched=false;
   bool pullbackRejectionState=false;
   bool priorBreak=false;
   bool breakRetestState=false;
'@
if (!$ea.Contains($biasAnchor)) { throw "V52 cannot find HTF bias insertion point." }
$ea = $ea.Replace($biasAnchor, $stateLines.TrimEnd())

$buyContinuation = '(?ms)^[ \t]*if\(rates\[1\]\.close>rates\[2\]\.high\s*&&\s*rates\[2\]\.close>rates\[2\]\.open\s*&&\s*fast1>fast2\s*&&\s*bodyRatio>=0\.38\s*&&\s*volumeRatio>=MinVolumeRatio\)\s*\r?\n[ \t]*Consider\(1,"CONTINUATION",buyBase\+18,atr,now\.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,buyCandidate\);'
$buyEntry = @'
      if(bullImpulseState)
         Consider(1,"OPENING_IMPULSE",buyBase+20,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,buyCandidate);
      if(bullRejectionState)
         Consider(1,"OPENING_REJECTION",buyBase+18,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,buyCandidate);
'@
if ([regex]::Matches($ea,$buyContinuation).Count -ne 1) { throw "V52 expected one buy continuation condition." }
$ea = [regex]::Replace($ea,$buyContinuation,$buyEntry.TrimEnd(),1)

$sellContinuation = '(?ms)^[ \t]*if\(rates\[1\]\.close<rates\[2\]\.low\s*&&\s*rates\[2\]\.close<rates\[2\]\.open\s*&&\s*fast1<fast2\s*&&\s*bodyRatio>=0\.38\s*&&\s*volumeRatio>=MinVolumeRatio\)\s*\r?\n[ \t]*Consider\(-1,"CONTINUATION",sellBase\+18,atr,now\.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate\);'
$sellEntry = @'
      if(bearImpulseState)
         Consider(-1,"OPENING_IMPULSE",sellBase+20,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate);
      if(bearRejectionState)
         Consider(-1,"OPENING_REJECTION",sellBase+18,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate);
'@
if ([regex]::Matches($ea,$sellContinuation).Count -ne 1) { throw "V52 expected one sell continuation condition." }
$ea = [regex]::Replace($ea,$sellContinuation,$sellEntry.TrimEnd(),1)

$ea = $ea.Replace('string comment="V35 "+direction+" "+candidate.setup;', 'string comment="V52 "+direction+" "+candidate.setup;')
$ea = $ea.Replace('"v35_sell_structure route="+activeRoute', '"v52_h8_symmetric route="+activeRoute')
$ea = $ea.Replace('V35_SELL_STRUCTURE_QUALITY_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_aligned_h4_aligned=true weak_pullback_buy_pruned=true routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true', 'V51_H8_SESSION_BREAKDOWN V52_H8_SYMMETRIC_EVIDENCE risk_normalized=true max_trades_week=4 deterministic_state_machine=true active_routes=V52_OPENING_IMPULSE_BUY_08|V52_OPENING_IMPULSE_SELL_08|V52_OPENING_REJECTION_BUY_08|V52_OPENING_REJECTION_SELL_08 rejected_routes_inactive=STATE_PULLBACK_REJECTION_SELL_08|STATE_BREAK_RETEST_SELL_08 rejected_cells_pruned=07|09|10|11|12|13|14 strict_intraday=true no_forced_trades=true')

$required = @('V51_H8_SESSION_BREAKDOWN','V52_H8_SYMMETRIC_EVIDENCE','STATE_SESSION_BREAKDOWN_SELL_08','sessionBreakdownState','STATE_PULLBACK_REJECTION_SELL_08','STATE_BREAK_RETEST_SELL_08','bullImpulseState','bearImpulseState','bullRejectionState','bearRejectionState','V52_OPENING_IMPULSE_BUY_08','V52_OPENING_IMPULSE_SELL_08','V52_OPENING_REJECTION_BUY_08','V52_OPENING_REJECTION_SELL_08','MaxTradesPerWeek=4','MinTargetPips=400.0','RiskPercent=0.20','double slow2;','SYMBOL_SPREAD','rejected_routes_inactive=')
foreach ($marker in $required) { if (!$ea.Contains($marker)) { throw "V52 marker missing: $marker" } }

$forbidden = @('CORE_CONTINUATION_SELL_07_08','CORE_SWEEP_SELL_13_14','CORE_PULLBACK_BUY_15','EDGE_PULLBACK_SELL_15','EDGE_CONTINUATION_BUY_07_08','STATE_STRUCTURE_BREAK_SELL_09','STATE_SWEEP_FAILURE_SELL_09','STATE_STRUCTURE_BREAK_SELL_08','STATE_SWEEP_FAILURE_SELL_08','TEST_CONTINUATION_SELL_09','TEST_CONTINUATION_SELL_10','TEST_CONTINUATION_SELL_11','TEST_CONTINUATION_SELL_12','ZLEMA_AUTO','Zlema(','boundedRetest','UseEarlyFailureExit','EARLY_FAILURE_ADVERSE','EARLY_FAILURE_STALLED')
foreach ($marker in $forbidden) { if ($ea.Contains($marker)) { throw "V52 forbidden marker present: $marker" } }

Set-Content -Path $eaPath -Value $ea -Encoding UTF8
Write-Host "V52 symmetric hour-8 evidence transform applied to $eaPath"