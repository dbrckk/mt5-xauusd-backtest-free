//+------------------------------------------------------------------+
//| XAUUSD_Master_V21_EA_PUBLIC.mq5                                  |
//| Pine conversion: EMA 9/21 cross + EMA200 + RSI + volume + session |
//| TP = 2.0 ATR, SL = 1.5 ATR.                                      |
//+------------------------------------------------------------------+
#property strict
#property version "21.01"
#property description "XAUUSD Master V21 Pine-to-MT5 EA for public MT5 backtests."

input string InpTradeSymbol = "XAUUSD";
input ulong InpMagic = 26062921;
input ENUM_TIMEFRAMES InpSignalTF = PERIOD_M15;
input double InpFixedLot = 0.01;

input int InpFastEMAPeriod = 9;
input int InpSlowEMAPeriod = 21;
input int InpTrendEMAPeriod = 200;
input int InpRSIPeriod = 14;
input int InpATRPeriod = 14;
input int InpVolumeSMAPeriod = 20;

input double InpVolumeMultiplier = 0.80;
input double InpLongRSIMin = 50.0;
input double InpLongRSIMax = 68.0;
input double InpShortRSIMax = 50.0;
input double InpShortRSIMin = 32.0;
input double InpTP_ATR_Multiplier = 2.0;
input double InpSL_ATR_Multiplier = 1.5;

input bool InpUseSessionFilter = true;
input int InpSessionStartHour = 8;
input int InpSessionEndHour = 21;
input bool InpMondayToFridayOnly = true;

input bool InpOnlyOnePosition = true;
input bool InpCloseOnOppositeSignal = true;
input int InpMinMinutesBetweenEntries = 120;
input int InpMaxNewEntriesPerDay = 5;
input double InpMaxSpreadPoints = 28.0;
input int InpDeviationPoints = 30;
input bool InpUseCSVJournal = false;
input string InpCSVJournalName = "XAUUSD_Master_V21_journal.csv";
input bool InpVerboseLog = false;
input bool InpVerboseDecisionLog = false;

