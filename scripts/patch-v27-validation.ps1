$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$runner = Join-Path (Resolve-Path ".").Path "scripts\run-ea-v27-public-backtest.ps1"
$ea = Join-Path (Resolve-Path ".").Path "MQL5\Experts\XAUUSD_V27_Clean_MultiSetup.mq5"

if (!(Test-Path $runner)) { throw "Runner not found: $runner" }
if (!(Test-Path $ea)) { throw "EA not found: $ea" }

$runnerText = Get-Content -Path $runner -Raw -Encoding UTF8
$runnerText = $runnerText.Replace('"MaxTradesPerDay=4"', '"MaxTradesPerDay=3"')
$runnerText = $runnerText.Replace('"CooldownMinutes=45"', '"CooldownMinutes=60"')
$runnerText = $runnerText.Replace('"SlippagePoints=120"', '"SlippagePoints=160"')
$runnerText = $runnerText.Replace('"BrokerStopBufferPoints=40"', '"BrokerStopBufferPoints=60"')
$runnerText = $runnerText.Replace('"FridayLastEntryHour=17"', '"FridayLastEntryHour=16"')
$runnerText = $runnerText.Replace('"MinSignalScore=72.0"', '"MinSignalScore=78.0"')
$runnerText = $runnerText.Replace('"MinDirectionScoreGap=6.0"', '"MinDirectionScoreGap=8.0"')
$runnerText = $runnerText.Replace('"MinADX=16.0"', '"MinADX=18.0"')
$runnerText = $runnerText.Replace('"MaxSpreadATRFraction=0.10"', '"MaxSpreadATRFraction=0.08"')
$runnerText = $runnerText.Replace('"BreakoutLookback=5"', '"BreakoutLookback=8"')
$runnerText = $runnerText.Replace('"SweepLookback=5"', '"SweepLookback=8"')
$runnerText = $runnerText.Replace('"PullbackTouchATR=0.28"', '"PullbackTouchATR=0.18"')
$runnerText = $runnerText.Replace('"MinBodyRatio=0.25"', '"MinBodyRatio=0.32"')
$runnerText = $runnerText.Replace('"MinVolumeRatio=0.80"', '"MinVolumeRatio=0.95"')
$runnerText = $runnerText.Replace('"BreakoutTP_ATR=1.25"', '"BreakoutTP_ATR=1.45"')
$runnerText = $runnerText.Replace('"BreakoutSL_ATR=1.35"', '"BreakoutSL_ATR=0.95"')
$runnerText = $runnerText.Replace('"PullbackTP_ATR=1.10"', '"PullbackTP_ATR=1.25"')
$runnerText = $runnerText.Replace('"PullbackSL_ATR=1.25"', '"PullbackSL_ATR=0.90"')
$runnerText = $runnerText.Replace('"ContinuationTP_ATR=1.00"', '"ContinuationTP_ATR=1.25"')
$runnerText = $runnerText.Replace('"ContinuationSL_ATR=1.30"', '"ContinuationSL_ATR=0.85"')
$runnerText = $runnerText.Replace('"SweepTP_ATR=1.30"', '"SweepTP_ATR=1.10"')
$runnerText = $runnerText.Replace('"SweepSL_ATR=1.20"', '"SweepSL_ATR=0.70"')
$runnerText = $runnerText.Replace('"BreakEvenTriggerATR=0.65"', '"BreakEvenTriggerATR=0.55"')
$runnerText = $runnerText.Replace('"BreakEvenOffsetATR=0.05"', '"BreakEvenOffsetATR=0.03"')
$runnerText = $runnerText.Replace('"TrailStartATR=1.00"', '"TrailStartATR=0.90"')
$runnerText = $runnerText.Replace('"TrailDistanceATR=0.75"', '"TrailDistanceATR=0.55"')
$runnerText = $runnerText.Replace('"MaxHoldBars=20"', '"MaxHoldBars=16"')
$runnerText = $runnerText.Replace('"TimeExitMinProgressATR=0.10"', '"TimeExitMinProgressATR=0.18"')
Set-Content -Path $runner -Value $runnerText -Encoding UTF8

$eaText = Get-Content -Path $ea -Raw -Encoding UTF8
$eaText = $eaText.Replace('#property version   "2.70"', '#property version   "2.71"')
$eaText = $eaText.Replace('ok = trade.Buy(lot, Sym, 0.0, sl, tp, comment);', 'ok = trade.Buy(lot, Sym, entryPrice, sl, tp, comment);')
$eaText = $eaText.Replace('ok = trade.Sell(lot, Sym, 0.0, sl, tp, comment);', 'ok = trade.Sell(lot, Sym, entryPrice, sl, tp, comment);')
$eaText = $eaText.Replace('ok = trade.Buy(lot, Sym, 0.0, 0.0, 0.0, comment + " retry");', 'ok = false;')
$eaText = $eaText.Replace('ok = trade.Sell(lot, Sym, 0.0, 0.0, 0.0, comment + " retry");', 'ok = false;')
Set-Content -Path $ea -Value $eaText -Encoding UTF8

Write-Host "V27 validation patch applied: explicit market prices, no unprotected retry, tighter setup filters."
