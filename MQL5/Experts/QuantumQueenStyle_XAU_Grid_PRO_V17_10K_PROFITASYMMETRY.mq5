//+------------------------------------------------------------------+

//| QuantumQueenStyle_XAU_Grid_PRO_V17_10K_PROFITASYMMETRY.mq5 |

//| Original MT5 EA for XAUUSD. 10K max-runner with strict lot band.|

//| Not copied from any MQL5 Market product. |

//+------------------------------------------------------------------+

#property strict

#property version "17.00"

#property description "XAUUSD V17 10K ProfitAsymmetry: single version for 10,000 capital, 0.01 base lot, 0.04 total max exposure, no martingale, no classic grid, adaptive elite entries, profit-only pyramiding, bigger runner capture and faster invalidation cuts."

//-------------------- Self-contained trade adapter --------------------

// This EA intentionally avoids #include <Trade/Trade.mqh> so GitHub Actions

// can compile it even when the MT5 standard Include folder is missing on a

// fresh cloud runner. It implements only the CTrade methods used below.

class CTrade

{

private:

ulong m_magic;

int m_deviation;

ENUM_ORDER_TYPE_FILLING m_filling;

bool IsGoodRetcode(const uint retcode)

{

return (retcode == TRADE_RETCODE_DONE ||

retcode == TRADE_RETCODE_DONE_PARTIAL ||

retcode == TRADE_RETCODE_PLACED);

}

bool SendDeal(const string symbol,

const ENUM_ORDER_TYPE orderType,

const double volume,

double price,

const double sl,

const double tp,

const string comment,

const ulong positionTicket = 0)

{

if(volume <= 0.0) return false;

MqlTick tick;

if(!SymbolInfoTick(symbol, tick)) return false;

if(price <= 0.0)

{

price = (orderType == ORDER_TYPE_BUY ? tick.ask : tick.bid);

}

MqlTradeRequest request;

MqlTradeResult result;

ZeroMemory(request);

ZeroMemory(result);

request.action = TRADE_ACTION_DEAL;

request.symbol = symbol;

request.volume = volume;

request.type = orderType;

request.price = price;

request.sl = sl;

request.tp = tp;

request.deviation = m_deviation;

request.magic = m_magic;

request.comment = comment;

request.type_time = ORDER_TIME_GTC;

request.type_filling = m_filling;

if(positionTicket > 0) request.position = positionTicket;

if(!OrderSend(request, result)) return false;

return IsGoodRetcode(result.retcode);

}

public:

CTrade()

{

m_magic = 0;

m_deviation = 30;

m_filling = ORDER_FILLING_IOC;

}

void SetExpertMagicNumber(const ulong magic)

{

m_magic = magic;

}

void SetDeviationInPoints(const int deviation)

{

m_deviation = deviation;

}

void SetTypeFillingBySymbol(const string symbol)

{

long filling = 0;

if(SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE, filling))

{

if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)

m_filling = ORDER_FILLING_FOK;

else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)

m_filling = ORDER_FILLING_IOC;

else

m_filling = ORDER_FILLING_RETURN;

}

}

bool Buy(const double volume,

const string symbol,

const double price = 0.0,

const double sl = 0.0,

const double tp = 0.0,

const string comment = "")

{

return SendDeal(symbol, ORDER_TYPE_BUY, volume, price, sl, tp, comment, 0);

}

bool Sell(const double volume,

const string symbol,

const double price = 0.0,

const double sl = 0.0,

const double tp = 0.0,

const string comment = "")

{

return SendDeal(symbol, ORDER_TYPE_SELL, volume, price, sl, tp, comment, 0);

}

bool PositionModify(const ulong ticket, const double sl, const double tp)

{

if(!PositionSelectByTicket(ticket)) return false;

MqlTradeRequest request;

MqlTradeResult result;

ZeroMemory(request);

ZeroMemory(result);

request.action = TRADE_ACTION_SLTP;

request.position = ticket;

request.symbol = PositionGetString(POSITION_SYMBOL);

request.sl = sl;

request.tp = tp;

request.magic = m_magic;

if(!OrderSend(request, result)) return false;

return IsGoodRetcode(result.retcode);

}

bool PositionClose(const ulong ticket)

{

if(!PositionSelectByTicket(ticket)) return false;

string symbol = PositionGetString(POSITION_SYMBOL);

double volume = PositionGetDouble(POSITION_VOLUME);

long posType = PositionGetInteger(POSITION_TYPE);

ENUM_ORDER_TYPE closeType = (posType == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);

return SendDeal(symbol, closeType, volume, 0.0, 0.0, 0.0, "close", ticket);

}

bool PositionClosePartial(const ulong ticket, const double volumeToClose)

{

if(!PositionSelectByTicket(ticket)) return false;

string symbol = PositionGetString(POSITION_SYMBOL);

double currentVolume = PositionGetDouble(POSITION_VOLUME);

double closeVolume = MathMin(volumeToClose, currentVolume);

if(closeVolume <= 0.0) return false;

long posType = PositionGetInteger(POSITION_TYPE);

ENUM_ORDER_TYPE closeType = (posType == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);

return SendDeal(symbol, closeType, closeVolume, 0.0, 0.0, 0.0, "partial", ticket);

}

};

CTrade trade;

//-------------------- Core --------------------

input string InpTradeSymbol = "XAUUSD";

input ulong InpMagic = 11880517;

input ENUM_TIMEFRAMES InpSignalTF = PERIOD_M15;

input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H1;

input ENUM_TIMEFRAMES InpMacroTF = PERIOD_H4;

input bool InpOneDecisionPerBar = true;

input bool InpRequireHedgingAccount = false;

//-------------------- Money management --------------------

input bool InpUseRiskLot = false;

input double InpFixedLot = 0.01;

input double InpRiskPercent = 0.08;

input double InpCapitalReference = 10000.0;

input bool InpForceTenKLotBand = true;

input double InpMinAllowedLot = 0.01;

input double InpMaxAllowedSingleLot = 0.04;

input double InpMaxAllowedTotalLots = 0.04;

input double InpMaxTotalLots = 0.04;

input double InpRecoveryLotMultiplier = 1.00;

input int InpMaxGridPositions = 1;

input double InpMinEquityForTrading = 100.0;

input bool InpRiskThrottleOnDD = true;

input double InpHalfRiskAtDDPercent = 3.0;

input bool InpCapitalProtectionMode = true;

input double InpDailyProfitTargetPercent = 4.20;

input int InpMaxConsecutiveLossBaskets = 2;

input int InpConsecutiveLossCooldownMin = 1440;

input double InpMinFreeMarginAfterTradePct = 65.0;

input bool InpUseDynamicScoreThreshold = true;

input double InpDDScorePenaltyAtPercent = 3.0;

//-------------------- Grid / basket --------------------

input bool InpUseGrid = false;

input double InpGridStepATR = 2.80;

input double InpGridStepExpansion = 1.45;

input bool InpAddGridOnlyIfTrendValid = true;

input double InpMaxBasketLossBeforeGridPct = 1.50;

input double InpBasketTakeProfitATR = 0.95;

input double InpBasketTPCompression = 0.10;

input double InpEmergencyStopATR = 3.80;

input bool InpCloseBasketOnOpposite = true;

input double InpOppositeScoreToClose = 72.0;

//-------------------- Exit management --------------------

input bool InpUseBreakEven = true;

input double InpBreakEvenStartATR = 0.55;

input double InpBreakEvenLockATR = 0.12;

input bool InpUseTrailing = true;

input double InpTrailStartATR = 1.15;

input double InpTrailDistanceATR = 0.72;

input bool InpUsePartialClose = false;

input double InpPartialCloseAtATR = 0.85;

input double InpPartialClosePercent = 40.0;

input bool InpUseBasketProfitLock = true;

input double InpBasketMinLockProfitPct = 0.55;

input double InpBasketLockRetainPct = 34.0;

input int InpMaxBasketMinutes = 480;

input bool InpCloseStaleBasketIfProfit = true;

input bool InpCloseStaleLossBasket = true;

input int InpMaxLosingBasketMinutes = 360;

input double InpMaxStaleBasketLossPct = 0.65;

//-------------------- Indicators --------------------

input int InpFastEMA = 34;

input int InpSlowEMA = 144;

input int InpMacroEMA = 200;

input int InpSignalEMA = 50;

input int InpRSIPeriod = 14;

input int InpADXPeriod = 14;

input int InpATRPeriod = 14;

input int InpBandsPeriod = 20;

input double InpBandsDeviation = 2.0;

input int InpStructureLookback = 36;

input int InpEfficiencyLookback = 24;

//-------------------- Filters --------------------

input double InpMinScoreToEnter = 95.0;

input double InpMinScoreGap = 24.0;

input double InpMinADX = 20.0;

input double InpMaxADX = 48.0;

input double InpMinATRPct = 0.045;

input double InpMaxATRPct = 0.500;

input double InpMinRangeEfficiency = 0.28;

input double InpMaxSpreadPoints = 28.0;

input int InpMinMinutesBetweenEntries = 120;

input int InpMaxNewEntriesPerDay = 5;

input bool InpRequireMacroAlignment = true;

input bool InpAvoidDoji = true;

input double InpMinCandleBodyATR = 0.09;

input bool InpUseVWAPFilter = true;

input bool InpUseSMCStructureScore = true;

input double InpMaxDistanceFromSignalEMA_ATR = 2.65;

input bool InpRejectLargeWickAgainstTrade = true;

input double InpMaxOppositeWickATR = 0.90;

input int InpTradeDirectionMode = 0; // 0 both, 1 buy only, -1 sell only.

//-------------------- V9 quality filters --------------------

input bool InpUseVolatilityShockFilter = true;

input double InpMaxCandleRangeATR = 2.20;

input double InpMaxGapATR = 0.70;

input bool InpUseTrendSlopeFilter = true;

input int InpSlopeLookbackBars = 4;

input double InpMinEMASlopeATR = 0.055;

input bool InpUseConsecutiveCloseFilter = true;

input int InpConfirmBars = 2;

input bool InpUseAdaptiveGridStop = true;

input double InpMaxProjectedBasketLossPct = 1.00;

input double InpBasketCashStopPct = 0.95;

input bool InpUseEquityCurvePause = true;

input double InpSoftDDPausePercent = 3.00;

input int InpSoftDDPauseMinutes = 720;

//-------------------- V9 quality filters --------------------

input bool InpUseATRAccelerationFilter = true;

input int InpATRAccelerationLookback = 12;

input double InpMaxATRAccelerationRatio = 1.65;

input bool InpUseSessionQualityFilter = true;

input bool InpBlockAsianSession = true;

input int InpAsianEndHourServer = 7;

input int InpLondonStartHourServer = 8;

input int InpLondonEndHourServer = 12;

input int InpNYStartHourServer = 13;

input int InpNYEndHourServer = 17;

input bool InpUseSpreadSpikeFilter = true;

input double InpMaxSpreadSpikeMultiplier = 1.85;

input double InpSpreadEmaAlpha = 0.08;

input bool InpCloseAtDailyProfitTarget = true;

input bool InpUseHardBasketTimeStop = true;

input int InpHardMaxBasketMinutes = 720;

input double InpHardTimeStopLossPct = 0.35;

input bool InpUseSignalDecayExit = true;

input double InpWeakSameDirectionScore = 52.0;

input bool InpVerboseDecisionLog = true;

//-------------------- V9 sentinel engine --------------------

input int InpStrategyProfile = 1; // 0 hybrid grid, 1 sniper one-shot, 2 conservative grid.

input bool InpUseDailyEquityTrail = true;

input double InpDailyEquityTrailStartPct = 1.40;

input double InpDailyEquityTrailRetainPct = 55.0;

input bool InpUseBasketTimeProfitExit = true;

input int InpBasketTimeProfitMinutes = 240;

input double InpMinTimedExitProfitPct = 0.03;

input bool InpUseScoreDivergenceExit = true;

input double InpScoreDivergenceCloseGap = 18.0;

input bool InpUseLiquidityDistanceFilter = true;

input double InpMinDistanceFromExtremeATR = 0.22;

input bool InpUseATRNormalizedSpread = true;

input double InpMaxSpreadATRPercent = 8.0;

input bool InpUseEntryScoreDecayBlock = true;

input double InpMinSameDirectionScoreForGrid = 64.0;

input bool InpUseCSVJournal = false;

input string InpCSVJournalName = "QQ_XAU_V17_10K_PROFITASYMMETRY_journal.csv";

//-------------------- V13 high-profit 10K refinements --------------------

input bool InpUseBasketNetBreakEvenLock = true;

input double InpBasketNetBEStartATR = 0.72;

input double InpBasketNetBELockATR = 0.18;

input bool InpUseRunnerScaleOut = true;

input double InpRunnerScaleOutAtATR = 3.20;

input int InpRunnerScaleOutMinPositions = 3;

input bool InpUseRunnerTimeoutOnlyIfWeak = true;

input double InpRunnerTimeoutWeakScoreBuffer = 7.0;

input bool InpUseHighConvictionReentry = true;

input double InpReentryAfterWinScore = 99.0;

input int InpMinMinutesAfterWinReentry = 45;

//-------------------- V14 apex-runner refinements --------------------

input bool InpUseV14ConvictionGate = true;

input double InpV14MinEntryScore = 96.0;

input double InpV14MinEntryGap = 26.0;

input bool InpV14RequireAlphaOrExplosive = true;

input bool InpUseV14ShockPause = true;

input double InpV14ShockCandleRangeATR = 2.40;

input double InpV14ShockGapATR = 0.62;

input double InpV14ShockATRAcceleration = 1.62;

input int InpV14ShockPauseMinutes = 120;

input bool InpUseV14AddQualityGate = true;

input double InpV14MinAddEfficiency = 0.58;

input double InpV14MinAddScoreGap = 28.0;

input bool InpV14NoAddAfterScaleOut = true;

input bool InpUseV14RunnerMFEGuard = true;

input double InpV14RunnerMFEGuardStartPct = 0.90;

input double InpV14RunnerMFERetainPct = 32.0;

input bool InpV14RunnerMFEHoldIfExplosive = true;

//-------------------- V15 elite-profit refinements --------------------

input bool InpUseV15EliteProfitGate = true;

input double InpV15MinEntryScore = 97.0;

input double InpV15MinEntryGap = 28.0;

input double InpV15MinADX = 31.0;

input double InpV15MinEfficiency = 0.52;

input double InpV15MinBodyATR = 0.18;

input double InpV15MinSlopeATR = 0.105;

input double InpV15MaxHealthyATRAcceleration = 1.50;

input double InpV15MaxEMAExtensionATR = 2.65;

input bool InpV15RequireEliteTrend = true;

input bool InpV15UseMomentumScoreBoost = true;

input bool InpV15UseProfitStaircase = true;

input double InpV15StaircaseStartPct = 1.10;

input double InpV15StaircaseRetainPct = 36.0;

input bool InpV15HoldExceptionalRunner = true;

input double InpV15RunnerHoldScore = 99.0;

input double InpV15RunnerHoldADX = 38.0;

input double InpV15RunnerHoldEfficiency = 0.62;

input bool InpV15UseProfitCeilingClose = true;

input double InpV15AbsoluteProfitClosePct = 11.00;

input bool InpV15BlockWeakAddAfterWin = true;

input double InpV15MinAddBasketProfitPct = 0.55;

input double InpV15MinAddDistanceATR = 1.20;

//-------------------- V16 apex-compound profitability refinements --------------------

input bool InpUseV16ApexCompoundEngine = true;

input double InpV16MinEntryScore = 96.8;

input double InpV16MinEntryGap = 27.0;

input double InpV16MinADX = 29.0;

input double InpV16MinEfficiency = 0.50;

input double InpV16MinSlopeATR = 0.095;

input double InpV16MinBodyATR = 0.16;

input double InpV16MaxATRAcceleration = 1.56;

input double InpV16MaxEMAExtensionATR = 2.70;

input double InpV16MinSessionQuality = 1.0;

input bool InpV16RequireConfirmedClose = true;

input bool InpV16RequireApexTrend = true;

input bool InpV16UseScoreBoost = true;

input double InpV16ApexRunnerScore = 99.0;

input double InpV16ApexRunnerADX = 42.0;

input double InpV16ApexRunnerEfficiency = 0.66;

input double InpV16ApexTargetATR = 18.0;

input bool InpV16UseApexHighWaterLock = true;

input double InpV16HighWaterStartPct = 1.25;

input double InpV16HighWaterRetainPct = 36.0;

input double InpV16ApexHoldRetainPct = 24.0;

input bool InpV16UseBadEntryScratch = true;

input int InpV16ScratchMinutes = 30;

input double InpV16ScratchLossATR = 0.32;

input double InpV16ScratchOppositeGap = 8.0;

input bool InpV16UseApexAddGate = true;

input double InpV16MinAddScore = 99.0;

input double InpV16MinAddGap = 32.0;

input double InpV16MinAddBasketPct = 0.55;

input double InpV16MinAddDistanceATR = 1.15;

input int InpV16MaxPositions = 4;

input bool InpV16BlockAddIfProfitRetracing = true;

input double InpV16AddMaxRetracePct = 35.0;

//-------------------- V17 profit-asymmetry refinements --------------------

input bool InpUseV17ProfitAsymmetry = true;

input double InpV17CoreScore = 96.5;

input double InpV17ApexScore = 99.0;

input double InpV17MinGap = 26.0;

input double InpV17MinADX = 28.0;

input double InpV17MinEfficiency = 0.49;

input double InpV17MinSlopeATR = 0.088;

input double InpV17MaxATRAcceleration = 1.58;

input double InpV17MaxEMAExtensionATR = 2.85;

input double InpV17MinBodyATR = 0.14;