// Compatibility inputs used by the existing GitHub Actions runner/set files.
input int InpStrategyProfile = 0;
input bool InpUseRiskLot = false;
input bool InpForceTenKLotBand = true;
input double InpMaxAllowedSingleLot = 0.04;
input double InpMaxAllowedTotalLots = 0.04;
input double InpMaxTotalLots = 0.04;
input bool InpRiskThrottleOnDD = true;
input bool InpCapitalProtectionMode = true;
input double InpMinFreeMarginAfterTradePct = 65.0;
input bool InpUseDynamicScoreThreshold = true;
input double InpMinScoreToEnter = 95.0;
input double InpMinScoreGap = 24.0;
input double InpMinADX = 20.0;
input double InpMaxADX = 48.0;
input double InpMinATRPct = 0.045;
input double InpMaxATRPct = 0.500;
input double InpMinRangeEfficiency = 0.28;
input bool InpRequireMacroAlignment = true;
input bool InpAvoidDoji = true;
input bool InpUseVWAPFilter = true;
input bool InpUseSMCStructureScore = true;
input bool InpRejectLargeWickAgainstTrade = true;
input bool InpUseVolatilityShockFilter = true;
input bool InpUseTrendSlopeFilter = true;
input bool InpUseConsecutiveCloseFilter = true;
input bool InpUseAdaptiveGridStop = true;
input bool InpUseEquityCurvePause = true;
input bool InpUseATRAccelerationFilter = true;
input bool InpUseSessionQualityFilter = true;
input bool InpBlockAsianSession = true;
input bool InpUseSpreadSpikeFilter = true;
input bool InpCloseAtDailyProfitTarget = true;
input bool InpUseHardBasketTimeStop = true;
input bool InpUseSignalDecayExit = true;
input bool InpUseATRNormalizedSpread = true;
input bool InpUseLiquidityDistanceFilter = true;
input bool InpUseEntryScoreDecayBlock = true;
input bool InpUseV14ConvictionGate = true;
input double InpV14MinEntryScore = 96.0;
input double InpV14MinEntryGap = 26.0;
input bool InpV14RequireAlphaOrExplosive = true;
input bool InpUseV14ShockPause = true;
input bool InpUseV15EliteProfitGate = true;
input bool InpV15RequireEliteTrend = true;
input bool InpUseV16ApexCompoundEngine = true;
input bool InpV16RequireConfirmedClose = true;
input bool InpV16RequireApexTrend = true;
input bool InpUseV17ProfitAsymmetry = true;
input bool InpV17BlockThreeBarReversal = true;
input bool InpUseAlphaHarvestEngine = true;
input bool InpUseAmbiguityPenalty = true;
input bool InpUseWeeklyProtection = true;
input ENUM_TIMEFRAMES InpMacroTF = PERIOD_H1;
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H1;
input int InpSlowEMA = 34;
input int InpMacroEMA = 34;
input int InpSignalEMA = 20;
input bool InpOneDecisionPerBar = false;
input int InpStartHourServer = 8;
input int InpEndHourServer = 17;
input int InpLondonStartHourServer = 8;
input int InpLondonEndHourServer = 12;
input int InpNYStartHourServer = 13;
input int InpNYEndHourServer = 17;
input double InpMaxATRAccelerationRatio = 9.99;
input bool InpUseBasketTimeProfitExit = false;
input int InpBasketTimeProfitMinutes = 180;
input double InpMinTimedExitProfitPct = 0.20;
input bool InpUseScoreDivergenceExit = false;
input bool InpCloseOnRunnerExhaustion = false;
input bool InpUseFastLoserCut = false;
input bool InpUseEarlyBadTradeAbort = false;
input bool InpCloseStaleLossBasket = false;
input bool InpCloseStaleBasketIfProfit = false;
input bool InpUseBasketProfitLock = false;
input bool InpUseBreakEven = false;
input bool InpUseTrailing = false;
input bool InpUseBasketNetBreakEvenLock = false;
input bool InpUseV14RunnerMFEGuard = false;
input bool InpUseV17RunnerProfitElasticity = false;

/*
Compatibility marker block for scripts/run-public-history-backtest.ps1.
The runner replaces these exact strings before compiling the EA.
input string InpTradeSymbol = "XAUUSD";
input bool InpForceTenKLotBand = true;
input double InpMaxAllowedSingleLot = 0.04;
input double InpMaxAllowedTotalLots = 0.04;
input double InpMaxTotalLots = 0.04;
input bool InpRiskThrottleOnDD = true;
input bool InpCapitalProtectionMode = true;
input double InpMinFreeMarginAfterTradePct = 65.0;
input bool InpUseDynamicScoreThreshold = true;
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
input bool InpUseVWAPFilter = true;
input bool InpUseSMCStructureScore = true;
input bool InpRejectLargeWickAgainstTrade = true;
input bool InpUseVolatilityShockFilter = true;
input bool InpUseTrendSlopeFilter = true;
input bool InpUseConsecutiveCloseFilter = true;
input bool InpUseAdaptiveGridStop = true;
input bool InpUseEquityCurvePause = true;
input bool InpUseATRAccelerationFilter = true;
input bool InpUseSessionQualityFilter = true;
input bool InpBlockAsianSession = true;
input bool InpUseSpreadSpikeFilter = true;
input bool InpCloseAtDailyProfitTarget = true;
input bool InpUseHardBasketTimeStop = true;
input bool InpUseSignalDecayExit = true;
input bool InpUseATRNormalizedSpread = true;
input bool InpUseLiquidityDistanceFilter = true;
input bool InpUseEntryScoreDecayBlock = true;
input bool InpUseV14ConvictionGate = true;
input double InpV14MinEntryScore = 96.0;
input double InpV14MinEntryGap = 26.0;
input bool InpV14RequireAlphaOrExplosive = true;
input bool InpUseV14ShockPause = true;
input bool InpUseV15EliteProfitGate = true;
input bool InpV15RequireEliteTrend = true;
input bool InpUseV16ApexCompoundEngine = true;
input bool InpV16RequireConfirmedClose = true;
input bool InpV16RequireApexTrend = true;
input bool InpUseV17ProfitAsymmetry = true;
input bool InpV17BlockThreeBarReversal = true;
input bool InpUseAlphaHarvestEngine = true;
input bool InpUseAmbiguityPenalty = true;
input bool InpUseWeeklyProtection = true;
input bool InpUseCSVJournal = false;
input bool InpVerboseLog = false;
*/

