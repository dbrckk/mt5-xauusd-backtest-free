$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$eaPath = "MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5"
if (!(Test-Path $eaPath)) { throw "EA source missing: $eaPath" }

# Rebuild deterministically from the committed V35 sell-only profile.
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/apply-v35-sell-structure.ps1
$ea = Get-Content $eaPath -Raw

# Identity.
$ea = $ea.Replace('#property version "2.94"', '#property version "3.00"')
$ea = $ea.Replace('V35 Sell Structure Quality Gate: weak pullback route pruned', 'V42 Hour-8 Break-Retest State Machine: supported cell only')
$ea = $ea.Replace('input string CSVJournalName="V35_SELL_STRUCTURE_journal.csv";', 'input string CSVJournalName="V42_H8_STATE_MACHINE_journal.csv";')

# Keep only the independently supported continuation cell at hour 08.
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
   if(setup=="CONTINUATION" && dir<0 && hour==8)
   {
      name="CORE_CONTINUATION_SELL_08";
      return true;
   }
'@
if (!$ea.Contains($routeOld)) { throw "V42 cannot find V35 sell route block." }
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
$routeQualityV42 = @'
bool RouteQuality(string setup,int dir,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if(dir>=0 || setup!="CONTINUATION")
      return false;
   if(h1Bias>=0 || h4Bias>0)
      return false;
   if(adx<MinADX || volumeRatio<MinVolumeRatio || bodyRatio<MinBodyRatio)
      return false;

   return rsi>=26 && rsi<=60 && adx>=15 && volumeRatio>=0.65 && bodyRatio>=0.12;
}
'@
if (!$ea.Contains($routeQualityV35)) { throw "V42 cannot find V35 RouteQuality block." }
$ea = $ea.Replace($routeQualityV35, $routeQualityV42)

# Preserve the V41 scalar opportunity envelope and V40 exits; isolate architecture as the only experiment.
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

$globalAnchor = 'double activeRisk=0.0;'
$globalState = @'
double activeRisk=0.0;
int h8State=0;
int h8StateDay=-1;
double h8ReferenceLow=0.0;
datetime h8BreakBarTime=0;
'@
if (!$ea.Contains($globalAnchor)) { throw "V42 cannot find global state anchor." }
$ea = $ea.Replace($globalAnchor, $globalState.TrimEnd())

$volumeLine = '   double volumeRatio=volumeSma>0?(double)rates[1].tick_volume/volumeSma:0;'
$stateLines = @'
   double volumeRatio=volumeSma>0?(double)rates[1].tick_volume/volumeSma:0;
   double closeLocation=(rates[1].close-rates[1].low)/range;
   double bearishDisplacement=(rates[1].open-rates[1].close)/atr;
   double recentLow=LL(rates,2,4);
   bool bearishState=(fast1<slow1 && fast1<=fast2 && rates[1].close<fast1);

   MqlDateTime stateClock;
   TimeToStruct(rates[1].time,stateClock);
   int stateDay=stateClock.year*1000+stateClock.day_of_year;
   if(stateDay!=h8StateDay)
   {
      h8StateDay=stateDay;
      h8State=0;
      h8ReferenceLow=0.0;
      h8BreakBarTime=0;
   }

   bool setupWindow=(stateClock.hour==7 && stateClock.min>=45) || stateClock.hour==8;
   if(!setupWindow && h8State!=3)
   {
      h8State=0;
      h8ReferenceLow=0.0;
      h8BreakBarTime=0;
   }

   if(h8State==0 && setupWindow && bearishState && h1Bias<0 && h4Bias<=0)
   {
      h8State=1;
      h8ReferenceLow=recentLow;
   }

   bool structureBreak=(h8State==1 && stateClock.hour==8 && rates[1].low<h8ReferenceLow && rates[1].close<=h8ReferenceLow-atr*0.02);
   if(structureBreak)
   {
      h8State=2;
      h8BreakBarTime=rates[1].time;
   }

   bool boundedRetest=(h8State==2 && rates[1].time>h8BreakBarTime && rates[1].time-h8BreakBarTime<=45*60);
   bool retestTouch=(rates[1].high>=h8ReferenceLow-atr*0.12);
   bool bearishRejection=(rates[1].close<h8ReferenceLow && rates[1].close<rates[1].open && closeLocation<=0.60 && bearishDisplacement>=0.02);
   bool h8StateTrigger=(boundedRetest && retestTouch && bearishRejection && bearishState);
'@
if (!$ea.Contains($volumeLine)) { throw "V42 cannot find volume ratio insertion point." }
$ea = $ea.Replace($volumeLine, $stateLines.TrimEnd())

$continuationOld = '      if(rates[1].close<rates[2].low && rates[2].close<rates[2].open && fast1<fast2 && bodyRatio>=0.38 && volumeRatio>=MinVolumeRatio)'
$continuationNew = '      if(h8StateTrigger && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio)'
if (!$ea.Contains($continuationOld)) { throw "V42 cannot find continuation sell condition." }
$ea = $ea.Replace($continuationOld, $continuationNew)

$considerLine = '         Consider(-1,"CONTINUATION",sellBase+18,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate);'
$considerBlock = @'
      {
         Consider(-1,"CONTINUATION",sellBase+18,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate);
         h8State=3;
      }
'@
if (!$ea.Contains($considerLine)) { throw "V42 cannot find continuation Consider call." }
$ea = $ea.Replace($considerLine, $considerBlock.TrimEnd())

$ea = $ea.Replace('string comment="V35 "+direction+" "+candidate.setup;', 'string comment="V42 "+direction+" "+candidate.setup;')
$ea = $ea.Replace('"v35_sell_structure route="+activeRoute', '"v42_h8_state_machine route="+activeRoute')
$ea = $ea.Replace('V35_SELL_STRUCTURE_QUALITY_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_aligned_h4_aligned=true weak_pullback_buy_pruned=true routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true', 'V42_H8_BREAK_RETEST_STATE_MACHINE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_bearish_h4_not_bullish=true deterministic_state=true setup_break_retest=true one_entry_per_state=true exits_locked_v40=true routes=CORE_CONTINUATION_SELL_08 rejected_cells_pruned=true')

$required = @(
  'V42_H8_BREAK_RETEST_STATE_MACHINE',
  'deterministic_state=true',
  'setup_break_retest=true',
  'one_entry_per_state=true',
  'h8StateTrigger',
  'boundedRetest',
  'CORE_CONTINUATION_SELL_08',
  'MaxTradesPerWeek=4',
  'MinTargetPips=400.0',
  'RiskPercent=0.20'
)
foreach ($marker in $required) {
  if (!$ea.Contains($marker)) { throw "V42 marker missing: $marker" }
}

$forbidden = @('CORE_CONTINUATION_SELL_07_08','CORE_SWEEP_SELL_13_14','CORE_PULLBACK_BUY_15','EDGE_PULLBACK_SELL_15','EDGE_CONTINUATION_BUY_07_08','ZLEMA_AUTO','Zlema(')
foreach ($marker in $forbidden) {
  if ($ea.Contains($marker)) { throw "V42 forbidden marker present: $marker" }
}

Set-Content -Path $eaPath -Value $ea -Encoding UTF8
Write-Host "V42 hour-8 break-retest state-machine transform applied to $eaPath"