input bool InpV17AllowCleanContinuation = true;

input bool InpV17BlockThreeBarReversal = true;

input double InpV17ReversalWickATR = 0.72;

input bool InpV17UseFailedMomentumCut = true;

input int InpV17FailedMoveMinutes = 180;

input double InpV17FailedMoveMinMFE_ATR = 0.42;

input double InpV17FailedMoveLossATR = 0.22;

input bool InpV17UseRunnerProfitElasticity = true;

input double InpV17ElasticLockStartPct = 0.95;

input double InpV17ElasticRetainNormalPct = 44.0;

input double InpV17ElasticRetainApexPct = 26.0;

input double InpV17AbsoluteProfitCeilingPct = 16.0;

input bool InpV17UseProfitReacceleration = true;

input double InpV17ReaccelerationScore = 98.5;

input double InpV17ReaccelerationADX = 36.0;

input double InpV17ReaccelerationEfficiency = 0.58;

input double InpV17AddMinBasketPct = 0.48;

input double InpV17AddMinDistanceATR = 1.05;

//-------------------- V9 max-profit engine --------------------

input bool InpUseProfitExpansion = true;

input bool InpUseRunnerMode = true;

input bool InpUseDynamicTP = true;

input double InpStrongTrendTPATR = 3.10;

input double InpStrongTrendADX = 28.0;

input double InpStrongTrendEfficiency = 0.42;

input double InpStrongTrendScore = 94.0;

input double InpExpansionTriggerATR = 1.55;

input double InpExpansionTrailATR = 1.30;

input bool InpUseAddToWinner = true;

input int InpMaxWinnerAdds = 3;

input double InpWinnerAddStepATR = 1.10;

input double InpWinnerAddLotMultiplier = 1.00;

input double InpMinScoreForWinnerAdd = 98.0;

input int InpMinMinutesBetweenWinnerAdds = 90;

input bool InpRequireProtectedSLForAdd = true;

input bool InpUseProfitTargetExtension = true;

input double InpProfitTargetExtensionScore = 96.0;

input double InpMaxRunnerMinutes = 960;

input bool InpCloseRunnerOnSessionEnd = false;

//-------------------- V10 hyper-profit engine --------------------

input bool InpUseAsymmetricProfitEngine = true;

input bool InpUseFastLoserCut = true;

input int InpFastLoserCutMinutes = 90;

input double InpFastLoserCutATR = 0.82;

input double InpFastLoserMinSameScore = 58.0;

input double InpFastLoserOppositeGap = 10.0;

input bool InpUseHyperRunnerTP = true;

input double InpMegaTrendScore = 97.0;

input double InpMegaTrendADX = 34.0;

input double InpMegaTrendEfficiency = 0.52;

input double InpMegaTrendTPATR = 5.20;

input double InpHyperTrendTPATR = 7.40;

input double InpRunnerStretchStartATR = 2.00;

input double InpRunnerMaxTrailATR = 2.80;

input bool InpUseLockedProfitPyramid = true;

input int InpMaxPyramidAdds = 3;

input double InpPyramidMinBasketProfitPct = 0.42;

input double InpPyramidStepATR = 1.15;

input double InpPyramidLotDecay = 1.00;

input double InpPyramidMinSameScore = 98.0;

input bool InpUseDailyProfitUnlock = true;

input double InpDailyProfitUnlockAtPct = 1.25;

input double InpUnlockedMaxDailyProfitPct = 8.00;

input bool InpUseEquitySnowballLimit = true;

input double InpSnowballRiskBoostAtProfitPct = 1.25;

input double InpSnowballRiskMultiplier = 1.00;

input double InpAbsoluteMaxBasketProfitPct = 15.00;

input bool InpCloseOnRunnerExhaustion = true;

input double InpRunnerExhaustionScoreDrop = 16.0;

//-------------------- V13 alpha-harvest engine --------------------

input bool InpUseAlphaHarvestEngine = true;

input bool InpUseTrendConvictionBonus = true;

input double InpAlphaMinADX = 30.0;

input double InpAlphaMinEfficiency = 0.48;

input double InpAlphaMinSlopeATR = 0.090;

input double InpAlphaMinScoreGap = 22.0;

input bool InpUseExplosiveRunnerTarget = true;

input double InpExplosiveTrendScore = 99.0;

input double InpExplosiveTrendADX = 40.0;

input double InpExplosiveTrendEfficiency = 0.62;

input double InpExplosiveTrendTPATR = 18.00;

input bool InpUseAdaptiveRunnerTrail = true;

input double InpAlphaTrailTightenDrop = 9.0;

input double InpAlphaTrailWidenScore = 98.0;

input double InpAlphaMaxTrailATR = 4.20;

input bool InpUseEarlyBadTradeAbort = true;

input int InpEarlyAbortMinutes = 45;

input double InpEarlyAbortLossATR = 0.48;

input double InpEarlyAbortMaxSameScore = 62.0;

input bool InpUseTrendVault = true;

input double InpTrendVaultStartPct = 3.20;

input double InpTrendVaultRetainPct = 55.0;

input bool InpUsePullbackPyramid = true;

input double InpPullbackPyramidMaxEMA_ATR = 0.85;

input double InpPullbackPyramidMinScore = 98.0;

input bool InpUseProfitOnlyAdds = true;

input double InpMinBasketProfitForAnyAddPct = 0.42;

input bool InpUseAmbiguityPenalty = true;

input double InpAmbiguousBothScoreLevel = 82.0;

input double InpAmbiguityMinGap = 18.0;

input bool InpUseWeeklyProtection = true;

input double InpWeeklyLossStopPct = 3.00;

input double InpWeeklyProfitVaultPct = 7.50;

input double InpWeeklyProfitRetainPct = 48.0;

//-------------------- Account protection --------------------

input double InpMaxDailyLossPercent = 1.20;

input double InpMaxEquityDDPercent = 4.8;

input double InpHardStopEquityDDPercent = 6.8;

input bool InpCloseAllOnHardDD = true;

input int InpCooldownAfterLossMinutes = 720;

input int InpCooldownAfterDDMinutes = 1440;

//-------------------- Sessions --------------------

input int InpStartHourServer = 2;

input int InpEndHourServer = 21;

input bool InpTradeMonday = true;

input bool InpTradeTuesday = true;

input bool InpTradeWednesday = true;

input bool InpTradeThursday = true;

input bool InpTradeFriday = true;

input bool InpBlockFridayLate = true;

input int InpFridayStopHourServer = 16;

input bool InpCloseWeekendRisk = true;

input int InpWeekendFlatHourServer = 15;

// Manual blackout: "2026.06.18 14:00-2026.06.18 15:30;2026.06.19 13:00-2026.06.19 14:00"

input bool InpUseManualNewsBlackout = false;

input string InpNewsBlackoutWindows = "";

//-------------------- Execution / dashboard --------------------

input int InpDeviationPoints = 30;

input bool InpShowDashboard = true;

input bool InpVerboseLog = false;

//-------------------- Handles --------------------

int hFast = INVALID_HANDLE;

int hSlow = INVALID_HANDLE;

int hMacro = INVALID_HANDLE;

int hSignalEMA = INVALID_HANDLE;

int hRSI = INVALID_HANDLE;

int hADX = INVALID_HANDLE;

int hATR = INVALID_HANDLE;

int hBands = INVALID_HANDLE;

//-------------------- State --------------------

datetime g_lastBar = 0;

datetime g_lastEntry = 0;

datetime g_dayStart = 0;

datetime g_weekStart = 0;

datetime g_cooldownUntil = 0;

double g_dayStartEquity = 0.0;

double g_weekStartEquity = 0.0;

double g_weekPeakEquity = 0.0;

double g_dayPeakEquity = 0.0;

double g_peakEquity = 0.0;

double g_basketPeakProfit = 0.0;

int g_entriesToday = 0;

bool g_partialDone = false;

int g_consecutiveLossBaskets = 0;

datetime g_lastBasketClose = 0;

bool g_lastBasketWasProfit = false;

datetime g_lastWinnerAdd = 0;

datetime g_v14ShockPauseUntil = 0;

double g_runnerBestScore = 0.0;

double g_runnerBestDistanceATR = 0.0;

double g_v17BasketMFEATR = 0.0;

double g_spreadEma = 0.0;

datetime g_lastDecisionLog = 0;

string g_status = "INIT";

//-------------------- Types --------------------

struct SignalPack

{

int direction;

double buyScore;

double sellScore;

double atr;

double adx;

double atrPct;

double efficiency;

double vwap;

double distanceFromSignalEMAATR;

double bodyATR;

double candleRangeATR;

double gapATR;

double emaSlopeATR;

double atrAcceleration;

int sessionQuality;

bool buyConfirmed;

bool sellConfirmed;

double oppositeWickATRBuy;

double oppositeWickATRSell;

double distanceToRecentHighATR;

double distanceToRecentLowATR;

double scoreGap;

string regime;

string reason;

};

//-------------------- Forward declarations --------------------

void ResetWeekIfNeeded();

double WeeklyLossPct();

double WeeklyProfitPct();

double WeeklyPeakProfitPct();

//-------------------- Helpers --------------------

bool SymbolOK()

{

return (_Symbol == InpTradeSymbol || StringFind(_Symbol, InpTradeSymbol) >= 0);

}

double Ask()

{

return SymbolInfoDouble(_Symbol, SYMBOL_ASK);

}

double Bid()

{

return SymbolInfoDouble(_Symbol, SYMBOL_BID);

}

double SpreadPts()

{

double ask = Ask();

double bid = Bid();

if(ask <= 0 || bid <= 0 || _Point <= 0) return 999999.0;

return (ask - bid) / _Point;

}

double NormPrice(const double p)

{

return NormalizeDouble(p, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

}

double NormalizeLot(double lot)

{

double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

if(step <= 0) step = 0.01;

lot = MathMax(minLot, MathMin(maxLot, lot));

lot = MathFloor(lot / step) * step;

return NormalizeDouble(lot, 2);

}

double EffectiveMaxTotalLots()

{

if(InpForceTenKLotBand)

return MathMin(InpMaxTotalLots, InpMaxAllowedTotalLots);

return InpMaxTotalLots;

}

double ApplyTenKLotBand(const double rawLot)

{

double lot = rawLot;

if(InpForceTenKLotBand)

lot = MathMax(InpMinAllowedLot, MathMin(InpMaxAllowedSingleLot, lot));

return NormalizeLot(lot);

}

bool CopyVal(const int handle, const int buffer, const int shift, double &v)

{

double a[1];

ArraySetAsSeries(a, true);

if(CopyBuffer(handle, buffer, shift, 1, a) != 1) return false;

v = a[0];

return true;

}

bool CloseVal(const ENUM_TIMEFRAMES tf, const int shift, double &v)

{

double a[1];

ArraySetAsSeries(a, true);

if(CopyClose(_Symbol, tf, shift, 1, a) != 1) return false;

v = a[0];

return true;

}

bool OpenVal(const ENUM_TIMEFRAMES tf, const int shift, double &v)

{

double a[1];

ArraySetAsSeries(a, true);

if(CopyOpen(_Symbol, tf, shift, 1, a) != 1) return false;

v = a[0];

return true;

}

bool HighVal(const ENUM_TIMEFRAMES tf, const int shift, double &v)

{

double a[1];

ArraySetAsSeries(a, true);

if(CopyHigh(_Symbol, tf, shift, 1, a) != 1) return false;

v = a[0];

return true;

}

bool LowVal(const ENUM_TIMEFRAMES tf, const int shift, double &v)

{

double a[1];

ArraySetAsSeries(a, true);

if(CopyLow(_Symbol, tf, shift, 1, a) != 1) return false;

v = a[0];

return true;

}

bool NewBar()

{

datetime t = iTime(_Symbol, InpSignalTF, 0);

if(t <= 0) return false;

if(t != g_lastBar)

{

g_lastBar = t;

return true;

}

return false;

}

void Log(const string msg)

{

if(InpVerboseLog) Print("QQ_V14 | ", msg);

}

void JournalEvent(const string eventName, const string detail)

{

if(!InpUseCSVJournal) return;

int flags = FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON;

int h = FileOpen(InpCSVJournalName, flags, ';');

if(h == INVALID_HANDLE) return;

bool empty = (FileSize(h) == 0);

FileSeek(h, 0, SEEK_END);

if(empty)

FileWrite(h, "time", "symbol", "event", "detail", "equity", "balance", "positions", "basket_profit", "daily_loss_pct", "peak_dd_pct", "spread_pts");

FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), _Symbol, eventName, detail,

DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),

DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),

IntegerToString(CountPositions()),

DoubleToString(BasketProfit(), 2),

DoubleToString(DailyLossPct(), 2),

DoubleToString(PeakDDPct(), 2),

DoubleToString(SpreadPts(), 1));

FileClose(h);

}

void ResetDayIfNeeded()

{

MqlDateTime nowStruct;

MqlDateTime dayStruct;

TimeToStruct(TimeCurrent(), nowStruct);

if(g_dayStart > 0) TimeToStruct(g_dayStart, dayStruct);

if(g_dayStart == 0 || nowStruct.day != dayStruct.day || nowStruct.mon != dayStruct.mon || nowStruct.year != dayStruct.year)

{

g_dayStart = TimeCurrent();

g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

g_dayPeakEquity = g_dayStartEquity;

g_entriesToday = 0;

}

double eq = AccountInfoDouble(ACCOUNT_EQUITY);

if(g_peakEquity <= 0.0 || eq > g_peakEquity) g_peakEquity = eq;

if(g_dayPeakEquity <= 0.0 || eq > g_dayPeakEquity) g_dayPeakEquity = eq;

ResetWeekIfNeeded();

}

double DailyLossPct()

{

if(g_dayStartEquity <= 0.0) return 0.0;

double loss = (g_dayStartEquity - AccountInfoDouble(ACCOUNT_EQUITY)) / g_dayStartEquity * 100.0;

return MathMax(0.0, loss);

}

double DailyProfitPct()

{

if(g_dayStartEquity <= 0.0) return 0.0;

double profit = (AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartEquity) / g_dayStartEquity * 100.0;

return MathMax(0.0, profit);

}

double DailyPeakProfitPct()

{

if(g_dayStartEquity <= 0.0 || g_dayPeakEquity <= 0.0) return 0.0;

double profit = (g_dayPeakEquity - g_dayStartEquity) / g_dayStartEquity * 100.0;

return MathMax(0.0, profit);

}

datetime WeekAnchor(datetime when)

{

MqlDateTime t;

TimeToStruct(when, t);

t.hour = 0;

t.min = 0;

t.sec = 0;

datetime d = StructToTime(t);

int dow = t.day_of_week;

int offset = (dow == 0 ? 6 : dow - 1); // Monday anchor.

return d - offset * 86400;

}

void ResetWeekIfNeeded()

{

if(!InpUseWeeklyProtection) return;

datetime anchor = WeekAnchor(TimeCurrent());

if(g_weekStart == 0 || anchor != g_weekStart)

{

g_weekStart = anchor;

g_weekStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

g_weekPeakEquity = g_weekStartEquity;

}

double eq = AccountInfoDouble(ACCOUNT_EQUITY);

if(g_weekPeakEquity <= 0.0 || eq > g_weekPeakEquity) g_weekPeakEquity = eq;

}

double WeeklyLossPct()

{

if(g_weekStartEquity <= 0.0) return 0.0;

double loss = (g_weekStartEquity - AccountInfoDouble(ACCOUNT_EQUITY)) / g_weekStartEquity * 100.0;

return MathMax(0.0, loss);

}

double WeeklyProfitPct()

{

if(g_weekStartEquity <= 0.0) return 0.0;

double profit = (AccountInfoDouble(ACCOUNT_EQUITY) - g_weekStartEquity) / g_weekStartEquity * 100.0;

return MathMax(0.0, profit);

}

double WeeklyPeakProfitPct()

{

if(g_weekStartEquity <= 0.0 || g_weekPeakEquity <= 0.0) return 0.0;

double profit = (g_weekPeakEquity - g_weekStartEquity) / g_weekStartEquity * 100.0;

return MathMax(0.0, profit);

}

bool ATRNormalizedSpreadOK(const double atr)

{

if(!InpUseATRNormalizedSpread) return true;

if(atr <= 0.0) return false;

double spreadPctOfATR = (SpreadPts() * _Point) / atr * 100.0;

return (spreadPctOfATR <= InpMaxSpreadATRPercent);

}

bool WeekendFlatTime()

{

MqlDateTime t;

TimeToStruct(TimeCurrent(), t);

return (t.day_of_week == 5 && InpCloseWeekendRisk && t.hour >= InpWeekendFlatHourServer);

}

double DynamicMinScore()

{

double threshold = InpMinScoreToEnter;

if(!InpUseDynamicScoreThreshold) return threshold;

double dd = PeakDDPct();

double dl = DailyLossPct();

if(dd >= InpDDScorePenaltyAtPercent) threshold += 4.0;

if(InpStrategyProfile == 1) threshold += 2.0;

if(dl >= InpMaxDailyLossPercent * 0.50) threshold += 4.0;

if(g_consecutiveLossBaskets > 0) threshold += 3.0 * g_consecutiveLossBaskets;

if(SpreadPts() > InpMaxSpreadPoints * 0.70) threshold += 2.0;

if(InpUseDailyProfitUnlock && DailyProfitPct() >= InpDailyProfitUnlockAtPct && PeakDDPct() < InpHalfRiskAtDDPercent)

threshold = MathMax(InpMinScoreToEnter, threshold - 2.0);

if(InpUseAlphaHarvestEngine && InpUseAmbiguityPenalty && g_consecutiveLossBaskets > 0) threshold += 2.0;

if(InpUseWeeklyProtection && WeeklyLossPct() >= InpWeeklyLossStopPct * 0.50) threshold += 5.0;

if(WeekendFlatTime()) threshold = 101.0;

return MathMin(101.0, threshold);

}