string g_symbol = "";
datetime g_lastBarTime = 0;
datetime g_lastEntryTime = 0;
int g_dayKey = 0;
int g_entriesToday = 0;
int hFast = INVALID_HANDLE;
int hSlow = INVALID_HANDLE;
int hTrend = INVALID_HANDLE;
int hRSI = INVALID_HANDLE;
int hATR = INVALID_HANDLE;

string ActiveSymbol()
{
   if(StringLen(InpTradeSymbol) > 0) return InpTradeSymbol;
   return _Symbol;
}

int CurrentDayKey(datetime t)
{
   MqlDateTime d;
   TimeToStruct(t, d);
   return d.year * 10000 + d.mon * 100 + d.day;
}

void ResetDayCounter()
{
   int k = CurrentDayKey(TimeCurrent());
   if(k != g_dayKey)
   {
      g_dayKey = k;
      g_entriesToday = 0;
   }
}

void Journal(string eventName, string details)
{
   if(!InpUseCSVJournal) return;
   int file = FileOpen(InpCSVJournalName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON, ';');
   if(file == INVALID_HANDLE) return;
   FileSeek(file, 0, SEEK_END);
   FileWrite(file, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), g_symbol, eventName, details);
   FileClose(file);
}

void DebugLog(string text)
{
   if(InpVerboseLog || InpVerboseDecisionLog) Print(text);
}

bool Ready()
{
   if(g_symbol == "") g_symbol = ActiveSymbol();
   if(!SymbolSelect(g_symbol, true)) return false;
   int requiredBars = MathMax(InpTrendEMAPeriod, MathMax(InpVolumeSMAPeriod, MathMax(InpRSIPeriod, InpATRPeriod))) + 10;
   return iBars(g_symbol, InpSignalTF) >= requiredBars;
}

bool NewBar()
{
   datetime t = iTime(g_symbol, InpSignalTF, 0);
   if(t <= 0 || t == g_lastBarTime) return false;
   g_lastBarTime = t;
   return true;
}

bool BufferValue(int handle, int shift, double &value)
{
   double data[];
   ArraySetAsSeries(data, true);
   if(handle == INVALID_HANDLE) return false;
   if(CopyBuffer(handle, 0, shift, 1, data) != 1) return false;
   value = data[0];
   return true;
}

bool ClosedBar(MqlRates &bar)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(g_symbol, InpSignalTF, 1, 1, rates) != 1) return false;
   bar = rates[0];
   return true;
}

bool SessionOK()
{
   if(!InpUseSessionFilter) return true;
   datetime t = iTime(g_symbol, InpSignalTF, 1);
   if(t <= 0) return false;
   MqlDateTime d;
   TimeToStruct(t, d);
   if(InpMondayToFridayOnly && (d.day_of_week == 0 || d.day_of_week == 6)) return false;
   return d.hour >= InpSessionStartHour && d.hour < InpSessionEndHour;
}

