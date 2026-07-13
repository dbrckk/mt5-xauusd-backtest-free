$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$eaPath = "MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5"
if (!(Test-Path $eaPath)) { throw "EA source missing: $eaPath" }

# Rebuild deterministically from the committed V35 sell-only profile.
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/apply-v35-sell-structure.ps1
$ea = Get-Content $eaPath -Raw

# Identity.
$ea = $ea.Replace('#property version "2.94"', '#property version "2.97"')
$ea = $ea.Replace('V35 Sell Structure Quality Gate: weak pullback route pruned', 'V39 Structure Impulse Gate: validated routes only')
$ea = $ea.Replace('input string CSVJournalName="V35_SELL_STRUCTURE_journal.csv";', 'input string CSVJournalName="V39_STRUCTURE_IMPULSE_journal.csv";')

# V38 remained statistically unusable (8 trades across four full periods). V39 broadens
# only the two accepted route-hour cells, while retaining deterministic HTF bearish regime,
# spread controls, natural signals, risk normalization, weekly cap and strict intraday flat.
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
$routeQualityV39 = @'
bool RouteQuality(string setup,int dir,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if(dir>=0)
      return false;
   if(h1Bias>=0 || h4Bias>=0)
      return false;
   if(adx<MinADX || volumeRatio<MinVolumeRatio || bodyRatio<MinBodyRatio)
      return false;

   if(setup=="CONTINUATION" && dir<0)
      return rsi>=30 && rsi<=54 && adx>=16 && volumeRatio>=0.75 && bodyRatio>=0.18;
   if(setup=="SWEEP" && dir<0)
      return rsi>=30 && rsi<=56 && adx>=16 && volumeRatio>=0.75 && bodyRatio>=0.18;

   return false;
}
'@
if (!$ea.Contains($routeQualityV35)) { throw "V39 cannot find V35 RouteQuality block." }
$ea = $ea.Replace($routeQualityV35, $routeQualityV39)

# Recover a useful sample without opening rejected routes or hours.
$ea = $ea.Replace('input double MinSignalScore=91.0;', 'input double MinSignalScore=76.0;')
$ea = $ea.Replace('input double MinADX=28.0;', 'input double MinADX=16.0;')
$ea = $ea.Replace('input double MaxSpreadATRFraction=0.045;', 'input double MaxSpreadATRFraction=0.070;')
$ea = $ea.Replace('input double MinBodyRatio=0.48;', 'input double MinBodyRatio=0.18;')
$ea = $ea.Replace('input double MinVolumeRatio=1.18;', 'input double MinVolumeRatio=0.75;')

$volumeLine = '   double volumeRatio=volumeSma>0?(double)rates[1].tick_volume/volumeSma:0;'
$geometryLines = @'
   double volumeRatio=volumeSma>0?(double)rates[1].tick_volume/volumeSma:0;
   double closeLocation=(rates[1].close-rates[1].low)/range;
   double upperWickRatio=(rates[1].high-MathMax(rates[1].open,rates[1].close))/range;
   double bearishDisplacement=(rates[1].open-rates[1].close)/atr;
'@
if (!$ea.Contains($volumeLine)) { throw "V39 cannot find volume ratio insertion point." }
$ea = $ea.Replace($volumeLine, $geometryLines.TrimEnd())

# Continuation becomes a deterministic bearish impulse / structure-pressure event.
$continuationOld = '      if(rates[1].close<rates[2].low && rates[2].close<rates[2].open && fast1<fast2 && bodyRatio>=0.38 && volumeRatio>=MinVolumeRatio)'
$continuationNew = '      if(rates[1].close<rates[2].close && rates[1].close<rates[1].open && fast1<slow1 && fast1<=fast2 && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio && closeLocation<=0.55 && bearishDisplacement>=0.10)'
if (!$ea.Contains($continuationOld)) { throw "V39 cannot find continuation sell condition." }
$ea = $ea.Replace($continuationOld, $continuationNew)

# Sweep remains genuine: takes prior liquidity, closes back below it, and rejects upper range.
$sweepOld = '      if(h1Bias<0 && h4Bias<0 && rates[1].high>previousHigh && rates[1].close<previousHigh && rates[1].close<rates[1].open && rsi<53 && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio)'
$sweepNew = '      if(h1Bias<0 && h4Bias<0 && rates[1].high>previousHigh && rates[1].close<previousHigh && rates[1].close<rates[1].open && rsi<56 && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio && closeLocation<=0.60 && upperWickRatio>=0.12)'
if (!$ea.Contains($sweepOld)) { throw "V39 cannot find sweep sell condition." }
$ea = $ea.Replace($sweepOld, $sweepNew)

$ea = $ea.Replace('string comment="V35 "+direction+" "+candidate.setup;', 'string comment="V39 "+direction+" "+candidate.setup;')
$ea = $ea.Replace('"v35_sell_structure route="+activeRoute', '"v39_structure_impulse route="+activeRoute')
$ea = $ea.Replace('V35_SELL_STRUCTURE_QUALITY_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_aligned_h4_aligned=true weak_pullback_buy_pruned=true routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true', 'V39_STRUCTURE_IMPULSE_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_aligned_h4_aligned=true bearish_displacement=true routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true')

$required = @(
  'V39_STRUCTURE_IMPULSE_GATE',
  'bearish_displacement=true',
  'bearishDisplacement>=0.10',
  'upperWickRatio>=0.12',
  'MaxTradesPerWeek=4',
  'MinTargetPips=400.0',
  'RiskPercent=0.20',
  'CORE_CONTINUATION_SELL_07_08',
  'CORE_SWEEP_SELL_13_14'
)
foreach ($marker in $required) {
  if (!$ea.Contains($marker)) { throw "V39 marker missing: $marker" }
}

$forbidden = @('EDGE_PULLBACK_SELL_15','EDGE_CONTINUATION_BUY_07_08','CORE_PULLBACK_BUY_15','ZLEMA_AUTO','Zlema(')
foreach ($marker in $forbidden) {
  if ($ea.Contains($marker)) { throw "V39 forbidden marker present: $marker" }
}

Set-Content -Path $eaPath -Value $ea -Encoding UTF8
Write-Host "V39 structure-impulse transform applied to $eaPath"