double PeakDDPct()

{

if(g_peakEquity <= 0.0) return 0.0;

double dd = (g_peakEquity - AccountInfoDouble(ACCOUNT_EQUITY)) / g_peakEquity * 100.0;

return MathMax(0.0, dd);

}

double BasketLossPct()

{

double eq = AccountInfoDouble(ACCOUNT_EQUITY);

if(eq <= 0.0) return 0.0;

double p = BasketProfit();

if(p >= 0.0) return 0.0;

return MathAbs(p) / eq * 100.0;

}

double ProjectedBasketLossPct(const int dir, const double lot, const double atr)

{

double eq = AccountInfoDouble(ACCOUNT_EQUITY);

if(eq <= 0.0 || lot <= 0.0 || atr <= 0.0) return 999.0;

double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

if(tickSize <= 0.0 || tickValue <= 0.0) return 999.0;

double adverseDistance = atr * InpEmergencyStopATR;

double addedRiskMoney = (adverseDistance / tickSize) * tickValue * lot;

double currentLossMoney = MathMax(0.0, -BasketProfit());

return (currentLossMoney + addedRiskMoney) / eq * 100.0;

}

bool TradeDirectionAllowed(const int dir)

{

if(InpTradeDirectionMode == 1 && dir == -1) return false;

if(InpTradeDirectionMode == -1 && dir == 1) return false;

return true;

}

bool DayAllowed()

{

MqlDateTime t;

TimeToStruct(TimeCurrent(), t);

if(t.day_of_week == 1 && !InpTradeMonday) return false;

if(t.day_of_week == 2 && !InpTradeTuesday) return false;

if(t.day_of_week == 3 && !InpTradeWednesday) return false;

if(t.day_of_week == 4 && !InpTradeThursday) return false;

if(t.day_of_week == 5 && !InpTradeFriday) return false;

if(t.day_of_week == 5 && InpBlockFridayLate && t.hour >= InpFridayStopHourServer) return false;

return true;

}

bool SessionOK()

{

MqlDateTime t;

TimeToStruct(TimeCurrent(), t);

if(!DayAllowed()) return false;

if(t.hour < InpStartHourServer || t.hour >= InpEndHourServer) return false;

return true;

}

int SessionQuality()

{

if(!DayAllowed()) return 0;

MqlDateTime t;

TimeToStruct(TimeCurrent(), t);

if(t.hour < InpStartHourServer || t.hour >= InpEndHourServer) return 0;

if(t.day_of_week == 5 && InpBlockFridayLate && t.hour >= InpFridayStopHourServer) return 0;

bool london = (t.hour >= InpLondonStartHourServer && t.hour < InpLondonEndHourServer);

bool ny = (t.hour >= InpNYStartHourServer && t.hour < InpNYEndHourServer);

bool asian = (t.hour < InpAsianEndHourServer);

if(InpBlockAsianSession && asian) return 0;

if(london || ny) return 3;

return 1;

}

void UpdateSpreadEma()

{

double sp = SpreadPts();

if(sp <= 0.0 || sp > 100000.0) return;

double alpha = MathMax(0.01, MathMin(1.0, InpSpreadEmaAlpha));

if(g_spreadEma <= 0.0) g_spreadEma = sp;

else g_spreadEma = alpha * sp + (1.0 - alpha) * g_spreadEma;

}

bool SpreadSpikeOK()

{

if(!InpUseSpreadSpikeFilter) return true;

double sp = SpreadPts();

if(sp <= 0.0 || sp > InpMaxSpreadPoints) return false;

if(g_spreadEma <= 0.0) return true;

return (sp <= g_spreadEma * InpMaxSpreadSpikeMultiplier);

}

void DecisionLog(const string msg)

{

if(!InpVerboseDecisionLog) return;

datetime now = TimeCurrent();

if(now - g_lastDecisionLog < 60) return;

g_lastDecisionLog = now;

Print("QQ_V14 | ", msg);

JournalEvent("DECISION", msg);

}

bool InManualBlackout()

{

if(!InpUseManualNewsBlackout || StringLen(InpNewsBlackoutWindows) < 10) return false;

string parts[];

int n = StringSplit(InpNewsBlackoutWindows, ';', parts);

datetime now = TimeCurrent();

for(int i = 0; i < n; i++)

{

string w = parts[i];

StringTrimLeft(w);

StringTrimRight(w);

string lr[];

if(StringSplit(w, '-', lr) != 2) continue;

StringTrimLeft(lr[0]);

StringTrimRight(lr[0]);

StringTrimLeft(lr[1]);

StringTrimRight(lr[1]);

datetime a = StringToTime(lr[0]);

datetime b = StringToTime(lr[1]);

if(a > 0 && b > 0 && now >= a && now <= b) return true;

}

return false;

}

int CountPositions(const int dir = 0)

{

int c = 0;

for(int i = PositionsTotal() - 1; i >= 0; i--)

{

ulong tk = PositionGetTicket(i);

if(!PositionSelectByTicket(tk)) continue;

if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

long type = PositionGetInteger(POSITION_TYPE);

if(dir == 1 && type != POSITION_TYPE_BUY) continue;

if(dir == -1 && type != POSITION_TYPE_SELL) continue;

c++;

}

return c;

}

double TotalLots()

{

double s = 0.0;

for(int i = PositionsTotal() - 1; i >= 0; i--)

{

ulong tk = PositionGetTicket(i);

if(!PositionSelectByTicket(tk)) continue;

if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

s += PositionGetDouble(POSITION_VOLUME);

}

return s;

}

double BasketProfit()

{

double p = 0.0;

for(int i = PositionsTotal() - 1; i >= 0; i--)

{

ulong tk = PositionGetTicket(i);

if(!PositionSelectByTicket(tk)) continue;

if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

p += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

}

return p;

}

int BasketDirection()

{

int b = CountPositions(1);

int s = CountPositions(-1);

if(b > s) return 1;

if(s > b) return -1;

return 0;

}

datetime BasketOldestTime()

{

datetime oldest = 0;

for(int i = PositionsTotal() - 1; i >= 0; i--)

{

ulong tk = PositionGetTicket(i);

if(!PositionSelectByTicket(tk)) continue;

if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

datetime t = (datetime)PositionGetInteger(POSITION_TIME);

if(oldest == 0 || t < oldest) oldest = t;

}

return oldest;

}

double WeightedEntry(const int dir)

{

double pv = 0.0;

double lv = 0.0;

for(int i = PositionsTotal() - 1; i >= 0; i--)

{

ulong tk = PositionGetTicket(i);

if(!PositionSelectByTicket(tk)) continue;

if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

long type = PositionGetInteger(POSITION_TYPE);

if(dir == 1 && type != POSITION_TYPE_BUY) continue;

if(dir == -1 && type != POSITION_TYPE_SELL) continue;

double lot = PositionGetDouble(POSITION_VOLUME);

pv += PositionGetDouble(POSITION_PRICE_OPEN) * lot;

lv += lot;

}

if(lv <= 0.0) return 0.0;

return pv / lv;

}

double LastEntryPrice(const int dir)

{

datetime best = 0;

double price = 0.0;

for(int i = PositionsTotal() - 1; i >= 0; i--)

{

ulong tk = PositionGetTicket(i);

if(!PositionSelectByTicket(tk)) continue;

if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

long type = PositionGetInteger(POSITION_TYPE);

if(dir == 1 && type != POSITION_TYPE_BUY) continue;

if(dir == -1 && type != POSITION_TYPE_SELL) continue;

datetime t = (datetime)PositionGetInteger(POSITION_TIME);

if(t >= best)

{

best = t;

price = PositionGetDouble(POSITION_PRICE_OPEN);

}

}

return price;

}

bool CloseAll()

{

int before = CountPositions();

double profitBefore = BasketProfit();

bool ok = true;

for(int i = PositionsTotal() - 1; i >= 0; i--)

{

ulong tk = PositionGetTicket(i);

if(!PositionSelectByTicket(tk)) continue;

if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

if(!trade.PositionClose(tk)) ok = false;

}

if(ok && before > 0)

{

g_lastBasketClose = TimeCurrent();

if(profitBefore < 0.0)

{

g_lastBasketWasProfit = false;

g_consecutiveLossBaskets++;

if(g_consecutiveLossBaskets >= InpMaxConsecutiveLossBaskets)

g_cooldownUntil = TimeCurrent() + InpConsecutiveLossCooldownMin * 60;

}

else if(profitBefore > 0.0)

{

g_lastBasketWasProfit = true;

g_consecutiveLossBaskets = 0;

}

else

{

g_lastBasketWasProfit = false;

}

}

return ok;

}

double DayVWAP()

{

MqlDateTime t;

TimeToStruct(TimeCurrent(), t);

t.hour = 0;

t.min = 0;

t.sec = 0;

datetime start = StructToTime(t);

MqlRates rates[];

int copied = CopyRates(_Symbol, InpSignalTF, start, TimeCurrent(), rates);

if(copied <= 0) return 0.0;

double pv = 0.0;

double vol = 0.0;

for(int i = 0; i < copied; i++)

{

double tp = (rates[i].high + rates[i].low + rates[i].close) / 3.0;

double v = (double)rates[i].tick_volume;

if(v <= 0.0) v = 1.0;

pv += tp * v;

vol += v;

}

if(vol <= 0.0) return 0.0;

return pv / vol;

}

double RangeEfficiency(const int lookback)

{

if(lookback < 5) return 0.0;

int hiShift = iHighest(_Symbol, InpSignalTF, MODE_HIGH, lookback, 1);

int loShift = iLowest(_Symbol, InpSignalTF, MODE_LOW, lookback, 1);

double hh = 0.0;

double ll = 0.0;

double c1 = 0.0;

double cN = 0.0;

if(hiShift < 0 || loShift < 0) return 0.0;

if(!HighVal(InpSignalTF, hiShift, hh)) return 0.0;

if(!LowVal(InpSignalTF, loShift, ll)) return 0.0;

if(!CloseVal(InpSignalTF, 1, c1)) return 0.0;

if(!CloseVal(InpSignalTF, lookback, cN)) return 0.0;

if(hh <= ll) return 0.0;

return MathAbs(c1 - cN) / (hh - ll);

}

bool RecentStructure(const int lookback, double &recentHigh, double &recentLow)

{

recentHigh = 0.0;

recentLow = 0.0;

int hiShift = iHighest(_Symbol, InpSignalTF, MODE_HIGH, lookback, 2);

int loShift = iLowest(_Symbol, InpSignalTF, MODE_LOW, lookback, 2);

if(hiShift < 0 || loShift < 0) return false;

if(!HighVal(InpSignalTF, hiShift, recentHigh)) return false;

if(!LowVal(InpSignalTF, loShift, recentLow)) return false;

return (recentHigh > 0.0 && recentLow > 0.0);

}

bool BullishFVG()

{

double low1 = 0.0;

double high3 = 0.0;

if(!LowVal(InpSignalTF, 1, low1)) return false;

if(!HighVal(InpSignalTF, 3, high3)) return false;

return (low1 > high3);

}

bool BearishFVG()

{

double high1 = 0.0;

double low3 = 0.0;

if(!HighVal(InpSignalTF, 1, high1)) return false;

if(!LowVal(InpSignalTF, 3, low3)) return false;

return (high1 < low3);

}

//-------------------- Signal model --------------------

bool BuildSignal(SignalPack &s)