bool VolumeOK()
{
   if(InpVolumeSMAPeriod <= 1) return true;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(g_symbol, InpSignalTF, 1, InpVolumeSMAPeriod, rates);
   if(copied < InpVolumeSMAPeriod) return false;
   double sum = 0.0;
   for(int i = 0; i < copied; i++) sum += (double)rates[i].tick_volume;
   return (double)rates[0].tick_volume > (sum / (double)copied) * InpVolumeMultiplier;
}

bool SpreadOK()
{
   if(InpMaxSpreadPoints <= 0.0) return true;
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   if(ask <= 0.0 || bid <= 0.0 || point <= 0.0) return true;
   return (ask - bid) / point <= InpMaxSpreadPoints;
}

int CountPositions(int direction = 0)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(direction > 0 && type != POSITION_TYPE_BUY) continue;
      if(direction < 0 && type != POSITION_TYPE_SELL) continue;
      count++;
   }
   return count;
}

double NormalizedLot()
{
   double volume = InpFixedLot;
   double minLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   if(stepLot > 0.0) volume = MathFloor(volume / stepLot + 0.0000001) * stepLot;
   if(minLot > 0.0) volume = MathMax(volume, minLot);
   if(maxLot > 0.0) volume = MathMin(volume, maxLot);
   return NormalizeDouble(volume, 2);
}

bool CloseTicket(ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return false;
   long positionType = PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick)) return false;

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = g_symbol;
   request.magic = InpMagic;
   request.volume = volume;
   request.type = (positionType == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   request.price = (positionType == POSITION_TYPE_BUY ? tick.bid : tick.ask);
   request.deviation = InpDeviationPoints;
   request.type_filling = ORDER_FILLING_FOK;
   request.type_time = ORDER_TIME_GTC;
   request.comment = "Master V21 close";

   bool ok = OrderSend(request, result);
   Journal(ok ? "CLOSE" : "CLOSE_FAIL", StringFormat("ticket=%I64u retcode=%u", ticket, result.retcode));
   return ok && (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL || result.retcode == TRADE_RETCODE_PLACED);
}

void CloseOppositePositions(int signalDirection)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(signalDirection > 0 && type == POSITION_TYPE_SELL) CloseTicket(ticket);
      if(signalDirection < 0 && type == POSITION_TYPE_BUY) CloseTicket(ticket);
   }
}

bool OpenMarketOrder(int direction, double atr)
{
   if(direction == 0 || atr <= 0.0) return false;
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick)) return false;

   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   double minDistance = MathMax((double)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point, point);
   double price = (direction > 0 ? tick.ask : tick.bid);
   double sl = (direction > 0 ? price - atr * InpSL_ATR_Multiplier : price + atr * InpSL_ATR_Multiplier);
   double tp = (direction > 0 ? price + atr * InpTP_ATR_Multiplier : price - atr * InpTP_ATR_Multiplier);

   if(direction > 0)
   {
      if(price - sl < minDistance) sl = price - minDistance;
      if(tp - price < minDistance) tp = price + minDistance;
   }
   else
   {
      if(sl - price < minDistance) sl = price + minDistance;
      if(price - tp < minDistance) tp = price - minDistance;
   }

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = g_symbol;
   request.magic = InpMagic;
   request.volume = NormalizedLot();
   request.type = (direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   request.price = NormalizeDouble(price, digits);
   request.sl = NormalizeDouble(sl, digits);
   request.tp = NormalizeDouble(tp, digits);
   request.deviation = InpDeviationPoints;
   request.type_filling = ORDER_FILLING_FOK;
   request.type_time = ORDER_TIME_GTC;
   request.comment = (direction > 0 ? "Master V21 BUY" : "Master V21 SELL");

   bool ok = OrderSend(request, result);
   string side = (direction > 0 ? "BUY" : "SELL");
   Journal(ok ? "OPEN" : "OPEN_FAIL", StringFormat("%s retcode=%u price=%.5f sl=%.5f tp=%.5f atr=%.5f", side, result.retcode, request.price, request.sl, request.tp, atr));
   DebugLog(StringFormat("%s retcode=%u", side, result.retcode));

   if(ok && (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL || result.retcode == TRADE_RETCODE_PLACED))
   {
      g_lastEntryTime = TimeCurrent();
      g_entriesToday++;
      return true;
   }
   return false;
}

