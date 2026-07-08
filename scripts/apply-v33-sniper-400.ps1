$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$eaPath = "MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5"
if (!(Test-Path $eaPath)) { throw "EA source missing: $eaPath" }

pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/apply-v32-prune-edge.ps1

$ea = Get-Content $eaPath -Raw

$ea = $ea.Replace('#property version "2.91"', '#property version "2.92"')
$ea = $ea.Replace('V32 Pruned Core Quality Gate: EDGE routes removed', 'V33 Sniper 400 Quality Gate: weekly cap, strict HTF, large TP')
$ea = $ea.Replace('input string CSVJournalName="V32_PRUNED_CORE_journal.csv";', 'input string CSVJournalName="V33_SNIPER_400_journal.csv";')

$ea = $ea.Replace('input int MaxTradesPerDay=4;', "input int MaxTradesPerDay=1;`ninput int MaxTradesPerWeek=4;")
$ea = $ea.Replace('input int CooldownMinutes=45;', 'input int CooldownMinutes=240;')
$ea = $ea.Replace('input int LastEntryHour=19;', 'input int LastEntryHour=18;')
$ea = $ea.Replace('input int LastEntryMinute=15;', 'input int LastEntryMinute=30;')
$ea = $ea.Replace('input double MinSignalScore=78.0;', 'input double MinSignalScore=92.0;')
$ea = $ea.Replace('input double MinADX=20.0;', 'input double MinADX=28.0;')
$ea = $ea.Replace('input double MaxSpreadATRFraction=0.07;', 'input double MaxSpreadATRFraction=0.045;')
$ea = $ea.Replace('input double MinBodyRatio=0.34;', 'input double MinBodyRatio=0.52;')
$ea = $ea.Replace('input double MinVolumeRatio=0.95;', 'input double MinVolumeRatio=1.25;')

$ea = $ea.Replace('input double BreakoutTP_ATR=1.55;', 'input double BreakoutTP_ATR=4.20;')
$ea = $ea.Replace('input double BreakoutSL_ATR=1.05;', 'input double BreakoutSL_ATR=0.72;')
$ea = $ea.Replace('input double PullbackTP_ATR=1.35;', 'input double PullbackTP_ATR=4.00;')
$ea = $ea.Replace('input double PullbackSL_ATR=1.00;', 'input double PullbackSL_ATR=0.68;')
$ea = $ea.Replace('input double ContinuationTP_ATR=1.30;', 'input double ContinuationTP_ATR=4.15;')
$ea = $ea.Replace('input double ContinuationSL_ATR=1.00;', 'input double ContinuationSL_ATR=0.70;')
$ea = $ea.Replace('input double SweepTP_ATR=1.45;', 'input double SweepTP_ATR=4.35;')
$ea = $ea.Replace('input double SweepSL_ATR=0.95;', 'input double SweepSL_ATR=0.72;')
$ea = $ea.Replace('input bool UseBreakEven=true;', "input double PipSize=0.01;`ninput double MinTargetPips=400.0;`ninput bool UseBreakEven=true;")
$ea = $ea.Replace('input double BreakEvenTriggerATR=0.85;', 'input double BreakEvenTriggerATR=0.62;')
$ea = $ea.Replace('input double BreakEvenOffsetATR=0.02;', 'input double BreakEvenOffsetATR=0.04;')
$ea = $ea.Replace('input double TrailStartATR=1.25;', 'input double TrailStartATR=2.80;')
$ea = $ea.Replace('input double TrailDistanceATR=0.70;', 'input double TrailDistanceATR=1.15;')
$ea = $ea.Replace('input int MaxHoldBars=28;', 'input int MaxHoldBars=24;')
$ea = $ea.Replace('input double TimeExitMinProgressATR=0.20;', 'input double TimeExitMinProgressATR=0.55;')

$ea = $ea.Replace('int currentDay=-1;', "int currentDay=-1;`nint currentWeekKey=-1;`nint tradesThisWeek=0;")

$resetDayBlock = @'
void ResetDay()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(),now);
   if(now.year!=currentYear || now.day_of_year!=currentDay)
   {
      currentYear=now.year;
      currentDay=now.day_of_year;
      tradesToday=0;
   }
}
'@
$resetDayReplacement = @'
int WeekKey(const MqlDateTime &dt)
{
   return dt.year*100+(dt.day_of_year/7);
}

void ResetDay()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(),now);
   if(now.year!=currentYear || now.day_of_year!=currentDay)
   {
      currentYear=now.year;
      currentDay=now.day_of_year;
      tradesToday=0;
   }

   int weekKey=WeekKey(now);
   if(weekKey!=currentWeekKey)
   {
      currentWeekKey=weekKey;
      tradesThisWeek=0;
   }
}
'@
$ea = $ea.Replace($resetDayBlock, $resetDayReplacement)

$ea = $ea.Replace('double tpDistance=MathMax(atr*tpMultiplier,minDistance);', 'double tpDistance=MathMax(MathMax(atr*tpMultiplier,minDistance),MinTargetPips*PipSize);')
$ea = $ea.Replace('if((buy && h4Bias<0) || (!buy && h4Bias>0))', 'if((buy && h4Bias<=0) || (!buy && h4Bias>=0))')