{

s.direction = 0;

s.buyScore = 0.0;

s.sellScore = 0.0;

s.atr = 0.0;

s.adx = 0.0;

s.atrPct = 0.0;

s.efficiency = 0.0;

s.vwap = 0.0;

s.distanceFromSignalEMAATR = 0.0;

s.bodyATR = 0.0;

s.candleRangeATR = 0.0;

s.gapATR = 0.0;

s.emaSlopeATR = 0.0;

s.atrAcceleration = 1.0;

s.sessionQuality = 0;

s.buyConfirmed = false;

s.sellConfirmed = false;

s.oppositeWickATRBuy = 0.0;

s.oppositeWickATRSell = 0.0;

s.distanceToRecentHighATR = 999.0;

s.distanceToRecentLowATR = 999.0;

s.scoreGap = 0.0;

s.regime = "UNKNOWN";

s.reason = "";

double fast = 0.0;

double slow = 0.0;

double macro = 0.0;

double sigEma = 0.0;

double rsi = 0.0;

double adx = 0.0;

double atr = 0.0;

double atrPast = 0.0;

double upper = 0.0;

double mid = 0.0;

double lower = 0.0;

double c1 = 0.0;

double o1 = 0.0;

double c2 = 0.0;

double h1 = 0.0;

double l1 = 0.0;

double sigEmaPast = 0.0;

if(!CopyVal(hFast, 0, 1, fast)) return false;

if(!CopyVal(hSlow, 0, 1, slow)) return false;

if(!CopyVal(hMacro, 0, 1, macro)) return false;

if(!CopyVal(hSignalEMA, 0, 1, sigEma)) return false;

int slopeShift = InpSlopeLookbackBars + 1;

if(slopeShift < 2) slopeShift = 2;

if(!CopyVal(hSignalEMA, 0, slopeShift, sigEmaPast)) return false;

if(!CopyVal(hRSI, 0, 1, rsi)) return false;

if(!CopyVal(hADX, 0, 1, adx)) return false;

if(!CopyVal(hATR, 0, 1, atr)) return false;

int atrAccelShift = InpATRAccelerationLookback + 1;

if(atrAccelShift < 3) atrAccelShift = 3;

if(!CopyVal(hATR, 0, atrAccelShift, atrPast)) atrPast = atr;

// MQL5 iBands buffers: 0 = middle/base, 1 = upper, 2 = lower.

if(!CopyVal(hBands, 0, 1, mid)) return false;

if(!CopyVal(hBands, 1, 1, upper)) return false;

if(!CopyVal(hBands, 2, 1, lower)) return false;

if(!CloseVal(InpSignalTF, 1, c1)) return false;

if(!OpenVal(InpSignalTF, 1, o1)) return false;

if(!CloseVal(InpSignalTF, 2, c2)) return false;

if(!HighVal(InpSignalTF, 1, h1)) return false;

if(!LowVal(InpSignalTF, 1, l1)) return false;

if(atr <= 0.0 || c1 <= 0.0) return false;

s.atr = atr;

s.adx = adx;

s.atrPct = atr / c1 * 100.0;

s.efficiency = RangeEfficiency(InpEfficiencyLookback);

s.vwap = DayVWAP();

double body = MathAbs(c1 - o1);

double range = MathMax(h1 - l1, _Point);

double closePos = (c1 - l1) / range;

s.distanceFromSignalEMAATR = MathAbs(c1 - sigEma) / atr;

s.bodyATR = body / atr;

s.candleRangeATR = (h1 - l1) / atr;

s.gapATR = MathAbs(o1 - c2) / atr;

s.emaSlopeATR = (sigEma - sigEmaPast) / atr;

s.atrAcceleration = (atrPast > 0.0 ? atr / atrPast : 1.0);

s.sessionQuality = SessionQuality();

bool buyConfirm = true;

bool sellConfirm = true;

int confirmBars = InpConfirmBars;

if(confirmBars < 1) confirmBars = 1;

if(confirmBars > 5) confirmBars = 5;

for(int k = 1; k <= confirmBars; k++)

{

double ck = 0.0;

double ek = 0.0;

if(!CloseVal(InpSignalTF, k, ck) || !CopyVal(hSignalEMA, 0, k, ek))

{

buyConfirm = false;

sellConfirm = false;

break;

}

if(ck <= ek) buyConfirm = false;

if(ck >= ek) sellConfirm = false;

}

s.buyConfirmed = buyConfirm;

s.sellConfirmed = sellConfirm;

s.oppositeWickATRBuy = (MathMin(o1, c1) - l1) / atr;

s.oppositeWickATRSell = (h1 - MathMax(o1, c1)) / atr;

double buy = 0.0;

double sell = 0.0;

double recentHigh = 0.0;

double recentLow = 0.0;

bool hasStructure = RecentStructure(InpStructureLookback, recentHigh, recentLow);

if(hasStructure)

{

s.distanceToRecentHighATR = MathAbs(recentHigh - c1) / atr;

s.distanceToRecentLowATR = MathAbs(c1 - recentLow) / atr;

}

if(adx >= InpMinADX && adx <= InpMaxADX && s.efficiency >= InpMinRangeEfficiency)

s.regime = "TRADEABLE";

else if(s.efficiency < InpMinRangeEfficiency)

s.regime = "CHOPPY";

else if(adx > InpMaxADX)

s.regime = "OVEREXTENDED";

else

s.regime = "WEAK";

// Module 1: H1 trend.

if(fast > slow)

{

buy += 19.0;

s.reason += "H1_UP ";

}

else if(fast < slow)

{

sell += 19.0;

s.reason += "H1_DOWN ";

}

// Module 2: H4 macro bias.

if(c1 > macro) buy += 17.0;

if(c1 < macro) sell += 17.0;

// Module 3: M15 local EMA location.

if(c1 > sigEma && c1 > c2) buy += 11.0;

if(c1 < sigEma && c1 < c2) sell += 11.0;

// V9 module: EMA slope and multi-candle confirmation.

if(s.emaSlopeATR >= InpMinEMASlopeATR) buy += 8.0;

if(s.emaSlopeATR <= -InpMinEMASlopeATR) sell += 8.0;

if(InpUseTrendSlopeFilter)

{

if(s.emaSlopeATR < InpMinEMASlopeATR) buy -= 8.0;

if(s.emaSlopeATR > -InpMinEMASlopeATR) sell -= 8.0;

}

if(InpUseConsecutiveCloseFilter)

{

if(s.buyConfirmed) buy += 7.0; else buy -= 6.0;

if(s.sellConfirmed) sell += 7.0; else sell -= 6.0;

}

// Module 4: RSI impulse without buying/selling exhaustion.

if(rsi >= 52.0 && rsi <= 66.0) buy += 14.0;

if(rsi <= 48.0 && rsi >= 34.0) sell += 14.0;

if(rsi > 74.0) buy -= 9.0;

if(rsi < 26.0) sell -= 9.0;

// Module 5: Bollinger pullback or continuation.

if(c1 > lower && c1 < mid && fast > slow) buy += 9.0;

if(c1 < upper && c1 > mid && fast < slow) sell += 9.0;

if(c1 > mid && closePos >= 0.62 && fast > slow) buy += 6.0;

if(c1 < mid && closePos <= 0.38 && fast < slow) sell += 6.0;

// Module 6: SMC-style structure, liquidity sweep and imbalance approximation.

if(InpUseSMCStructureScore && hasStructure)

{

bool bullBreak = (c1 > recentHigh);

bool bearBreak = (c1 < recentLow);

bool bullSweep = (l1 < recentLow && c1 > recentLow && c1 > o1);

bool bearSweep = (h1 > recentHigh && c1 < recentHigh && c1 < o1);

if(bullBreak) buy += 12.0;

if(bearBreak) sell += 12.0;

if(bullSweep) buy += 10.0;

if(bearSweep) sell += 10.0;

if(BullishFVG()) buy += 5.0;

if(BearishFVG()) sell += 5.0;

}

// Regime quality bonus/penalty.

if(adx >= InpMinADX && adx <= InpMaxADX)

{

buy += 7.0;

sell += 7.0;

}

else

{

buy -= 14.0;

sell -= 14.0;

}

if(s.atrPct >= InpMinATRPct && s.atrPct <= InpMaxATRPct)

{

buy += 7.0;

sell += 7.0;

}

else

{

buy -= 14.0;

sell -= 14.0;

}

if(s.efficiency >= InpMinRangeEfficiency)

{

buy += 5.0;

sell += 5.0;

}

else

{

buy -= 12.0;

sell -= 12.0;

}

// VWAP filter.

if(InpUseVWAPFilter && s.vwap > 0.0)

{

if(c1 > s.vwap) buy += 5.0;

if(c1 < s.vwap) sell += 5.0;

if(c1 < s.vwap && fast > slow) buy -= 6.0;

if(c1 > s.vwap && fast < slow) sell -= 6.0;

}

// Candle quality.

if(InpAvoidDoji && body < atr * InpMinCandleBodyATR)

{

buy -= 14.0;

sell -= 14.0;

}

if(c1 > o1 && closePos >= 0.62) buy += 7.0;

if(c1 < o1 && closePos <= 0.38) sell += 7.0;

// Macro hard penalty.

if(InpRequireMacroAlignment)

{

if(c1 < macro) buy -= 24.0;

if(c1 > macro) sell -= 24.0;

}

// Exhaustion filter: avoid late entries too far away from the signal EMA.

if(s.distanceFromSignalEMAATR > InpMaxDistanceFromSignalEMA_ATR)

{

buy -= 12.0;

sell -= 12.0;

}

// Wick quality: avoid buying under a large rejection wick or selling over a large rejection wick.

if(InpRejectLargeWickAgainstTrade)

{

if(s.oppositeWickATRSell > InpMaxOppositeWickATR) buy -= 9.0;

if(s.oppositeWickATRBuy > InpMaxOppositeWickATR) sell -= 9.0;

}

// Volatility shock penalty.

if(InpUseVolatilityShockFilter)

{

if(s.candleRangeATR > InpMaxCandleRangeATR)

{

buy -= 18.0;

sell -= 18.0;

}

if(s.gapATR > InpMaxGapATR)

{

buy -= 18.0;

sell -= 18.0;

}

}

// V9: session quality and volatility acceleration.

if(InpUseSessionQualityFilter)

{

if(s.sessionQuality >= 2)

{

buy += 4.0;

sell += 4.0;

}

else if(s.sessionQuality <= 0)

{

buy -= 16.0;

sell -= 16.0;

}

else

{

buy -= 3.0;

sell -= 3.0;

}

}

if(InpUseATRAccelerationFilter && s.atrAcceleration > InpMaxATRAccelerationRatio)

{

buy -= 20.0;

sell -= 20.0;

}

if(InpUseSpreadSpikeFilter && !SpreadSpikeOK())

{

buy -= 16.0;

sell -= 16.0;

}

if(!ATRNormalizedSpreadOK(atr))

{

buy -= 18.0;

sell -= 18.0;

}

if(InpUseLiquidityDistanceFilter && hasStructure)

{

// Avoid opening directly into the nearest liquidity extreme unless it has already broken cleanly.

if(c1 < recentHigh && s.distanceToRecentHighATR < InpMinDistanceFromExtremeATR) buy -= 10.0;

if(c1 > recentLow && s.distanceToRecentLowATR < InpMinDistanceFromExtremeATR) sell -= 10.0;

}

// Spread penalty before clamping.

if(SpreadPts() > InpMaxSpreadPoints * 0.80)

{

buy -= 5.0;

sell -= 5.0;

}

// V13 alpha-harvest: reward clean directional conviction and penalize mixed signals.

if(InpUseAlphaHarvestEngine && InpUseTrendConvictionBonus)

{

if(adx >= InpAlphaMinADX && s.efficiency >= InpAlphaMinEfficiency && s.emaSlopeATR >= InpAlphaMinSlopeATR && closePos >= 0.58)

buy += 8.0;

if(adx >= InpAlphaMinADX && s.efficiency >= InpAlphaMinEfficiency && s.emaSlopeATR <= -InpAlphaMinSlopeATR && closePos <= 0.42)

sell += 8.0;

if(adx < InpMinADX || s.efficiency < InpMinRangeEfficiency)

{

buy -= 8.0;

sell -= 8.0;

}

}

// V15 elite-profit: extra reward only for clean impulse + trend efficiency.

if(InpUseV15EliteProfitGate && InpV15UseMomentumScoreBoost)

{

bool healthyVol = (s.atrAcceleration <= InpV15MaxHealthyATRAcceleration && s.atrAcceleration >= 0.75);

bool quality = (adx >= InpV15MinADX && s.efficiency >= InpV15MinEfficiency && s.bodyATR >= InpV15MinBodyATR && healthyVol);

if(quality && s.emaSlopeATR >= InpV15MinSlopeATR && c1 > sigEma && closePos >= 0.60)

buy += 10.0;

if(quality && s.emaSlopeATR <= -InpV15MinSlopeATR && c1 < sigEma && closePos <= 0.40)

sell += 10.0;

if(s.distanceFromSignalEMAATR > InpV15MaxEMAExtensionATR)

{

buy -= 14.0;

sell -= 14.0;

}

if(s.efficiency < InpV15MinEfficiency * 0.75)

{

buy -= 10.0;

sell -= 10.0;

}

}

// V16 apex-compound: reward only clean apex impulse and punish extended/noisy moves.

if(InpUseV16ApexCompoundEngine && InpV16UseScoreBoost)

{

bool healthyApexVol = (s.atrAcceleration >= 0.82 && s.atrAcceleration <= InpV16MaxATRAcceleration);

bool apexQuality = (adx >= InpV16MinADX && s.efficiency >= InpV16MinEfficiency && s.bodyATR >= InpV16MinBodyATR && healthyApexVol);

if(apexQuality && s.emaSlopeATR >= InpV16MinSlopeATR && c1 > sigEma && closePos >= 0.64 && s.buyConfirmed)

buy += 7.0;

if(apexQuality && s.emaSlopeATR <= -InpV16MinSlopeATR && c1 < sigEma && closePos <= 0.36 && s.sellConfirmed)

sell += 7.0;

if(s.distanceFromSignalEMAATR > InpV16MaxEMAExtensionATR)

{

buy -= 18.0;

sell -= 18.0;

}

if(s.atrAcceleration > InpV16MaxATRAcceleration || s.efficiency < InpV16MinEfficiency * 0.72)

{

buy -= 12.0;

sell -= 12.0;

}

}

s.buyScore = MathMax(0.0, MathMin(100.0, buy));

s.sellScore = MathMax(0.0, MathMin(100.0, sell));

s.scoreGap = MathAbs(s.buyScore - s.sellScore);

if(s.buyScore >= InpMinScoreToEnter && s.buyScore > s.sellScore + InpMinScoreGap)

s.direction = 1;

if(s.sellScore >= InpMinScoreToEnter && s.sellScore > s.buyScore + InpMinScoreGap)

s.direction = -1;

return true;

}

bool BaseFiltersOK(const SignalPack &sig)

{

ResetDayIfNeeded();

if(!SymbolOK())

{

g_status = "WRONG_SYMBOL";

return false;

}

if(AccountInfoDouble(ACCOUNT_EQUITY) < InpMinEquityForTrading)

{

g_status = "EQUITY_LOW";

return false;

}

if(!SessionOK())

{

g_status = "SESSION_BLOCK";

return false;

}

if(InManualBlackout())

{

g_status = "NEWS_BLACKOUT";

return false;

}

if(V14ShockPauseActive())

{

g_status = "V14_SHOCK_PAUSE";

return false;

}

if(V14ShockDetected(sig))

{

g_v14ShockPauseUntil = TimeCurrent() + InpV14ShockPauseMinutes * 60;

g_status = "V14_SHOCK_DETECTED";

DecisionLog(g_status);

return false;

}

if(TimeCurrent() < g_cooldownUntil)

{

g_status = "COOLDOWN";

return false;

}

if(SpreadPts() > InpMaxSpreadPoints)

{

g_status = "SPREAD_HIGH";

DecisionLog(g_status + " spread=" + DoubleToString(SpreadPts(), 1));

return false;

}

if(!SpreadSpikeOK())

{

g_status = "SPREAD_SPIKE";

DecisionLog(g_status + " spread=" + DoubleToString(SpreadPts(), 1) + " ema=" + DoubleToString(g_spreadEma, 1));

return false;

}

if(!ATRNormalizedSpreadOK(sig.atr))

{

g_status = "SPREAD_ATR_BLOCK";

DecisionLog(g_status);

return false;

}

if(InpUseSessionQualityFilter && sig.sessionQuality <= 0)

{

g_status = "SESSION_QUALITY_BLOCK";

DecisionLog(g_status);

return false;

}

if(InpUseATRAccelerationFilter && sig.atrAcceleration > InpMaxATRAccelerationRatio)

{

g_status = "ATR_ACCELERATION_BLOCK";

DecisionLog(g_status + " ratio=" + DoubleToString(sig.atrAcceleration, 2));

return false;

}

if(sig.direction != 0 && !TradeDirectionAllowed(sig.direction))

{

g_status = "DIRECTION_MODE_BLOCK";

return false;

}

if(AmbiguousSignalBlocked(sig))

{

g_status = "AMBIGUOUS_SIGNAL_BLOCK";

return false;

}

if(InpUseWeeklyProtection && WeeklyLossPct() >= InpWeeklyLossStopPct)

{

g_status = "WEEKLY_LOSS_STOP";

g_cooldownUntil = TimeCurrent() + InpCooldownAfterDDMinutes * 60;

return false;

}

if(InpUseVolatilityShockFilter && sig.candleRangeATR > InpMaxCandleRangeATR)

{

g_status = "VOLATILITY_SHOCK";

return false;

}

if(InpUseVolatilityShockFilter && sig.gapATR > InpMaxGapATR)

{

g_status = "GAP_SHOCK";

return false;

}

if(InpUseTrendSlopeFilter && sig.direction == 1 && sig.emaSlopeATR < InpMinEMASlopeATR)

{

g_status = "BUY_SLOPE_BLOCK";

return false;

}

if(InpUseTrendSlopeFilter && sig.direction == -1 && sig.emaSlopeATR > -InpMinEMASlopeATR)

{

g_status = "SELL_SLOPE_BLOCK";

return false;

}

if(InpUseConsecutiveCloseFilter && sig.direction == 1 && !sig.buyConfirmed)

{

g_status = "BUY_CONFIRM_BLOCK";

return false;

}

if(InpUseConsecutiveCloseFilter && sig.direction == -1 && !sig.sellConfirmed)

{

g_status = "SELL_CONFIRM_BLOCK";

return false;

}

if(g_entriesToday >= InpMaxNewEntriesPerDay)

{

g_status = "DAILY_ENTRY_LIMIT";

return false;

}

if((TimeCurrent() - g_lastEntry) < InpMinMinutesBetweenEntries * 60)

{

bool highConvictionReentry = false;

if(InpUseHighConvictionReentry && g_lastBasketWasProfit && g_lastBasketClose > 0 && sig.direction != 0)

{

bool enoughAfterWin = ((TimeCurrent() - g_lastBasketClose) >= InpMinMinutesAfterWinReentry * 60);

bool scoreOK = (DirectionScore(sig, sig.direction) >= InpReentryAfterWinScore);

bool alphaOK = (!InpUseAlphaHarvestEngine || AlphaTrend(sig, sig.direction) || ExplosiveTrend(sig, sig.direction));

highConvictionReentry = (enoughAfterWin && scoreOK && alphaOK && DailyLossPct() <= 0.0 && PeakDDPct() < InpHalfRiskAtDDPercent);

}

if(!highConvictionReentry)

{

g_status = "WAIT_BETWEEN_ENTRIES";

return false;

}

g_status = "HIGH_CONVICTION_REENTRY";

}

if(DailyLossPct() >= InpMaxDailyLossPercent)

{

g_status = "DAILY_LOSS_BLOCK";

g_cooldownUntil = TimeCurrent() + InpCooldownAfterDDMinutes * 60;

return false;

}

if(PeakDDPct() >= InpMaxEquityDDPercent)

{

g_status = "EQUITY_DD_BLOCK";

g_cooldownUntil = TimeCurrent() + InpCooldownAfterDDMinutes * 60;

return false;

}

if(InpUseEquityCurvePause && PeakDDPct() >= InpSoftDDPausePercent)

{

g_status = "SOFT_DD_PAUSE";

g_cooldownUntil = TimeCurrent() + InpSoftDDPauseMinutes * 60;

return false;

}

if(sig.adx < InpMinADX || sig.adx > InpMaxADX)

{

g_status = "ADX_BLOCK";

return false;

}

if(sig.atrPct < InpMinATRPct || sig.atrPct > InpMaxATRPct)

{

g_status = "ATR_BLOCK";

return false;

}

if(sig.efficiency < InpMinRangeEfficiency)

{

g_status = "CHOP_BLOCK";

return false;

}

if(InpCapitalProtectionMode && DailyProfitPct() >= InpDailyProfitTargetPercent)

{

g_status = "DAILY_PROFIT_LOCK";

return false;

}

if(g_consecutiveLossBaskets >= InpMaxConsecutiveLossBaskets)

{

g_status = "LOSS_STREAK_BLOCK";

g_cooldownUntil = TimeCurrent() + InpConsecutiveLossCooldownMin * 60;

return false;

}

if(sig.distanceFromSignalEMAATR > InpMaxDistanceFromSignalEMA_ATR)

{

g_status = "EXTENDED_FROM_EMA";

return false;

}

if(InpRejectLargeWickAgainstTrade)

{

if(sig.direction == 1 && sig.oppositeWickATRSell > InpMaxOppositeWickATR)

{

g_status = "BUY_REJECTION_WICK";

return false;

}

if(sig.direction == -1 && sig.oppositeWickATRBuy > InpMaxOppositeWickATR)

{

g_status = "SELL_REJECTION_WICK";

return false;

}

}

if(InpUseLiquidityDistanceFilter)

{

if(sig.direction == 1 && sig.distanceToRecentHighATR < InpMinDistanceFromExtremeATR)

{

g_status = "BUY_NEAR_LIQUIDITY_HIGH";

return false;

}

if(sig.direction == -1 && sig.distanceToRecentLowATR < InpMinDistanceFromExtremeATR)

{

g_status = "SELL_NEAR_LIQUIDITY_LOW";

return false;

}

}

double dynScore = DynamicMinScore();

if(sig.direction == 1 && sig.buyScore < dynScore)

{

g_status = "DYNAMIC_SCORE_BLOCK";

return false;

}

if(sig.direction == -1 && sig.sellScore < dynScore)

{

g_status = "DYNAMIC_SCORE_BLOCK";

return false;

}

if(!V14InitialEntryGateOK(sig))

return false;

if(!V15InitialEntryGateOK(sig))

return false;

if(!V16InitialEntryGateOK(sig))

return false;

if(!V17InitialEntryGateOK(sig))

return false;

return true;

}

double CurrentRiskMultiplier()

{

double mult = 1.0;

if(InpRiskThrottleOnDD)

{

if(PeakDDPct() >= InpHalfRiskAtDDPercent) mult *= 0.50;

if(DailyLossPct() >= InpMaxDailyLossPercent * 0.50) mult *= 0.50;

if(g_consecutiveLossBaskets == 1) mult *= 0.65;

if(g_consecutiveLossBaskets >= 2) mult *= 0.35;

}

if(InpCapitalProtectionMode && DailyProfitPct() >= InpDailyProfitTargetPercent * 0.70)

{

if(InpUseDailyProfitUnlock && DailyProfitPct() < InpUnlockedMaxDailyProfitPct && PeakDDPct() < InpHalfRiskAtDDPercent)

mult *= 0.85;

else

mult *= 0.50;

}

if(InpStrategyProfile == 1) mult *= 0.75;

if(InpUseEquitySnowballLimit && DailyProfitPct() >= InpSnowballRiskBoostAtProfitPct && PeakDDPct() <= InpHalfRiskAtDDPercent * 0.50 && DailyLossPct() <= InpMaxDailyLossPercent * 0.25)

mult *= MathMax(1.0, InpSnowballRiskMultiplier);

if(InpUseWeeklyProtection && WeeklyLossPct() >= InpWeeklyLossStopPct * 0.50) mult *= 0.50;

if(InpStrategyProfile == 3 && DailyLossPct() <= InpMaxDailyLossPercent * 0.25 && PeakDDPct() <= InpHalfRiskAtDDPercent * 0.50) mult *= 1.05;

return MathMax(0.10, MathMin(2.20, mult));

}