int Signal(double &atr)
{
   atr = 0.0;
   if(!SessionOK() || !VolumeOK()) return 0;

   double fast1, fast2, slow1, slow2, ema200, rsi, atrValue;
   if(!BufferValue(hFast, 1, fast1) || !BufferValue(hFast, 2, fast2)) return 0;
   if(!BufferValue(hSlow, 1, slow1) || !BufferValue(hSlow, 2, slow2)) return 0;
   if(!BufferValue(hTrend, 1, ema200) || !BufferValue(hRSI, 1, rsi) || !BufferValue(hATR, 1, atrValue)) return 0;

   MqlRates bar;
   if(!ClosedBar(bar)) return 0;

   bool longSignal = fast1 > slow1 && fast2 <= slow2 && bar.close > ema200 && rsi > InpLongRSIMin && rsi < InpLongRSIMax;
   bool shortSignal = fast1 < slow1 && fast2 >= slow2 && bar.close < ema200 && rsi < InpShortRSIMax && rsi > InpShortRSIMin;

   if(longSignal)
   {
      atr = atrValue;
      Journal("SIGNAL", StringFormat("BUY close=%.5f rsi=%.2f atr=%.5f", bar.close, rsi, atrValue));
      return 1;
   }
   if(shortSignal)
   {
      atr = atrValue;
      Journal("SIGNAL", StringFormat("SELL close=%.5f rsi=%.2f atr=%.5f", bar.close, rsi, atrValue));
      return -1;
   }
   return 0;
}

int OnInit()
{
   g_symbol = ActiveSymbol();
   SymbolSelect(g_symbol, true);
   hFast = iMA(g_symbol, InpSignalTF, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hSlow = iMA(g_symbol, InpSignalTF, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hTrend = iMA(g_symbol, InpSignalTF, InpTrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hRSI = iRSI(g_symbol, InpSignalTF, InpRSIPeriod, PRICE_CLOSE);
   hATR = iATR(g_symbol, InpSignalTF, InpATRPeriod);

   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hTrend == INVALID_HANDLE || hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE)
      return INIT_FAILED;

   g_lastBarTime = iTime(g_symbol, InpSignalTF, 0);
   ResetDayCounter();
   Journal("INIT", StringFormat("symbol=%s tf=%d", g_symbol, (int)InpSignalTF));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hFast != INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow != INVALID_HANDLE) IndicatorRelease(hSlow);
   if(hTrend != INVALID_HANDLE) IndicatorRelease(hTrend);
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   Journal("DEINIT", IntegerToString(reason));
}

void OnTick()
{
   if(!Ready() || !NewBar()) return;
   ResetDayCounter();

   double atr = 0.0;
   int signal = Signal(atr);
   if(signal == 0) return;

   if(!SpreadOK())
   {
      Journal("BLOCK", "spread");
      return;
   }

   if(InpMinMinutesBetweenEntries > 0 && g_lastEntryTime > 0 && TimeCurrent() - g_lastEntryTime < InpMinMinutesBetweenEntries * 60)
   {
      Journal("BLOCK", "cooldown");
      return;
   }

   if(InpMaxNewEntriesPerDay > 0 && g_entriesToday >= InpMaxNewEntriesPerDay)
   {
      Journal("BLOCK", "daily_limit");
      return;
   }

   if(InpCloseOnOppositeSignal) CloseOppositePositions(signal);
   if(InpOnlyOnePosition && CountPositions() > 0)
   {
      Journal("BLOCK", "existing_position");
      return;
   }

   OpenMarketOrder(signal, atr);
}