$routeQualityBlock = @'
bool RouteQuality(string setup,int dir,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if((dir>0 && h1Bias<=0) || (dir<0 && h1Bias>=0))
      return false;
   if((dir>0 && h4Bias<0) || (dir<0 && h4Bias>0))
      return false;
   if(adx<MinADX || volumeRatio<MinVolumeRatio || bodyRatio<MinBodyRatio)
      return false;

   if(setup=="PULLBACK" && dir>0)
      return rsi>51 && rsi<66 && volumeRatio>=1.00 && bodyRatio>=0.36;
   if(setup=="PULLBACK" && dir<0)
      return rsi>34 && rsi<49 && volumeRatio>=1.00 && bodyRatio>=0.36;
   if(setup=="CONTINUATION" && dir<0)
      return rsi>=35 && rsi<=47 && volumeRatio>=1.04 && bodyRatio>=0.38;
   if(setup=="CONTINUATION" && dir>0)
      return rsi>=53 && rsi<=65 && volumeRatio>=1.04 && bodyRatio>=0.38;
   if(setup=="SWEEP" && dir<0)
      return rsi>34 && rsi<50 && volumeRatio>=1.00 && bodyRatio>=0.36;

   return true;
}
'@
$routeQualityReplacement = @'
bool RouteQuality(string setup,int dir,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if((dir>0 && h1Bias<=0) || (dir<0 && h1Bias>=0))
      return false;
   if((dir>0 && h4Bias<=0) || (dir<0 && h4Bias>=0))
      return false;
   if(adx<MinADX || volumeRatio<MinVolumeRatio || bodyRatio<MinBodyRatio)
      return false;

   if(setup=="PULLBACK" && dir>0)
      return rsi>=56 && rsi<=63 && adx>=28 && volumeRatio>=1.28 && bodyRatio>=0.52;
   if(setup=="CONTINUATION" && dir<0)
      return rsi>=37 && rsi<=44 && adx>=30 && volumeRatio>=1.30 && bodyRatio>=0.54;
   if(setup=="SWEEP" && dir<0)
      return rsi>=37 && rsi<=47 && adx>=29 && volumeRatio>=1.32 && bodyRatio>=0.55;

   return false;
}
'@
$ea = $ea.Replace($routeQualityBlock, $routeQualityReplacement)

$ea = $ea.Replace('if(rsi>=54 && rsi<=64)', 'if(rsi>=57 && rsi<=62)')
$ea = $ea.Replace('else if(rsi>=52 && rsi<=66)', 'else if(rsi>=55 && rsi<=64)')
$ea = $ea.Replace('if(rsi>=36 && rsi<=46)', 'if(rsi>=38 && rsi<=43)')
$ea = $ea.Replace('else if(rsi>=34 && rsi<=48)', 'else if(rsi>=36 && rsi<=46)')
$ea = $ea.Replace('if(adx>=28)', 'if(adx>=34)')
$ea = $ea.Replace('else if(adx>=MinADX)', 'else if(adx>=MinADX)')
$ea = $ea.Replace('if(volumeRatio>=1.20)', 'if(volumeRatio>=1.45)')
$ea = $ea.Replace('else if(volumeRatio>=MinVolumeRatio)', 'else if(volumeRatio>=MinVolumeRatio)')
$ea = $ea.Replace('if(bodyRatio>=0.60)', 'if(bodyRatio>=0.68)')
$ea = $ea.Replace('else if(bodyRatio>=MinBodyRatio)', 'else if(bodyRatio>=MinBodyRatio)')

$ea = $ea.Replace('tradesToday++;', "tradesToday++;`n   tradesThisWeek++;")
$ea = $ea.Replace('tradesToday>=MaxTradesPerDay ||', 'tradesToday>=MaxTradesPerDay || tradesThisWeek>=MaxTradesPerWeek ||')
$ea = $ea.Replace('string comment="V32 "+direction+" "+candidate.setup;', 'string comment="V33 "+direction+" "+candidate.setup;')
$ea = $ea.Replace('"v32_pruned_core route="+activeRoute', '"v33_sniper_400 route="+activeRoute')
$ea = $ea.Replace('V32_PRUNED_CORE_QUALITY_GATE risk_normalized=true routes=CORE_PULLBACK_BUY_15|CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true', 'V33_SNIPER_400_QUALITY_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 strict_h1_h4=true routes=CORE_PULLBACK_BUY_15|CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true')

$required = @(
  'V33_SNIPER_400_QUALITY_GATE',
  'MaxTradesPerWeek=4',
  'MinTargetPips=400.0',
  'PipSize=0.01',
  'tradesThisWeek',
  'RiskPercent=0.20',
  'OrderCalcProfit'
)
foreach ($marker in $required) {
  if (!$ea.Contains($marker)) { throw "V33 marker missing: $marker" }
}

$forbidden = @('EDGE_PULLBACK_SELL_15','EDGE_CONTINUATION_BUY_07_08','ZLEMA_AUTO','Zlema(')
foreach ($marker in $forbidden) {
  if ($ea.Contains($marker)) { throw "V33 forbidden marker present: $marker" }
}

Set-Content -Path $eaPath -Value $ea -Encoding UTF8
Write-Host "V33 sniper 400 transform applied to $eaPath"