bool MarginOKForOrder(const int dir, const double lot)

{

if(lot <= 0.0) return false;

ENUM_ORDER_TYPE orderType = (dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);

double price = (dir == 1 ? Ask() : Bid());

double margin = 0.0;

if(!OrderCalcMargin(orderType, _Symbol, lot, price, margin))

return false;

double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

double equity = AccountInfoDouble(ACCOUNT_EQUITY);

if(equity <= 0.0) return false;

double freeAfterPct = (freeMargin - margin) / equity * 100.0;

return (freeAfterPct >= InpMinFreeMarginAfterTradePct);

}

double CalcLot(const double atr, const int gridIndex)

{

double currentLots = TotalLots();

double remaining = EffectiveMaxTotalLots() - currentLots;

double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

if(remaining < minLot) return 0.0;

double lot = InpFixedLot;

if(InpUseRiskLot)

{

double equity = AccountInfoDouble(ACCOUNT_EQUITY);

double riskMoney = equity * InpRiskPercent / 100.0 * CurrentRiskMultiplier();

double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

double stopDist = MathMax(atr * InpEmergencyStopATR, 300.0 * _Point);

double moneyPerLot = 0.0;

if(tickSize > 0.0) moneyPerLot = (stopDist / tickSize) * tickValue;

if(moneyPerLot > 0.0) lot = riskMoney / moneyPerLot;

}

lot *= MathPow(InpRecoveryLotMultiplier, gridIndex);

lot = MathMin(lot, remaining);

return ApplyTenKLotBand(lot);

}

bool OpenTrade(const int dir, const double atr, const int gridIndex)

{

if(TotalLots() >= EffectiveMaxTotalLots()) return false;

double lot = CalcLot(atr, gridIndex);

if(lot <= 0.0) return false;

if(InpUseAdaptiveGridStop && ProjectedBasketLossPct(dir, lot, atr) > InpMaxProjectedBasketLossPct)

{

g_status = "PROJECTED_LOSS_BLOCK";

return false;

}

if(!MarginOKForOrder(dir, lot))

{

g_status = "MARGIN_GUARD";

return false;

}

trade.SetExpertMagicNumber(InpMagic);

trade.SetDeviationInPoints(InpDeviationPoints);

trade.SetTypeFillingBySymbol(_Symbol);

double price = (dir == 1 ? Ask() : Bid());

double sl = (dir == 1 ? price - atr * InpEmergencyStopATR : price + atr * InpEmergencyStopATR);

sl = NormPrice(sl);

string comment = (gridIndex == 0 ? "QQ_V16_ENTRY" : "QQ_V16_RECOVERY");

bool ok = false;

if(dir == 1) ok = trade.Buy(lot, _Symbol, 0.0, sl, 0.0, comment);

if(dir == -1) ok = trade.Sell(lot, _Symbol, 0.0, sl, 0.0, comment);

if(ok)

{

g_lastEntry = TimeCurrent();

g_entriesToday++;

g_status = (gridIndex == 0 ? "OPEN_ENTRY" : "OPEN_RECOVERY");

JournalEvent(g_status, (dir == 1 ? "BUY" : "SELL") + StringFormat(" lot=%.2f grid=%d", lot, gridIndex));

}

return ok;

}

void ManageStops(const double atr)

{

if(atr <= 0.0) return;

for(int i = PositionsTotal() - 1; i >= 0; i--)

{

ulong tk = PositionGetTicket(i);

if(!PositionSelectByTicket(tk)) continue;

if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

long type = PositionGetInteger(POSITION_TYPE);

double open = PositionGetDouble(POSITION_PRICE_OPEN);

double sl = PositionGetDouble(POSITION_SL);

double tp = PositionGetDouble(POSITION_TP);

double cur = (type == POSITION_TYPE_BUY ? Bid() : Ask());

double profitDist = (type == POSITION_TYPE_BUY ? cur - open : open - cur);

double newSL = sl;

if(InpUseBreakEven && profitDist >= atr * InpBreakEvenStartATR)

{

double be = (type == POSITION_TYPE_BUY ? open + atr * InpBreakEvenLockATR : open - atr * InpBreakEvenLockATR);

if(type == POSITION_TYPE_BUY && (sl == 0.0 || be > sl)) newSL = be;

if(type == POSITION_TYPE_SELL && (sl == 0.0 || be < sl)) newSL = be;

}

if(InpUseTrailing && profitDist >= atr * InpTrailStartATR)

{

double trailATR = InpTrailDistanceATR;

if(InpUseProfitExpansion && profitDist >= atr * InpExpansionTriggerATR)

trailATR = MathMax(InpTrailDistanceATR, RunnerTrailATRForDistance(profitDist / atr));

double tr = (type == POSITION_TYPE_BUY ? cur - atr * trailATR : cur + atr * trailATR);

if(type == POSITION_TYPE_BUY && (newSL == 0.0 || tr > newSL)) newSL = tr;

if(type == POSITION_TYPE_SELL && (newSL == 0.0 || tr < newSL)) newSL = tr;

}

if(newSL != sl && newSL > 0.0)

trade.PositionModify(tk, NormPrice(newSL), tp);

}

}

void TryPartialClose(const int dir, const double atr, const double dist)

{

if(!InpUsePartialClose || g_partialDone) return;

if(dist < atr * InpPartialCloseAtATR) return;

bool any = false;

double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

for(int i = PositionsTotal() - 1; i >= 0; i--)

{

ulong tk = PositionGetTicket(i);

if(!PositionSelectByTicket(tk)) continue;

if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

long type = PositionGetInteger(POSITION_TYPE);

if(dir == 1 && type != POSITION_TYPE_BUY) continue;

if(dir == -1 && type != POSITION_TYPE_SELL) continue;

double vol = PositionGetDouble(POSITION_VOLUME);

double closeVol = NormalizeLot(vol * InpPartialClosePercent / 100.0);

if(closeVol >= minLot && vol - closeVol >= minLot)

{

if(trade.PositionClosePartial(tk, closeVol)) any = true;

}

}

if(any)

{

g_partialDone = true;

g_status = "PARTIAL_CLOSE";

}

}

void BasketProfitLock()

{

if(!InpUseBasketProfitLock) return;

int n = CountPositions();

if(n <= 0)

{

g_basketPeakProfit = 0.0;

g_partialDone = false;

return;

}

double p = BasketProfit();

if(p > g_basketPeakProfit) g_basketPeakProfit = p;

double minLock = AccountInfoDouble(ACCOUNT_EQUITY) * InpBasketMinLockProfitPct / 100.0;

if(g_basketPeakProfit >= minLock && p <= g_basketPeakProfit * InpBasketLockRetainPct / 100.0)

{

CloseAll();

g_status = "BASKET_PROFIT_LOCK";

g_basketPeakProfit = 0.0;

g_partialDone = false;

}

}

bool GridPermissionOK(const int dir, const SignalPack &sig)

{

if(!InpUseGrid) return false;

if(InpStrategyProfile == 1) return false;

if(!SessionOK()) return false;

if(InManualBlackout()) return false;

if(TimeCurrent() < g_cooldownUntil) return false;

if(SpreadPts() > InpMaxSpreadPoints) return false;

if(!SpreadSpikeOK()) return false;

if(!ATRNormalizedSpreadOK(sig.atr)) return false;

if(InpUseSessionQualityFilter && sig.sessionQuality <= 0) return false;

if(InpUseATRAccelerationFilter && sig.atrAcceleration > InpMaxATRAccelerationRatio) return false;

if(g_entriesToday >= InpMaxNewEntriesPerDay) return false;

if((TimeCurrent() - g_lastEntry) < InpMinMinutesBetweenEntries * 60) return false;

if(DailyLossPct() >= InpMaxDailyLossPercent) return false;

if(PeakDDPct() >= InpMaxEquityDDPercent) return false;

if(BasketLossPct() >= InpMaxBasketLossBeforeGridPct) return false;

if(InpCapitalProtectionMode && DailyProfitPct() >= InpDailyProfitTargetPercent) return false;

if(g_consecutiveLossBaskets >= InpMaxConsecutiveLossBaskets) return false;

if(sig.distanceFromSignalEMAATR > InpMaxDistanceFromSignalEMA_ATR) return false;

if(sig.adx < InpMinADX || sig.adx > InpMaxADX) return false;

if(sig.atrPct < InpMinATRPct || sig.atrPct > InpMaxATRPct) return false;

if(sig.efficiency < InpMinRangeEfficiency) return false;

if(!TradeDirectionAllowed(dir)) return false;

if(InpUseVolatilityShockFilter && sig.candleRangeATR > InpMaxCandleRangeATR) return false;

if(InpUseVolatilityShockFilter && sig.gapATR > InpMaxGapATR) return false;

if(InpUseTrendSlopeFilter && dir == 1 && sig.emaSlopeATR < InpMinEMASlopeATR) return false;

if(InpUseTrendSlopeFilter && dir == -1 && sig.emaSlopeATR > -InpMinEMASlopeATR) return false;

if(InpUseConsecutiveCloseFilter && dir == 1 && !sig.buyConfirmed) return false;

if(InpUseConsecutiveCloseFilter && dir == -1 && !sig.sellConfirmed) return false;

if(InpAddGridOnlyIfTrendValid)

{

if(dir == 1 && sig.sellScore >= InpOppositeScoreToClose) return false;

if(dir == -1 && sig.buyScore >= InpOppositeScoreToClose) return false;

if(dir == 1 && sig.buyScore < InpMinSameDirectionScoreForGrid) return false;

if(dir == -1 && sig.sellScore < InpMinSameDirectionScoreForGrid) return false;

if(InpStrategyProfile == 2 && dir == 1 && sig.buyScore < DynamicMinScore() - 4.0) return false;

if(InpStrategyProfile == 2 && dir == -1 && sig.sellScore < DynamicMinScore() - 4.0) return false;

}

return true;

}

bool StrongTrend(const SignalPack &sig, const int dir)

{

if(dir == 1)

return (sig.buyScore >= InpStrongTrendScore && sig.buyScore > sig.sellScore + InpMinScoreGap && sig.adx >= InpStrongTrendADX && sig.efficiency >= InpStrongTrendEfficiency && sig.emaSlopeATR > 0.0);

if(dir == -1)

return (sig.sellScore >= InpStrongTrendScore && sig.sellScore > sig.buyScore + InpMinScoreGap && sig.adx >= InpStrongTrendADX && sig.efficiency >= InpStrongTrendEfficiency && sig.emaSlopeATR < 0.0);

return false;

}

double BasketProfitPct()

{

double eq = AccountInfoDouble(ACCOUNT_EQUITY);

if(eq <= 0.0) return 0.0;

return MathMax(0.0, BasketProfit()) / eq * 100.0;

}

double DirectionScore(const SignalPack &sig, const int dir)

{

if(dir == 1) return sig.buyScore;

if(dir == -1) return sig.sellScore;

return 0.0;

}

double OppositeScore(const SignalPack &sig, const int dir)

{

if(dir == 1) return sig.sellScore;

if(dir == -1) return sig.buyScore;

return 0.0;

}

bool MegaTrend(const SignalPack &sig, const int dir)

{

if(!StrongTrend(sig, dir)) return false;

if(DirectionScore(sig, dir) < InpMegaTrendScore) return false;

if(sig.adx < InpMegaTrendADX) return false;

if(sig.efficiency < InpMegaTrendEfficiency) return false;

if(dir == 1 && sig.emaSlopeATR <= 0.0) return false;

if(dir == -1 && sig.emaSlopeATR >= 0.0) return false;

return true;

}

bool AlphaTrend(const SignalPack &sig, const int dir)

{

if(!InpUseAlphaHarvestEngine) return false;

if(!StrongTrend(sig, dir)) return false;

if(DirectionScore(sig, dir) < InpStrongTrendScore) return false;

if(sig.scoreGap < InpAlphaMinScoreGap) return false;

if(sig.adx < InpAlphaMinADX) return false;

if(sig.efficiency < InpAlphaMinEfficiency) return false;

if(dir == 1 && sig.emaSlopeATR < InpAlphaMinSlopeATR) return false;

if(dir == -1 && sig.emaSlopeATR > -InpAlphaMinSlopeATR) return false;

if(sig.atrAcceleration > InpMaxATRAccelerationRatio) return false;

if(sig.sessionQuality <= 0) return false;

return true;

}

bool ExplosiveTrend(const SignalPack &sig, const int dir)

{

if(!InpUseExplosiveRunnerTarget) return false;

if(!AlphaTrend(sig, dir)) return false;

if(DirectionScore(sig, dir) < InpExplosiveTrendScore) return false;

if(sig.adx < InpExplosiveTrendADX) return false;

if(sig.efficiency < InpExplosiveTrendEfficiency) return false;

return true;

}

bool AmbiguousSignalBlocked(const SignalPack &sig)

{

if(!InpUseAlphaHarvestEngine || !InpUseAmbiguityPenalty) return false;

if(sig.buyScore >= InpAmbiguousBothScoreLevel && sig.sellScore >= InpAmbiguousBothScoreLevel && sig.scoreGap < InpAmbiguityMinGap)

return true;

return false;

}

bool V14ShockPauseActive()

{

return (InpUseV14ShockPause && TimeCurrent() < g_v14ShockPauseUntil);

}

bool V14ShockDetected(const SignalPack &sig)

{

if(!InpUseV14ShockPause) return false;

if(sig.candleRangeATR >= InpV14ShockCandleRangeATR) return true;

if(sig.gapATR >= InpV14ShockGapATR) return true;

if(sig.atrAcceleration >= InpV14ShockATRAcceleration) return true;

return false;

}

bool V14InitialEntryGateOK(const SignalPack &sig)

{

if(!InpUseV14ConvictionGate) return true;

if(sig.direction == 0) return true;

double same = DirectionScore(sig, sig.direction);

if(same < InpV14MinEntryScore)

{

g_status = "V14_ENTRY_SCORE_BLOCK";

return false;

}

if(sig.scoreGap < InpV14MinEntryGap)

{

g_status = "V14_ENTRY_GAP_BLOCK";

return false;

}

if(InpV14RequireAlphaOrExplosive && !AlphaTrend(sig, sig.direction) && !ExplosiveTrend(sig, sig.direction))

{

g_status = "V14_ALPHA_BLOCK";

return false;

}

return true;

}

bool V14AddQualityOK(const SignalPack &sig, const int dir)

{

if(!InpUseV14AddQualityGate) return true;

if(InpV14NoAddAfterScaleOut && g_partialDone) return false;

if(sig.efficiency < InpV14MinAddEfficiency) return false;

if(sig.scoreGap < InpV14MinAddScoreGap) return false;

if(!AlphaTrend(sig, dir) && !ExplosiveTrend(sig, dir)) return false;

return true;

}

bool V14RunnerMFEGuardCloseAllowed(const SignalPack &sig, const int dir)

{

if(InpV14RunnerMFEHoldIfExplosive && ExplosiveTrend(sig, dir)) return false;

if(AlphaTrend(sig, dir) && DirectionScore(sig, dir) >= InpAlphaTrailWidenScore) return false;

return true;

}

void V14RunnerMFEGuard(const SignalPack &sig, const int dir)

{

if(!InpUseV14RunnerMFEGuard) return;

if(CountPositions(dir) <= 0) return;

double eq = AccountInfoDouble(ACCOUNT_EQUITY);

if(eq <= 0.0) return;

double peakPct = g_basketPeakProfit / eq * 100.0;

double nowPct = BasketProfit() / eq * 100.0;

if(peakPct < InpV14RunnerMFEGuardStartPct) return;

if(nowPct <= peakPct * InpV14RunnerMFERetainPct / 100.0 && V14RunnerMFEGuardCloseAllowed(sig, dir))

{

CloseAll();

g_status = "V14_RUNNER_MFE_GUARD";

DecisionLog(g_status + StringFormat(" peak=%.2f now=%.2f", peakPct, nowPct));

g_basketPeakProfit = 0.0;

g_partialDone = false;

g_runnerBestScore = 0.0;

g_runnerBestDistanceATR = 0.0;

}

}

bool V15EliteTrend(const SignalPack &sig, const int dir)

{

if(!InpUseV15EliteProfitGate) return true;

if(dir == 0) return false;

double same = DirectionScore(sig, dir);

if(same < InpV15MinEntryScore) return false;

if(sig.scoreGap < InpV15MinEntryGap) return false;

if(sig.adx < InpV15MinADX) return false;

if(sig.efficiency < InpV15MinEfficiency) return false;

if(sig.bodyATR < InpV15MinBodyATR) return false;

if(sig.atrAcceleration > InpV15MaxHealthyATRAcceleration) return false;

if(sig.distanceFromSignalEMAATR > InpV15MaxEMAExtensionATR) return false;

if(sig.sessionQuality <= 0) return false;

if(dir == 1)

{

if(sig.emaSlopeATR < InpV15MinSlopeATR) return false;

if(!sig.buyConfirmed) return false;

}

if(dir == -1)

{

if(sig.emaSlopeATR > -InpV15MinSlopeATR) return false;

if(!sig.sellConfirmed) return false;

}

if(InpV15RequireEliteTrend && !AlphaTrend(sig, dir) && !ExplosiveTrend(sig, dir) && !MegaTrend(sig, dir))

return false;

return true;

}

bool V15InitialEntryGateOK(const SignalPack &sig)

{

if(!InpUseV15EliteProfitGate) return true;

if(sig.direction == 0) return true;

if(V15EliteTrend(sig, sig.direction)) return true;

g_status = "V15_ELITE_ENTRY_BLOCK";

DecisionLog(g_status + " score=" + DoubleToString(DirectionScore(sig, sig.direction), 1) + " gap=" + DoubleToString(sig.scoreGap, 1) + " adx=" + DoubleToString(sig.adx, 1) + " eff=" + DoubleToString(sig.efficiency, 2));

return false;

}

bool V15ExceptionalRunnerHold(const SignalPack &sig, const int dir)

{

if(!InpUseV15EliteProfitGate || !InpV15HoldExceptionalRunner) return false;

if(DirectionScore(sig, dir) < InpV15RunnerHoldScore) return false;

if(sig.adx < InpV15RunnerHoldADX) return false;

if(sig.efficiency < InpV15RunnerHoldEfficiency) return false;

if(dir == 1 && sig.emaSlopeATR < InpV15MinSlopeATR) return false;

if(dir == -1 && sig.emaSlopeATR > -InpV15MinSlopeATR) return false;

if(!AlphaTrend(sig, dir) && !ExplosiveTrend(sig, dir) && !MegaTrend(sig, dir)) return false;

return true;

}

void V15ProfitStaircase(const SignalPack &sig, const int dir)

{

if(!InpUseV15EliteProfitGate || !InpV15UseProfitStaircase) return;

if(CountPositions(dir) <= 0) return;

double eq = AccountInfoDouble(ACCOUNT_EQUITY);

if(eq <= 0.0) return;

double peakPct = g_basketPeakProfit / eq * 100.0;

double nowPct = BasketProfit() / eq * 100.0;

if(InpV15UseProfitCeilingClose && nowPct >= InpV15AbsoluteProfitClosePct && !V15ExceptionalRunnerHold(sig, dir))

{

CloseAll();

g_status = "V15_ABSOLUTE_PROFIT_CLOSE";

DecisionLog(g_status + StringFormat(" profitPct=%.2f", nowPct));

g_basketPeakProfit = 0.0;

g_partialDone = false;

g_runnerBestScore = 0.0;

g_runnerBestDistanceATR = 0.0;

return;

}

if(peakPct < InpV15StaircaseStartPct) return;

if(nowPct <= peakPct * InpV15StaircaseRetainPct / 100.0 && !V15ExceptionalRunnerHold(sig, dir))

{

CloseAll();

g_status = "V15_PROFIT_STAIRCASE_LOCK";

DecisionLog(g_status + StringFormat(" peak=%.2f now=%.2f", peakPct, nowPct));

g_basketPeakProfit = 0.0;

g_partialDone = false;

g_runnerBestScore = 0.0;

g_runnerBestDistanceATR = 0.0;

}

}

bool V16ApexTrend(const SignalPack &sig, const int dir)

{

if(!InpUseV16ApexCompoundEngine) return true;

if(dir == 0) return false;

double same = DirectionScore(sig, dir);

if(same < InpV16MinEntryScore) return false;

if(sig.scoreGap < InpV16MinEntryGap) return false;

if(sig.adx < InpV16MinADX) return false;

if(sig.efficiency < InpV16MinEfficiency) return false;

if(sig.bodyATR < InpV16MinBodyATR) return false;

if(sig.atrAcceleration > InpV16MaxATRAcceleration) return false;

if(sig.distanceFromSignalEMAATR > InpV16MaxEMAExtensionATR) return false;

if(sig.sessionQuality < (int)InpV16MinSessionQuality) return false;

if(dir == 1)

{

if(sig.emaSlopeATR < InpV16MinSlopeATR) return false;

if(InpV16RequireConfirmedClose && !sig.buyConfirmed) return false;

}

if(dir == -1)

{

if(sig.emaSlopeATR > -InpV16MinSlopeATR) return false;

if(InpV16RequireConfirmedClose && !sig.sellConfirmed) return false;

}

if(InpV16RequireApexTrend && !AlphaTrend(sig, dir) && !MegaTrend(sig, dir) && !ExplosiveTrend(sig, dir) && !V15ExceptionalRunnerHold(sig, dir))

return false;

return true;

}

bool V16InitialEntryGateOK(const SignalPack &sig)

{

if(!InpUseV16ApexCompoundEngine) return true;

if(sig.direction == 0) return true;

if(V16ApexTrend(sig, sig.direction)) return true;

g_status = "V16_APEX_ENTRY_BLOCK";

DecisionLog(g_status + " score=" + DoubleToString(DirectionScore(sig, sig.direction), 1) + " gap=" + DoubleToString(sig.scoreGap, 1) + " adx=" + DoubleToString(sig.adx, 1) + " eff=" + DoubleToString(sig.efficiency, 2));

return false;

}

bool V16ApexRunnerHold(const SignalPack &sig, const int dir)

{

if(!InpUseV16ApexCompoundEngine) return false;

if(DirectionScore(sig, dir) < InpV16ApexRunnerScore) return false;

if(sig.adx < InpV16ApexRunnerADX) return false;

if(sig.efficiency < InpV16ApexRunnerEfficiency) return false;

if(dir == 1 && sig.emaSlopeATR < InpV16MinSlopeATR) return false;

if(dir == -1 && sig.emaSlopeATR > -InpV16MinSlopeATR) return false;

if(sig.atrAcceleration > InpV16MaxATRAcceleration) return false;

return (AlphaTrend(sig, dir) || MegaTrend(sig, dir) || ExplosiveTrend(sig, dir));

}

bool V16BadEntryScratchNeeded(const SignalPack &sig, const int dir, const double distATR, const datetime oldest)

{

if(!InpUseV16ApexCompoundEngine || !InpV16UseBadEntryScratch) return false;

if(BasketProfit() >= 0.0) return false;

if(oldest <= 0) return false;

int ageMin = (int)((TimeCurrent() - oldest) / 60);

if(ageMin > InpV16ScratchMinutes) return false;

double same = DirectionScore(sig, dir);

double opp = OppositeScore(sig, dir);

if(distATR <= -InpV16ScratchLossATR && !V16ApexTrend(sig, dir)) return true;

if(distATR <= -InpV16ScratchLossATR * 0.65 && opp >= same + InpV16ScratchOppositeGap) return true;

return false;

}

void V16ApexHighWaterLock(const SignalPack &sig, const int dir)

{

if(!InpUseV16ApexCompoundEngine || !InpV16UseApexHighWaterLock) return;

if(CountPositions(dir) <= 0) return;

double eq = AccountInfoDouble(ACCOUNT_EQUITY);

if(eq <= 0.0) return;

double peakPct = g_basketPeakProfit / eq * 100.0;

double nowPct = BasketProfit() / eq * 100.0;

if(peakPct < InpV16HighWaterStartPct) return;

double retain = (V16ApexRunnerHold(sig, dir) ? InpV16ApexHoldRetainPct : InpV16HighWaterRetainPct);

if(nowPct <= peakPct * retain / 100.0)

{

CloseAll();

g_status = "V16_APEX_HIGHWATER_LOCK";

DecisionLog(g_status + StringFormat(" peak=%.2f now=%.2f retain=%.1f", peakPct, nowPct, retain));

g_basketPeakProfit = 0.0;

g_partialDone = false;

g_runnerBestScore = 0.0;

g_runnerBestDistanceATR = 0.0;

}

}

bool V16AddGateOK(const SignalPack &sig, const int dir, const double distATR)

{

if(!InpUseV16ApexCompoundEngine || !InpV16UseApexAddGate) return true;

if(CountPositions(dir) >= InpV16MaxPositions) return false;

if(BasketProfitPct() < InpV16MinAddBasketPct) return false;

if(distATR < InpV16MinAddDistanceATR) return false;

if(DirectionScore(sig, dir) < InpV16MinAddScore) return false;

if(sig.scoreGap < InpV16MinAddGap) return false;

if(!V16ApexTrend(sig, dir) && !V16ApexRunnerHold(sig, dir)) return false;

if(InpV16BlockAddIfProfitRetracing)

{

double eq = AccountInfoDouble(ACCOUNT_EQUITY);

if(eq > 0.0 && g_basketPeakProfit > 0.0)

{

double nowPct = BasketProfit() / eq * 100.0;

double peakPct = g_basketPeakProfit / eq * 100.0;

if(peakPct > 0.0)

{

double retracePct = 100.0 - (nowPct / peakPct * 100.0);

if(retracePct > InpV16AddMaxRetracePct) return false;

}

}

}

return true;

}

bool V17CoreContinuation(const SignalPack &sig, const int dir)

{

if(!InpUseV17ProfitAsymmetry) return true;

if(dir == 0) return false;

double same = DirectionScore(sig, dir);

if(same < InpV17CoreScore) return false;

if(sig.scoreGap < InpV17MinGap) return false;

if(sig.adx < InpV17MinADX) return false;

if(sig.efficiency < InpV17MinEfficiency) return false;

if(sig.bodyATR < InpV17MinBodyATR) return false;

if(sig.atrAcceleration > InpV17MaxATRAcceleration) return false;

if(sig.distanceFromSignalEMAATR > InpV17MaxEMAExtensionATR) return false;

if(sig.sessionQuality <= 0) return false;

if(dir == 1)

{

if(sig.emaSlopeATR < InpV17MinSlopeATR) return false;

if(!sig.buyConfirmed) return false;

}

if(dir == -1)

{

if(sig.emaSlopeATR > -InpV17MinSlopeATR) return false;

if(!sig.sellConfirmed) return false;

}

return true;

}

bool V17ApexContinuation(const SignalPack &sig, const int dir)

{

if(!InpUseV17ProfitAsymmetry) return true;

if(!V17CoreContinuation(sig, dir)) return false;

if(DirectionScore(sig, dir) < InpV17ApexScore) return false;

if(sig.adx < InpV17ReaccelerationADX) return false;

if(sig.efficiency < InpV17ReaccelerationEfficiency) return false;

return (AlphaTrend(sig, dir) || MegaTrend(sig, dir) || ExplosiveTrend(sig, dir) || V16ApexRunnerHold(sig, dir));

}

bool V17ThreeBarReversalBlocked(const SignalPack &sig, const int dir)

{

if(!InpUseV17ProfitAsymmetry || !InpV17BlockThreeBarReversal) return false;

if(dir == 1)

{

if(sig.oppositeWickATRSell >= InpV17ReversalWickATR && sig.distanceToRecentHighATR <= InpMinDistanceFromExtremeATR * 1.35)

return true;

}

if(dir == -1)

{

if(sig.oppositeWickATRBuy >= InpV17ReversalWickATR && sig.distanceToRecentLowATR <= InpMinDistanceFromExtremeATR * 1.35)

return true;

}

return false;

}

bool V17InitialEntryGateOK(const SignalPack &sig)

{

if(!InpUseV17ProfitAsymmetry) return true;

if(sig.direction == 0) return true;

int dir = sig.direction;

bool clean = V17CoreContinuation(sig, dir);

bool apex = V17ApexContinuation(sig, dir);

if(V17ThreeBarReversalBlocked(sig, dir))

{

g_status = "V17_REVERSAL_RISK_BLOCK";

DecisionLog(g_status);

return false;

}

if(apex) return true;

if(InpV17AllowCleanContinuation && clean && !InpV16RequireApexTrend) return true;

if(InpV17AllowCleanContinuation && clean && (AlphaTrend(sig, dir) || MegaTrend(sig, dir))) return true;

g_status = "V17_PROFIT_ASYMMETRY_BLOCK";

DecisionLog(g_status + " score=" + DoubleToString(DirectionScore(sig, dir), 1) + " gap=" + DoubleToString(sig.scoreGap, 1) + " adx=" + DoubleToString(sig.adx, 1) + " eff=" + DoubleToString(sig.efficiency, 2));

return false;

}

bool V17FailedMomentumCutNeeded(const SignalPack &sig, const int dir, const double distATR, const datetime oldest)

{

if(!InpUseV17ProfitAsymmetry || !InpV17UseFailedMomentumCut) return false;

if(oldest <= 0) return false;

if(BasketProfit() >= 0.0) return false;

int ageMin = (int)((TimeCurrent() - oldest) / 60);

if(ageMin < InpV17FailedMoveMinutes) return false;

if(g_v17BasketMFEATR >= InpV17FailedMoveMinMFE_ATR) return false;

if(distATR > -InpV17FailedMoveLossATR) return false;

if(V17ApexContinuation(sig, dir)) return false;

return true;

}

void V17RunnerProfitElasticity(const SignalPack &sig, const int dir)

{

if(!InpUseV17ProfitAsymmetry || !InpV17UseRunnerProfitElasticity) return;

if(CountPositions(dir) <= 0) return;

double eq = AccountInfoDouble(ACCOUNT_EQUITY);

if(eq <= 0.0) return;

double peakPct = g_basketPeakProfit / eq * 100.0;

double nowPct = BasketProfit() / eq * 100.0;

if(peakPct < InpV17ElasticLockStartPct) return;

bool apex = V17ApexContinuation(sig, dir) || V16ApexRunnerHold(sig, dir) || ExplosiveTrend(sig, dir);

double retain = (apex ? InpV17ElasticRetainApexPct : InpV17ElasticRetainNormalPct);

if(nowPct >= InpV17AbsoluteProfitCeilingPct && !apex)

{

CloseAll();

g_status = "V17_ABSOLUTE_PROFIT_CEILING";

DecisionLog(g_status + StringFormat(" profitPct=%.2f", nowPct));

g_basketPeakProfit = 0.0;

g_partialDone = false;

g_runnerBestScore = 0.0;

g_runnerBestDistanceATR = 0.0;

g_v17BasketMFEATR = 0.0;

return;

}

if(nowPct <= peakPct * retain / 100.0)

{

CloseAll();

g_status = "V17_ELASTIC_PROFIT_LOCK";

DecisionLog(g_status + StringFormat(" peak=%.2f now=%.2f retain=%.1f", peakPct, nowPct, retain));

g_basketPeakProfit = 0.0;

g_partialDone = false;

g_runnerBestScore = 0.0;

g_runnerBestDistanceATR = 0.0;

g_v17BasketMFEATR = 0.0;

}

}

bool V17AddGateOK(const SignalPack &sig, const int dir, const double distATR)

{

if(!InpUseV17ProfitAsymmetry) return true;

if(BasketProfitPct() < InpV17AddMinBasketPct) return false;

if(distATR < InpV17AddMinDistanceATR) return false;

if(DirectionScore(sig, dir) < InpV17ReaccelerationScore) return false;

if(sig.adx < InpV17ReaccelerationADX) return false;

if(sig.efficiency < InpV17ReaccelerationEfficiency) return false;

if(!V17CoreContinuation(sig, dir)) return false;

return true;

}

bool EarlyBadTradeAbortNeeded(const SignalPack &sig, const int dir, const double distATR, const datetime oldest)

{

if(!InpUseAlphaHarvestEngine || !InpUseEarlyBadTradeAbort) return false;

if(BasketProfit() >= 0.0) return false;

if(oldest <= 0) return false;

int ageMin = (int)((TimeCurrent() - oldest) / 60);

if(ageMin > InpEarlyAbortMinutes) return false;

double same = DirectionScore(sig, dir);

double opp = OppositeScore(sig, dir);

if(distATR <= -InpEarlyAbortLossATR && same <= InpEarlyAbortMaxSameScore) return true;

if(distATR <= -InpEarlyAbortLossATR * 0.70 && opp >= same + InpFastLoserOppositeGap) return true;

return false;

}

double HyperTargetATR(const SignalPack &sig, const int dir, const double currentTarget)

{

if(!InpUseHyperRunnerTP) return currentTarget;

double t = currentTarget;

if(StrongTrend(sig, dir)) t = MathMax(t, InpStrongTrendTPATR);

if(MegaTrend(sig, dir)) t = MathMax(t, InpMegaTrendTPATR);

if(DirectionScore(sig, dir) >= 99.0 && sig.adx >= InpMegaTrendADX + 6.0 && sig.efficiency >= InpMegaTrendEfficiency + 0.08)

t = MathMax(t, InpHyperTrendTPATR);

if(AlphaTrend(sig, dir)) t = MathMax(t, InpMegaTrendTPATR);

if(ExplosiveTrend(sig, dir)) t = MathMax(t, InpExplosiveTrendTPATR);

if(InpUseV16ApexCompoundEngine && V16ApexRunnerHold(sig, dir)) t = MathMax(t, InpV16ApexTargetATR);

return t;

}

double RunnerTrailATRForDistance(const double distATR)

{

double trail = InpExpansionTrailATR;

if(!InpUseAsymmetricProfitEngine) return trail;

if(distATR >= InpRunnerStretchStartATR)

{

double k = MathMin(1.0, (distATR - InpRunnerStretchStartATR) / MathMax(0.10, InpHyperTrendTPATR - InpRunnerStretchStartATR));

double maxTrail = InpRunnerMaxTrailATR;

if(InpUseAlphaHarvestEngine && InpUseAdaptiveRunnerTrail) maxTrail = MathMax(maxTrail, InpAlphaMaxTrailATR);

trail = InpExpansionTrailATR + (maxTrail - InpExpansionTrailATR) * k;

}

return MathMax(InpTrailDistanceATR, trail);

}

bool FastLoserCutNeeded(const SignalPack &sig, const int dir, const double distATR, const datetime oldest)

{

if(!InpUseFastLoserCut) return false;

if(BasketProfit() >= 0.0) return false;

if(oldest <= 0) return false;

int ageMin = (int)((TimeCurrent() - oldest) / 60);

double same = DirectionScore(sig, dir);

double opp = OppositeScore(sig, dir);

if(EarlyBadTradeAbortNeeded(sig, dir, distATR, oldest)) return true;

if(distATR <= -InpFastLoserCutATR && same <= InpFastLoserMinSameScore) return true;

if(ageMin >= InpFastLoserCutMinutes && opp >= same + InpFastLoserOppositeGap) return true;

if(ageMin >= InpFastLoserCutMinutes * 2 && same < DynamicMinScore() - InpRunnerExhaustionScoreDrop) return true;

return false;

}

bool RunnerExhausted(const SignalPack &sig, const int dir, const double distATR)

{

if(!InpCloseOnRunnerExhaustion) return false;

if(BasketProfit() <= 0.0) return false;

if(distATR < InpExpansionTriggerATR) return false;

double same = DirectionScore(sig, dir);

if(same > g_runnerBestScore) g_runnerBestScore = same;

if(distATR > g_runnerBestDistanceATR) g_runnerBestDistanceATR = distATR;

if(g_runnerBestScore >= InpMegaTrendScore && same <= g_runnerBestScore - InpRunnerExhaustionScoreDrop)

return true;

if(g_runnerBestDistanceATR >= InpMegaTrendTPATR && distATR <= g_runnerBestDistanceATR - MathMax(0.80, InpExpansionTrailATR))

return true;

return false;

}

bool ProtectedForWinnerAdd(const int dir, const double atr)

{

if(!InpRequireProtectedSLForAdd) return true;

if(atr <= 0.0) return false;

for(int i = PositionsTotal() - 1; i >= 0; i--)

{

ulong tk = PositionGetTicket(i);

if(!PositionSelectByTicket(tk)) continue;

if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

long type = PositionGetInteger(POSITION_TYPE);

if(dir == 1 && type != POSITION_TYPE_BUY) continue;

if(dir == -1 && type != POSITION_TYPE_SELL) continue;

double open = PositionGetDouble(POSITION_PRICE_OPEN);

double sl = PositionGetDouble(POSITION_SL);

if(sl <= 0.0) return false;

if(dir == 1 && sl < open - atr * 0.05) return false;

if(dir == -1 && sl > open + atr * 0.05) return false;

}

return true;

}

bool OpenWinnerAdd(const int dir, const double atr, const int winnerIndex)

{

if(TotalLots() >= EffectiveMaxTotalLots()) return false;

double baseLot = CalcLot(atr, 0);

double lotFactor = InpWinnerAddLotMultiplier;

if(InpUseLockedProfitPyramid)

lotFactor *= MathPow(MathMax(0.10, InpPyramidLotDecay), MathMax(0, winnerIndex - 1));

double lot = NormalizeLot(baseLot * lotFactor);

double remaining = EffectiveMaxTotalLots() - TotalLots();

lot = NormalizeLot(MathMin(lot, remaining));

if(lot <= 0.0) return false;

if(!MarginOKForOrder(dir, lot))

{

g_status = "WINNER_ADD_MARGIN_BLOCK";

return false;

}

if(InpUseAdaptiveGridStop && ProjectedBasketLossPct(dir, lot, atr) > InpMaxProjectedBasketLossPct)

{

g_status = "WINNER_ADD_PROJECTED_LOSS_BLOCK";

return false;

}

trade.SetExpertMagicNumber(InpMagic);

trade.SetDeviationInPoints(InpDeviationPoints);

trade.SetTypeFillingBySymbol(_Symbol);

double price = (dir == 1 ? Ask() : Bid());

double sl = (dir == 1 ? price - atr * InpEmergencyStopATR : price + atr * InpEmergencyStopATR);

sl = NormPrice(sl);

string comment = "QQ_V16_WINNER_ADD";

bool ok = false;

if(dir == 1) ok = trade.Buy(lot, _Symbol, 0.0, sl, 0.0, comment);

if(dir == -1) ok = trade.Sell(lot, _Symbol, 0.0, sl, 0.0, comment);

if(ok)

{

g_lastEntry = TimeCurrent();

g_lastWinnerAdd = TimeCurrent();

g_entriesToday++;

g_status = "OPEN_WINNER_ADD";

JournalEvent(g_status, (dir == 1 ? "BUY" : "SELL") + StringFormat(" lot=%.2f add=%d", lot, winnerIndex));

}

return ok;

}

void TryWinnerAdd(const int dir, const SignalPack &sig, const double atr, const double dist)

{

if(!InpUseAddToWinner) return;

int maxAdds = (InpUseLockedProfitPyramid ? InpMaxPyramidAdds : InpMaxWinnerAdds);

if(maxAdds <= 0) return;

if(atr <= 0.0 || dist <= 0.0) return;

double distATR = dist / atr;

if(!StrongTrend(sig, dir)) return;

if(BasketProfit() <= 0.0) return;

if(InpUseAlphaHarvestEngine && InpUseProfitOnlyAdds && BasketProfitPct() < InpMinBasketProfitForAnyAddPct) return;

if(InpUseAlphaHarvestEngine && !AlphaTrend(sig, dir)) return;

if(!V14AddQualityOK(sig, dir)) return;

if(InpV15BlockWeakAddAfterWin)

{

if(BasketProfitPct() < InpV15MinAddBasketProfitPct) return;

if(distATR < InpV15MinAddDistanceATR) return;

if(!V15EliteTrend(sig, dir) && !V15ExceptionalRunnerHold(sig, dir)) return;

}

if(!V16AddGateOK(sig, dir, distATR)) return;

if(!V17AddGateOK(sig, dir, distATR)) return;

if(InpUseLockedProfitPyramid && BasketProfitPct() < InpPyramidMinBasketProfitPct) return;

if(InpUseLockedProfitPyramid && DirectionScore(sig, dir) < InpPyramidMinSameScore) return;

if(g_entriesToday >= InpMaxNewEntriesPerDay) return;

if((TimeCurrent() - g_lastWinnerAdd) < InpMinMinutesBetweenWinnerAdds * 60) return;

if(!ProtectedForWinnerAdd(dir, atr)) return;

if(!SessionOK() || InManualBlackout()) return;

if(SpreadPts() > InpMaxSpreadPoints || !SpreadSpikeOK() || !ATRNormalizedSpreadOK(atr)) return;

if(DailyLossPct() > 0.0 || PeakDDPct() >= InpHalfRiskAtDDPercent) return;

if(dir == 1 && sig.buyScore < InpMinScoreForWinnerAdd) return;

if(dir == -1 && sig.sellScore < InpMinScoreForWinnerAdd) return;

int n = CountPositions(dir);

int addsDone = MathMax(0, n - 1);

if(addsDone >= maxAdds) return;

double last = LastEntryPrice(dir);

if(last <= 0.0) return;

double addStep = (InpUseLockedProfitPyramid ? InpPyramidStepATR : InpWinnerAddStepATR);

double needed = atr * addStep * MathPow(1.18, addsDone);

if(InpUseLockedProfitPyramid && distATR < InpExpansionTriggerATR + addStep * addsDone) return;

bool favorable = (dir == 1 && Bid() >= last + needed) || (dir == -1 && Ask() <= last - needed);

bool pullbackAdd = false;

if(InpUseAlphaHarvestEngine && InpUsePullbackPyramid && BasketProfitPct() >= InpMinBasketProfitForAnyAddPct && DirectionScore(sig, dir) >= InpPullbackPyramidMinScore)

{

if(sig.distanceFromSignalEMAATR <= InpPullbackPyramidMaxEMA_ATR)

pullbackAdd = true;

}

if(favorable || pullbackAdd)

OpenWinnerAdd(dir, atr, addsDone + 1);

}

void BasketNetBreakEvenLock(const int dir, const double atr, const double dist)

{

if(!InpUseBasketNetBreakEvenLock) return;

if(atr <= 0.0 || dist < atr * InpBasketNetBEStartATR) return;

if(CountPositions(dir) <= 0) return;

double entry = WeightedEntry(dir);

if(entry <= 0.0) return;

double targetSL = (dir == 1 ? entry + atr * InpBasketNetBELockATR : entry - atr * InpBasketNetBELockATR);

double stopLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

double pad = MathMax(stopLevel, 2.0 * _Point);

if(dir == 1)

targetSL = MathMin(targetSL, Bid() - pad);

else

targetSL = MathMax(targetSL, Ask() + pad);

if(targetSL <= 0.0) return;

targetSL = NormPrice(targetSL);

for(int i = PositionsTotal() - 1; i >= 0; i--)

{

ulong tk = PositionGetTicket(i);

if(!PositionSelectByTicket(tk)) continue;

if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

long type = PositionGetInteger(POSITION_TYPE);

if(dir == 1 && type != POSITION_TYPE_BUY) continue;

if(dir == -1 && type != POSITION_TYPE_SELL) continue;

double sl = PositionGetDouble(POSITION_SL);

double tp = PositionGetDouble(POSITION_TP);

bool improve = false;

if(dir == 1 && (sl == 0.0 || targetSL > sl)) improve = true;

if(dir == -1 && (sl == 0.0 || targetSL < sl)) improve = true;

if(improve)

trade.PositionModify(tk, targetSL, tp);

}

}

void RunnerScaleOut(const int dir, const double atr, const double distATR)

{

if(!InpUseRunnerScaleOut) return;

if(g_partialDone) return;

if(atr <= 0.0 || distATR < InpRunnerScaleOutAtATR) return;

if(CountPositions(dir) < InpRunnerScaleOutMinPositions) return;

if(BasketProfit() <= 0.0) return;

ulong ticketToClose = 0;

double weakestProfit = 1.0e100;

for(int i = PositionsTotal() - 1; i >= 0; i--)

{

ulong tk = PositionGetTicket(i);

if(!PositionSelectByTicket(tk)) continue;

if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

long type = PositionGetInteger(POSITION_TYPE);

if(dir == 1 && type != POSITION_TYPE_BUY) continue;

if(dir == -1 && type != POSITION_TYPE_SELL) continue;

double p = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

if(p > 0.0 && p < weakestProfit)

{

weakestProfit = p;

ticketToClose = tk;

}

}

if(ticketToClose > 0 && trade.PositionClose(ticketToClose))

{

g_partialDone = true;

g_status = "RUNNER_SCALE_OUT";

JournalEvent(g_status, StringFormat("closed_ticket=%I64u distATR=%.2f", ticketToClose, distATR));

}

}

void ManageBasket(SignalPack &sig)

{

int dir = BasketDirection();

if(dir == 0) return;

double atr = sig.atr;

if(atr <= 0.0) return;

ManageStops(atr);

BasketProfitLock();

if(CountPositions() <= 0) return;

double entry = WeightedEntry(dir);

if(entry <= 0.0) return;

if(InpBasketCashStopPct > 0.0 && BasketLossPct() >= InpBasketCashStopPct)

{

CloseAll();

g_status = "BASKET_CASH_STOP";

g_cooldownUntil = TimeCurrent() + InpCooldownAfterLossMinutes * 60;

g_basketPeakProfit = 0.0;

g_partialDone = false;

return;

}

double cur = (dir == 1 ? Bid() : Ask());

double dist = (dir == 1 ? cur - entry : entry - cur);

int n = CountPositions(dir);

BasketNetBreakEvenLock(dir, atr, dist);

double compressedTP = InpBasketTakeProfitATR - (MathMax(0, n - 1) * InpBasketTPCompression);

compressedTP = MathMax(0.28, compressedTP);

bool strongTrend = StrongTrend(sig, dir);

double targetTP = compressedTP;

if(InpUseDynamicTP && strongTrend)

targetTP = MathMax(targetTP, InpStrongTrendTPATR);

if(InpUseProfitTargetExtension && strongTrend)

{

if(dir == 1 && sig.buyScore >= InpProfitTargetExtensionScore) targetTP = MathMax(targetTP, InpStrongTrendTPATR * 1.35);

if(dir == -1 && sig.sellScore >= InpProfitTargetExtensionScore) targetTP = MathMax(targetTP, InpStrongTrendTPATR * 1.35);

}

targetTP = HyperTargetATR(sig, dir, targetTP);

datetime oldest = BasketOldestTime();

double distATR = dist / atr;

if(V16BadEntryScratchNeeded(sig, dir, distATR, oldest))

{

CloseAll();

g_status = "V16_BAD_ENTRY_SCRATCH";

DecisionLog(g_status);

g_cooldownUntil = TimeCurrent() + InpCooldownAfterLossMinutes * 60;

g_basketPeakProfit = 0.0;

g_partialDone = false;

g_runnerBestScore = 0.0;

g_runnerBestDistanceATR = 0.0;

return;

}

if(V17FailedMomentumCutNeeded(sig, dir, distATR, oldest))

{

CloseAll();

g_status = "V17_FAILED_MOMENTUM_CUT";

DecisionLog(g_status);

g_cooldownUntil = TimeCurrent() + InpCooldownAfterLossMinutes * 60;

g_basketPeakProfit = 0.0;

g_partialDone = false;

g_runnerBestScore = 0.0;

g_runnerBestDistanceATR = 0.0;

g_v17BasketMFEATR = 0.0;

return;

}

if(FastLoserCutNeeded(sig, dir, distATR, oldest))

{

CloseAll();

g_status = "FAST_LOSER_CUT";

DecisionLog(g_status);

g_cooldownUntil = TimeCurrent() + InpCooldownAfterLossMinutes * 60;

g_basketPeakProfit = 0.0;

g_partialDone = false;

g_runnerBestScore = 0.0;

g_runnerBestDistanceATR = 0.0;

return;

}

TryPartialClose(dir, atr, dist);

TryWinnerAdd(dir, sig, atr, dist);

RunnerScaleOut(dir, atr, distATR);

g_v17BasketMFEATR = MathMax(g_v17BasketMFEATR, distATR);

V14RunnerMFEGuard(sig, dir);

V15ProfitStaircase(sig, dir);

V16ApexHighWaterLock(sig, dir);

V17RunnerProfitElasticity(sig, dir);

if(CountPositions() <= 0) return;

if(dist >= atr * targetTP)

{

bool holdRunner = (InpUseProfitExpansion && InpUseRunnerMode && (strongTrend || MegaTrend(sig, dir) || V15ExceptionalRunnerHold(sig, dir) || V16ApexRunnerHold(sig, dir) || V17ApexContinuation(sig, dir)));

if(holdRunner && BasketProfitPct() < InpAbsoluteMaxBasketProfitPct)

{

g_status = "HYPER_RUNNER_HOLD";

}

else

{

CloseAll();

g_status = "BASKET_TP";

g_basketPeakProfit = 0.0;

g_partialDone = false;

g_runnerBestScore = 0.0;

g_runnerBestDistanceATR = 0.0;

return;

}

}

if(RunnerExhausted(sig, dir, distATR) && !V16ApexRunnerHold(sig, dir) && !V17ApexContinuation(sig, dir))

{

CloseAll();

g_status = "RUNNER_EXHAUSTION_CLOSE";

DecisionLog(g_status);

g_basketPeakProfit = 0.0;

g_partialDone = false;

g_runnerBestScore = 0.0;

g_runnerBestDistanceATR = 0.0;

return;

}

if(dist <= -atr * InpEmergencyStopATR)

{

CloseAll();

g_status = "EMERGENCY_ATR_CLOSE";

g_cooldownUntil = TimeCurrent() + InpCooldownAfterLossMinutes * 60;

g_basketPeakProfit = 0.0;

g_partialDone = false;

return;

}

if(InpCloseBasketOnOpposite)

{

if(dir == 1 && sig.sellScore >= InpOppositeScoreToClose)

{

CloseAll();

g_status = "OPPOSITE_CLOSE";

return;

}

if(dir == -1 && sig.buyScore >= InpOppositeScoreToClose)

{

CloseAll();

g_status = "OPPOSITE_CLOSE";

return;

}

}

if(InpCloseStaleBasketIfProfit && oldest > 0 && (TimeCurrent() - oldest) > InpMaxBasketMinutes * 60 && BasketProfit() >= 0.0)

{

CloseAll();

g_status = "STALE_PROFIT_CLOSE";

return;

}

if(InpCloseStaleLossBasket && oldest > 0 && (TimeCurrent() - oldest) > InpMaxLosingBasketMinutes * 60 && BasketLossPct() >= InpMaxStaleBasketLossPct)

{

CloseAll();

g_status = "STALE_LOSS_CUT";

DecisionLog(g_status);

g_cooldownUntil = TimeCurrent() + InpCooldownAfterLossMinutes * 60;

return;

}

if(InpUseHardBasketTimeStop && oldest > 0 && (TimeCurrent() - oldest) > InpHardMaxBasketMinutes * 60 && BasketLossPct() >= InpHardTimeStopLossPct)

{

CloseAll();

g_status = "HARD_TIME_STOP";

DecisionLog(g_status);

g_cooldownUntil = TimeCurrent() + InpCooldownAfterLossMinutes * 60;

return;

}

if(InpUseSignalDecayExit)

{

if(dir == 1 && sig.buyScore <= InpWeakSameDirectionScore && BasketProfit() < 0.0)

{

CloseAll();

g_status = "BUY_SIGNAL_DECAY_EXIT";

DecisionLog(g_status);

g_cooldownUntil = TimeCurrent() + InpCooldownAfterLossMinutes * 60;

return;

}

if(dir == -1 && sig.sellScore <= InpWeakSameDirectionScore && BasketProfit() < 0.0)

{

CloseAll();

g_status = "SELL_SIGNAL_DECAY_EXIT";

DecisionLog(g_status);

g_cooldownUntil = TimeCurrent() + InpCooldownAfterLossMinutes * 60;

return;

}

}

if(InpUseScoreDivergenceExit && BasketProfit() < 0.0)

{

if(dir == 1 && sig.sellScore > sig.buyScore + InpScoreDivergenceCloseGap)

{

CloseAll();

g_status = "BUY_SCORE_DIVERGENCE_EXIT";

DecisionLog(g_status);

g_cooldownUntil = TimeCurrent() + InpCooldownAfterLossMinutes * 60;

return;

}

if(dir == -1 && sig.buyScore > sig.sellScore + InpScoreDivergenceCloseGap)

{

CloseAll();

g_status = "SELL_SCORE_DIVERGENCE_EXIT";

DecisionLog(g_status);

g_cooldownUntil = TimeCurrent() + InpCooldownAfterLossMinutes * 60;

return;

}

}

if(InpUseBasketTimeProfitExit && oldest > 0 && (TimeCurrent() - oldest) > InpBasketTimeProfitMinutes * 60)

{

double minTimedProfit = AccountInfoDouble(ACCOUNT_EQUITY) * InpMinTimedExitProfitPct / 100.0;

if(BasketProfit() >= minTimedProfit)

{

CloseAll();

g_status = "TIMED_PROFIT_EXIT";

DecisionLog(g_status);

return;

}

}

if(InpUseRunnerMode && oldest > 0 && (TimeCurrent() - oldest) > InpMaxRunnerMinutes * 60 && BasketProfit() > 0.0)

{

bool weakTimeout = (DirectionScore(sig, dir) <= DynamicMinScore() - InpRunnerTimeoutWeakScoreBuffer || !StrongTrend(sig, dir));

if(!InpUseRunnerTimeoutOnlyIfWeak || weakTimeout)

{

CloseAll();

g_status = "MAX_RUNNER_TIME_EXIT";

DecisionLog(g_status);

return;

}

g_status = "RUNNER_TIME_HOLD_STRONG";

}

if(InpCloseRunnerOnSessionEnd && !SessionOK() && BasketProfit() > 0.0)

{

CloseAll();

g_status = "SESSION_END_PROFIT_EXIT";

DecisionLog(g_status);

return;

}

if(n >= InpMaxGridPositions) return;

if(!GridPermissionOK(dir, sig)) return;

double last = LastEntryPrice(dir);

if(last <= 0.0) return;

double needed = atr * InpGridStepATR * MathPow(InpGridStepExpansion, n - 1);

bool adverse = (dir == 1 && Bid() <= last - needed) || (dir == -1 && Ask() >= last + needed);

if(adverse)

OpenTrade(dir, atr, n);

}

void AccountGuard()

{

ResetDayIfNeeded();

if(WeekendFlatTime() && CountPositions() > 0)

{

CloseAll();

g_status = "WEEKEND_FLAT";

g_cooldownUntil = TimeCurrent() + InpCooldownAfterDDMinutes * 60;

return;

}

if(InpCloseAtDailyProfitTarget && InpCapitalProtectionMode && DailyProfitPct() >= InpDailyProfitTargetPercent)

{

if(InpUseDailyProfitUnlock && DailyProfitPct() < InpUnlockedMaxDailyProfitPct && PeakDDPct() < InpHalfRiskAtDDPercent)

{

g_status = "DAILY_PROFIT_UNLOCK";

}

else

{

if(CountPositions() > 0) CloseAll();

g_cooldownUntil = TimeCurrent() + InpCooldownAfterDDMinutes * 60;

g_status = "DAILY_TARGET_FLAT";

return;

}

}

if(InpUseDailyEquityTrail && g_dayStartEquity > 0.0 && g_dayPeakEquity > g_dayStartEquity)

{

double peakPct = DailyPeakProfitPct();

double currentPct = DailyProfitPct();

double retainPct = peakPct * InpDailyEquityTrailRetainPct / 100.0;

if(peakPct >= InpDailyEquityTrailStartPct && currentPct <= retainPct)

{

if(CountPositions() > 0) CloseAll();

g_cooldownUntil = TimeCurrent() + InpCooldownAfterDDMinutes * 60;

g_status = "DAILY_EQUITY_TRAIL_LOCK";

JournalEvent(g_status, StringFormat("peak=%.2f current=%.2f retain=%.2f", peakPct, currentPct, retainPct));

return;

}

}

if(InpUseWeeklyProtection)

{

double weekLoss = WeeklyLossPct();

double weekPeak = WeeklyPeakProfitPct();

double weekNow = WeeklyProfitPct();

if(weekLoss >= InpWeeklyLossStopPct)

{

if(CountPositions() > 0) CloseAll();

g_cooldownUntil = TimeCurrent() + InpCooldownAfterDDMinutes * 60;

g_status = "WEEKLY_LOSS_STOP";

return;

}

if(weekPeak >= InpWeeklyProfitVaultPct && weekNow <= weekPeak * InpWeeklyProfitRetainPct / 100.0)

{

if(CountPositions() > 0) CloseAll();

g_cooldownUntil = TimeCurrent() + InpCooldownAfterDDMinutes * 60;

g_status = "WEEKLY_PROFIT_VAULT";

return;

}

}

if(InpUseAlphaHarvestEngine && InpUseTrendVault && DailyPeakProfitPct() >= InpTrendVaultStartPct)

{

double retained = DailyPeakProfitPct() * InpTrendVaultRetainPct / 100.0;

if(DailyProfitPct() <= retained)

{

if(CountPositions() > 0) CloseAll();

g_cooldownUntil = TimeCurrent() + InpCooldownAfterDDMinutes * 60;

g_status = "TREND_VAULT_LOCK";

return;

}

}

double dd = PeakDDPct();

double dl = DailyLossPct();

if(InpUseEquityCurvePause && CountPositions() == 0 && dd >= InpSoftDDPausePercent)

{

g_cooldownUntil = TimeCurrent() + InpSoftDDPauseMinutes * 60;

g_status = "SOFT_DD_PAUSE";

}

if(dd >= InpHardStopEquityDDPercent || dl >= InpMaxDailyLossPercent * 1.50)

{

if(InpCloseAllOnHardDD && CountPositions() != 0) CloseAll();

g_cooldownUntil = TimeCurrent() + InpCooldownAfterDDMinutes * 60;

g_status = "HARD_RISK_STOP";

g_basketPeakProfit = 0.0;

g_partialDone = false;

}

}

void Dashboard(const SignalPack &sig)

{

if(!InpShowDashboard) return;

string txt = "QQ XAU GRID PRO V16 10K APEXCOMPOUND\n";

txt += "Symbol: " + _Symbol + " | TF: " + EnumToString(InpSignalTF) + " | Regime: " + sig.regime + "\n";

txt += "Status: " + g_status + "\n";

txt += "BuyScore: " + DoubleToString(sig.buyScore, 1) + " | SellScore: " + DoubleToString(sig.sellScore, 1) + " | Dir: " + IntegerToString(sig.direction) + "\n";

txt += "ADX: " + DoubleToString(sig.adx, 1) + " | ATR%: " + DoubleToString(sig.atrPct, 3) + " | Eff: " + DoubleToString(sig.efficiency, 2) + " | Spread: " + DoubleToString(SpreadPts(), 1) + "\n";

txt += "RangeATR: " + DoubleToString(sig.candleRangeATR, 2) + " | GapATR: " + DoubleToString(sig.gapATR, 2) + " | SlopeATR: " + DoubleToString(sig.emaSlopeATR, 3) + " | ATRx: " + DoubleToString(sig.atrAcceleration, 2) + " | SQ: " + IntegerToString(sig.sessionQuality) + "\n";

txt += "Profile: " + IntegerToString(InpStrategyProfile) + " | ScoreGap: " + DoubleToString(sig.scoreGap, 1) + " | LiqDist H/L ATR: " + DoubleToString(sig.distanceToRecentHighATR, 2) + "/" + DoubleToString(sig.distanceToRecentLowATR, 2) + " | DayPeak%: " + DoubleToString(DailyPeakProfitPct(), 2) + "\n";

txt += "Confirm B/S: " + (sig.buyConfirmed ? "Y" : "N") + "/" + (sig.sellConfirmed ? "Y" : "N") + " | SpreadEMA: " + DoubleToString(g_spreadEma, 1) + " | SpreadSpikeOK: " + (SpreadSpikeOK() ? "Y" : "N") + "\n";

txt += "VWAP: " + DoubleToString(sig.vwap, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) + " | Pos: " + IntegerToString(CountPositions()) + " | Lots: " + DoubleToString(TotalLots(), 2) + "/" + DoubleToString(EffectiveMaxTotalLots(), 2) + " | 10K lot band: " + (InpForceTenKLotBand ? "ON" : "OFF") + "\n";

txt += "Basket P/L: " + DoubleToString(BasketProfit(), 2) + " | PeakBasket: " + DoubleToString(g_basketPeakProfit, 2) + "\n";

txt += "DailyLoss%: " + DoubleToString(DailyLossPct(), 2) + " | DailyProfit%: " + DoubleToString(DailyProfitPct(), 2) + " | PeakDD%: " + DoubleToString(PeakDDPct(), 2) + "\n";

txt += "DynScore: " + DoubleToString(DynamicMinScore(), 1) + " | EMAextATR: " + DoubleToString(sig.distanceFromSignalEMAATR, 2) + " | LossBaskets: " + IntegerToString(g_consecutiveLossBaskets) + " | EntriesToday: " + IntegerToString(g_entriesToday) + "\n";

txt += "V16 10K ApexCompound: " + (InpUseAlphaHarvestEngine ? "ON" : "OFF") + " | AddWinner: " + (InpUseAddToWinner ? "ON" : "OFF") + " | Strong B/S: " + (StrongTrend(sig, 1) ? "Y" : "N") + "/" + (StrongTrend(sig, -1) ? "Y" : "N") + " | Alpha B/S: " + (AlphaTrend(sig, 1) ? "Y" : "N") + "/" + (AlphaTrend(sig, -1) ? "Y" : "N") + " | Explosive B/S: " + (ExplosiveTrend(sig, 1) ? "Y" : "N") + "/" + (ExplosiveTrend(sig, -1) ? "Y" : "N") + "\n";

txt += "Basket%: " + DoubleToString(BasketProfitPct(), 2) + " | Week P/L%: " + DoubleToString(WeeklyProfitPct() - WeeklyLossPct(), 2) + " | WeekPeak%: " + DoubleToString(WeeklyPeakProfitPct(), 2) + " | RunnerBestScore: " + DoubleToString(g_runnerBestScore, 1) + " | RunnerBestATR: " + DoubleToString(g_runnerBestDistanceATR, 2) + " | LastAdd: " + TimeToString(g_lastWinnerAdd, TIME_MINUTES) + "\n";

txt += "V14 Gate: " + (InpUseV14ConvictionGate ? "ON" : "OFF") + " | ShockPauseUntil: " + TimeToString(g_v14ShockPauseUntil, TIME_MINUTES) + " | AddQuality: " + (InpUseV14AddQualityGate ? "ON" : "OFF") + " | MFEGuard: " + (InpUseV14RunnerMFEGuard ? "ON" : "OFF") + "\n";

txt += "V15 EliteGate: " + (InpUseV15EliteProfitGate ? "ON" : "OFF") + " | Elite B/S: " + (V15EliteTrend(sig, 1) ? "Y" : "N") + "/" + (V15EliteTrend(sig, -1) ? "Y" : "N") + " | ExceptionalHold B/S: " + (V15ExceptionalRunnerHold(sig, 1) ? "Y" : "N") + "/" + (V15ExceptionalRunnerHold(sig, -1) ? "Y" : "N") + " | Staircase: " + (InpV15UseProfitStaircase ? "ON" : "OFF") + "\n";

txt += "V16 Apex: " + (InpUseV16ApexCompoundEngine ? "ON" : "OFF") + " | Apex B/S: " + (V16ApexTrend(sig, 1) ? "Y" : "N") + "/" + (V16ApexTrend(sig, -1) ? "Y" : "N") + " | ApexHold B/S: " + (V16ApexRunnerHold(sig, 1) ? "Y" : "N") + "/" + (V16ApexRunnerHold(sig, -1) ? "Y" : "N") + " | HWLock: " + (InpV16UseApexHighWaterLock ? "ON" : "OFF") + "\n";

Comment(txt);

}

//-------------------- MT5 events --------------------

int OnInit()

{

if(!SymbolOK())

Print("Warning: attach EA to ", InpTradeSymbol, " chart. Current: ", _Symbol);

if(InpTradeDirectionMode < -1 || InpTradeDirectionMode > 1)

{

Print("InpTradeDirectionMode must be -1, 0, or 1.");

return INIT_PARAMETERS_INCORRECT;

}

if(InpStrategyProfile < 0 || InpStrategyProfile > 3)

{

Print("InpStrategyProfile must be 0, 1, 2, or 3.");

return INIT_PARAMETERS_INCORRECT;

}

if(InpConfirmBars < 1 || InpConfirmBars > 5)

{

Print("InpConfirmBars must be between 1 and 5.");

return INIT_PARAMETERS_INCORRECT;

}

if(InpForceTenKLotBand)

{

if(InpCapitalReference < 5000.0 || InpCapitalReference > 20000.0)

{

Print("InpCapitalReference should stay near 10000 for this V16 profile.");

return INIT_PARAMETERS_INCORRECT;

}

if(InpMinAllowedLot < 0.01 || InpMaxAllowedSingleLot > 0.04 || InpMaxAllowedTotalLots > 0.04 || InpMaxAllowedTotalLots < InpMinAllowedLot)

{

Print("V16 10K lot band requires min lot >=0.01, max single <=0.04, max total <=0.04.");

return INIT_PARAMETERS_INCORRECT;

}

}

if(InpMaxWinnerAdds < 0 || InpMaxWinnerAdds > 3)

{

Print("InpMaxWinnerAdds must be between 0 and 3.");

return INIT_PARAMETERS_INCORRECT;

}

if(InpWinnerAddLotMultiplier < 0.05 || InpWinnerAddLotMultiplier > 1.0)

{

Print("InpWinnerAddLotMultiplier must be between 0.05 and 1.0.");

return INIT_PARAMETERS_INCORRECT;

}

if(InpRequireHedgingAccount)

{

long mode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);

if(mode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)

{

Print("This EA is configured to require a hedging account. Current margin mode is not retail hedging.");

return INIT_FAILED;

}

}

hFast = iMA(_Symbol, InpTrendTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);

hSlow = iMA(_Symbol, InpTrendTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);

hMacro = iMA(_Symbol, InpMacroTF, InpMacroEMA, 0, MODE_EMA, PRICE_CLOSE);

hSignalEMA = iMA(_Symbol, InpSignalTF, InpSignalEMA, 0, MODE_EMA, PRICE_CLOSE);

hRSI = iRSI(_Symbol, InpSignalTF, InpRSIPeriod, PRICE_CLOSE);

hADX = iADX(_Symbol, InpSignalTF, InpADXPeriod);

hATR = iATR(_Symbol, InpSignalTF, InpATRPeriod);

hBands = iBands(_Symbol, InpSignalTF, InpBandsPeriod, 0, InpBandsDeviation, PRICE_CLOSE);

if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hMacro == INVALID_HANDLE || hSignalEMA == INVALID_HANDLE ||

hRSI == INVALID_HANDLE || hADX == INVALID_HANDLE || hATR == INVALID_HANDLE || hBands == INVALID_HANDLE)

{

Print("Indicator handle creation failed.");

return INIT_FAILED;

}

trade.SetExpertMagicNumber(InpMagic);

trade.SetDeviationInPoints(InpDeviationPoints);

trade.SetTypeFillingBySymbol(_Symbol);

g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);

g_dayPeakEquity = g_peakEquity;

ResetDayIfNeeded();

ResetWeekIfNeeded();

g_status = "READY";

return INIT_SUCCEEDED;

}

void OnDeinit(const int reason)

{

if(hFast != INVALID_HANDLE) IndicatorRelease(hFast);

if(hSlow != INVALID_HANDLE) IndicatorRelease(hSlow);

if(hMacro != INVALID_HANDLE) IndicatorRelease(hMacro);

if(hSignalEMA != INVALID_HANDLE) IndicatorRelease(hSignalEMA);

if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);

if(hADX != INVALID_HANDLE) IndicatorRelease(hADX);

if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);

if(hBands != INVALID_HANDLE) IndicatorRelease(hBands);

Comment("");

}

void OnTick()

{

UpdateSpreadEma();

ResetDayIfNeeded();

AccountGuard();

SignalPack sig;

if(!BuildSignal(sig))

{

g_status = "SIGNAL_ERROR";

return;

}

Dashboard(sig);

if(CountPositions() > 0)

ManageBasket(sig);

AccountGuard();

if(InpOneDecisionPerBar && !NewBar()) return;

if(CountPositions() > 0) return;

g_basketPeakProfit = 0.0;

g_partialDone = false;

g_runnerBestScore = 0.0;

g_runnerBestDistanceATR = 0.0;

g_v17BasketMFEATR = 0.0;

if(!BaseFiltersOK(sig)) return;

if(sig.direction == 0)

{

g_status = "NO_SIGNAL";

DecisionLog(g_status + " buy=" + DoubleToString(sig.buyScore, 1) + " sell=" + DoubleToString(sig.sellScore, 1));

return;

}

if(OpenTrade(sig.direction, sig.atr, 0))

DecisionLog("OPEN " + (sig.direction == 1 ? "BUY" : "SELL") + " buyScore=" + DoubleToString(sig.buyScore, 1) + " sellScore=" + DoubleToString(sig.sellScore, 1));

}
