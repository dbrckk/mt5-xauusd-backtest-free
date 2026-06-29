//+------------------------------------------------------------------+
//| XAUUSD_Master_V21_EA_PUBLIC.mq5                                  |
//| Pine Script conversion for GitHub Actions MT5 public backtests.    |
//| Source logic: EMA 9/21 cross + EMA 200 trend + RSI + volume +     |
//| 08:00-21:00 Mon-Fri session + ATR TP/SL.                          |
//+------------------------------------------------------------------+
#property strict
#property version   "21.00"
#property description "XAUUSD Master V21 EA: Pine conversion with EMA cross, EMA200 trend, RSI, volume, session filter, ATR TP/SL."

//-------------------- Strategy inputs --------------------
input string          InpTradeSymbol              = "XAUUSD";
input ulong           InpMagic                    = 26062921;
input ENUM_TIMEFRAMES InpSignalTF                 = PERIOD_M15;
input double          InpFixedLot                 = 0.01;

input int             InpFastEMAPeriod            = 9;
input int             InpSlowEMAPeriod            = 21;
input int             InpTrendEMAPeriod           = 200;
input int             InpRSIPeriod                = 14;
input int             InpATRPeriod                = 14;
input int             InpVolumeSMAPeriod          = 20;

input double          InpVolumeMultiplier         = 0.80;
input double          InpLongRSIMin               = 50.0;
input double          InpLongRSIMax               = 68.0;
input double          InpShortRSIMax              = 50.0;
input double          InpShortRSIMin              = 32.0;

input double          InpTP_ATR_Multiplier        = 2.0;
input double          InpSL_ATR_Multiplier        = 1.5;

input bool            InpUseSessionFilter         = true;
input int             InpSessionStartHour         = 8;
input int             InpSessionEndHour           = 21;
input bool            InpMondayToFridayOnly       = true;

input bool            InpOnlyOnePosition          = true;
input bool            InpCloseOnOppositeSignal    = true;
input int             InpMinMinutesBetweenEntries = 0;
input int             InpMaxNewEntriesPerDay      = 80;
input double          InpMaxSpreadPoints          = 9999.0;
input int             InpDeviationPoints          = 30;

input bool            InpUseCSVJournal            = true;
input string          InpCSVJournalName           = "XAUUSD_Master_V21_journal.csv";
input bool            InpVerboseLog               = true;

//-------------------- Legacy public-runner compatibility inputs --------------------
// These inputs are intentionally kept so the existing GitHub Actions .set files
// can run without failing even though they are not used by the V21 signal logic.
input int    InpStrategyProfile = 0;
input bool   InpUseRiskLot = false;
input bool   InpForceTenKLotBand = false;
input double InpMaxAllowedSingleLot = 0.10;
input double InpMaxAllowedTotalLots = 0.20;
input double InpMaxTotalLots = 0.20;
input bool   InpRiskThrottleOnDD = false;
input bool   InpCapitalProtectionMode = false;
input double InpMinFreeMarginAfterTradePct = 5.0;
input bool   InpUseDynamicScoreThreshold = false;
input double InpMinScoreToEnter = 20.0;
input double InpMinScoreGap = 0.0;
input double InpMinADX = 0.0;
input double InpMaxADX = 100.0;
input double InpMinATRPct = 0.0;
input double InpMaxATRPct = 10.0;
input double InpMinRangeEfficiency = 0.0;
input bool   InpRequireMacroAlignment = false;
input bool   InpAvoidDoji = false;
input bool   InpUseVWAPFilter = false;
input bool   InpUseSMCStructureScore = false;
input bool   InpRejectLargeWickAgainstTrade = false;
input bool   InpUseVolatilityShockFilter = false;
input bool   InpUseTrendSlopeFilter = false;
input bool   InpUseConsecutiveCloseFilter = false;
input bool   InpUseAdaptiveGridStop = false;
input bool   InpUseEquityCurvePause = false;
input bool   InpUseATRAccelerationFilter = false;
input bool   InpUseSessionQualityFilter = false;
input bool   InpBlockAsianSession = false;
input bool   InpUseSpreadSpikeFilter = false;
input bool   InpCloseAtDailyProfitTarget = false;
input bool   InpUseHardBasketTimeStop = false;
input bool   InpUseSignalDecayExit = false;
input bool   InpUseATRNormalizedSpread = false;
input bool   InpUseLiquidityDistanceFilter = false;
input bool   InpUseEntryScoreDecayBlock = false;
input bool   InpUseV14ConvictionGate = false;
input double InpV14MinEntryScore = 20.0;
input double InpV14MinEntryGap = 0.0;
input bool   InpV14RequireAlphaOrExplosive = false;
input bool   InpUseV14ShockPause = false;
input bool   InpUseV15EliteProfitGate = false;
input bool   InpV15RequireEliteTrend = false;
input bool   InpUseV16ApexCompoundEngine = false;
input bool   InpV16RequireConfirmedClose = false;
input bool   InpV16RequireApexTrend = false;
input bool   InpUseV17ProfitAsymmetry = false;
input bool   InpV17BlockThreeBarReversal = false;
input bool   InpUseAlphaHarvestEngine = false;
input bool   InpUseAmbiguityPenalty = false;
input bool   InpUseWeeklyProtection = false;
input bool   InpVerboseDecisionLog = true;

string   g_symbol = "";
datetime g_lastBarTime = 0;
datetime g_lastEntryTime = 0;
int      g_dayKey = 0;
int      g_entriesToday = 0;

int g_fastHandle = INVALID_HANDLE;
int g_slowHandle = INVALID_HANDLE;
int g_trendHandle = INVALID_HANDLE;
int g_rsiHandle = INVALID_HANDLE;
int g_atrHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Utility                                                          |
//+------------------------------------------------------------------+
string TradeSymbol()
{
   if(StringLen(InpTradeSymbol) > 0)
      return InpTradeSymbol;
   return _Symbol;
}

int DayKey(const datetime value)
{
   MqlDateTime dt;
   TimeToStruct(value, dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

string DirectionText(const int direction)
{
   if(direction > 0) return "BUY";
   if(direction < 0) return "SELL";
   return "NONE";
}

void JournalEvent(const string eventName, const string details)
{
   if(!InpUseCSVJournal)
      return;

   int handle = FileOpen(InpCSVJournalName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON, ';');
   if(handle == INVALID_HANDLE)
      return;

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle,
             TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
             g_symbol,
             eventName,
             details);
   FileClose(handle);
}

void LogMsg(const string message)
{
   if(InpVerboseLog)
      Print(message);
}

bool RefreshDailyCounters()
{
   int today = DayKey(TimeCurrent());
   if(today <= 0)
      return false;

   if(g_dayKey != today)
   {
      g_dayKey = today;
      g_entriesToday = 0;
   }

   return true;
}

bool SymbolReady()
{
   if(g_symbol == "")
      g_symbol = TradeSymbol();

   if(!SymbolSelect(g_symbol, true))
   {
      Print("SymbolSelect failed for ", g_symbol);
      return false;
   }

   int minBars = MathMax(InpTrendEMAPeriod, MathMax(InpVolumeSMAPeriod, MathMax(InpRSIPeriod, InpATRPeriod))) + 10;
   if(iBars(g_symbol, InpSignalTF) < minBars)
      return false;

   return true;
}

bool NewBar()
{
   datetime currentBar = iTime(g_symbol, InpSignalTF, 0);
   if(currentBar <= 0)
      return false;

   if(currentBar == g_lastBarTime)
      return false;

   g_lastBarTime = currentBar;
   return true;
}

bool IndicatorValue(const int handle, const int shift, double &value)
{
   if(handle == INVALID_HANDLE)
      return false;

   double buffer[];
   ArraySetAsSeries(buffer, true);

   if(CopyBuffer(handle, 0, shift, 1, buffer) != 1)
      return false;

   value = buffer[0];
   return true;
}

bool ClosedBarRates(MqlRates &bar)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(g_symbol, InpSignalTF, 1, 1, rates) != 1)
      return false;

   bar = rates[0];
   return true;
}

bool SessionOK()
{
   if(!InpUseSessionFilter)
      return true;

   datetime barTime = iTime(g_symbol, InpSignalTF, 1);
   if(barTime <= 0)
      return false;

   MqlDateTime dt;
   TimeToStruct(barTime, dt);

   if(InpMondayToFridayOnly && (dt.day_of_week == 0 || dt.day_of_week == 6))
      return false;

   return (dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour);
}

bool VolumeOK()
{
   if(InpVolumeSMAPeriod <= 1)
      return true;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int copied = CopyRates(g_symbol, InpSignalTF, 1, InpVolumeSMAPeriod, rates);
   if(copied < InpVolumeSMAPeriod)
      return false;

   double sumVolume = 0.0;
   for(int i = 0; i < copied; i++)
      sumVolume += (double)rates[i].tick_volume;

   double averageVolume = sumVolume / (double)copied;
   double signalVolume = (double)rates[0].tick_volume;

   return (signalVolume > averageVolume * InpVolumeMultiplier);
}

bool SpreadOK()
{
   if(InpMaxSpreadPoints <= 0.0)
      return true;

   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);

   if(ask <= 0.0 || bid <= 0.0 || point <= 0.0)
      return true;

   double spreadPoints = (ask - bid) / point;
   return (spreadPoints <= InpMaxSpreadPoints);
}

int CountPositions(const int direction = 0)
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      if(direction > 0 && type != POSITION_TYPE_BUY)
         continue;
      if(direction < 0 && type != POSITION_TYPE_SELL)
         continue;

      count++;
   }

   return count;
}

double NormalizeTradeVolume(const double volume)
{
   double minLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);

   double normalized = volume;

   if(stepLot > 0.0)
      normalized = MathFloor(normalized / stepLot + 0.0000001) * stepLot;

   if(minLot > 0.0)
      normalized = MathMax(normalized, minLot);

   if(maxLot > 0.0)
      normalized = MathMin(normalized, maxLot);

   return NormalizeDouble(normalized, 2);
}

ENUM_ORDER_TYPE_FILLING FillingMode()
{
   long mode = SymbolInfoInteger(g_symbol, SYMBOL_FILLING_MODE);

   if((mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;

   if((mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
}

bool SendMarketOrder(const int direction, const double atr)
{
   if(direction == 0 || atr <= 0.0)
      return false;

   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick))
      return false;

   double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   long stopLevelPoints = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = MathMax((double)stopLevelPoints * point, point);

   double volume = NormalizeTradeVolume(InpFixedLot);
   if(volume <= 0.0)
      return false;

   double price = (direction > 0 ? tick.ask : tick.bid);
   double sl = 0.0;
   double tp = 0.0;

   if(direction > 0)
   {
      sl = price - atr * InpSL_ATR_Multiplier;
      tp = price + atr * InpTP_ATR_Multiplier;

      if(price - sl < minDistance) sl = price - minDistance;
      if(tp - price < minDistance) tp = price + minDistance;
   }
   else
   {
      sl = price + atr * InpSL_ATR_Multiplier;
      tp = price - atr * InpTP_ATR_Multiplier;

      if(sl - price < minDistance) sl = price + minDistance;
      if(price - tp < minDistance) tp = price - minDistance;
   }

   price = NormalizeDouble(price, digits);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = g_symbol;
   request.magic = InpMagic;
   request.volume = volume;
   request.type = (direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = InpDeviationPoints;
   request.type_filling = FillingMode();
   request.type_time = ORDER_TIME_GTC;
   request.comment = (direction > 0 ? "Master V21 BUY" : "Master V21 SELL");

   ResetLastError();
   bool ok = OrderSend(request, result);
   string details = StringFormat("%s volume=%.2f price=%.*f sl=%.*f tp=%.*f atr=%.5f retcode=%u last_error=%d",
                                 DirectionText(direction),
                                 volume,
                                 digits, price,
                                 digits, sl,
                                 digits, tp,
                                 atr,
                                 result.retcode,
                                 GetLastError());

   JournalEvent(ok ? "ORDER_SEND" : "ORDER_SEND_FAILED", details);
   LogMsg(details);

   if(ok && (result.retcode == TRADE_RETCODE_DONE ||
             result.retcode == TRADE_RETCODE_DONE_PARTIAL ||
             result.retcode == TRADE_RETCODE_PLACED))
   {
      g_lastEntryTime = TimeCurrent();
      g_entriesToday++;
      return true;
   }

   return false;
}

bool CloseTicket(const ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;

   string symbol = PositionGetString(POSITION_SYMBOL);
   long type = PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
      return false;

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = symbol;
   request.magic = InpMagic;
   request.volume = volume;
   request.type = (type == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   request.price = (type == POSITION_TYPE_BUY ? tick.bid : tick.ask);
   request.deviation = InpDeviationPoints;
   request.type_filling = FillingMode();
   request.type_time = ORDER_TIME_GTC;
   request.comment = "Master V21 close";

   ResetLastError();
   bool ok = OrderSend(request, result);

   string details = StringFormat("ticket=%I64u retcode=%u last_error=%d", ticket, result.retcode, GetLastError());
   JournalEvent(ok ? "CLOSE" : "CLOSE_FAILED", details);
   LogMsg(details);

   return (ok && (result.retcode == TRADE_RETCODE_DONE ||
                  result.retcode == TRADE_RETCODE_DONE_PARTIAL ||
                  result.retcode == TRADE_RETCODE_PLACED));
}

void CloseOppositePositions(const int signalDirection)
{
   if(signalDirection == 0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);

      if(signalDirection > 0 && type == POSITION_TYPE_SELL)
         CloseTicket(ticket);

      if(signalDirection < 0 && type == POSITION_TYPE_BUY)
         CloseTicket(ticket);
   }
}

bool EntryCooldownOK()
{
   if(InpMinMinutesBetweenEntries <= 0)
      return true;

   if(g_lastEntryTime <= 0)
      return true;

   return (TimeCurrent() - g_lastEntryTime >= InpMinMinutesBetweenEntries * 60);
}

bool EntryCountOK()
{
   if(!RefreshDailyCounters())
      return false;

   if(InpMaxNewEntriesPerDay <= 0)
      return true;

   return (g_entriesToday < InpMaxNewEntriesPerDay);
}

//+------------------------------------------------------------------+
//| Signal calculation                                                |
//+------------------------------------------------------------------+
int ComputeSignal(double &atrValue)
{
   atrValue = 0.0;

   if(!SessionOK())
      return 0;

   if(!VolumeOK())
      return 0;

   double fast1, fast2, slow1, slow2, trend1, rsi1, atr1;

   if(!IndicatorValue(g_fastHandle, 1, fast1)) return 0;
   if(!IndicatorValue(g_fastHandle, 2, fast2)) return 0;
   if(!IndicatorValue(g_slowHandle, 1, slow1)) return 0;
   if(!IndicatorValue(g_slowHandle, 2, slow2)) return 0;
   if(!IndicatorValue(g_trendHandle, 1, trend1)) return 0;
   if(!IndicatorValue(g_rsiHandle, 1, rsi1)) return 0;
   if(!IndicatorValue(g_atrHandle, 1, atr1)) return 0;

   MqlRates bar;
   if(!ClosedBarRates(bar))
      return 0;

   bool crossUp = (fast1 > slow1 && fast2 <= slow2);
   bool crossDown = (fast1 < slow1 && fast2 >= slow2);

   bool longSignal =
      crossUp &&
      bar.close > trend1 &&
      rsi1 > InpLongRSIMin &&
      rsi1 < InpLongRSIMax;

   bool shortSignal =
      crossDown &&
      bar.close < trend1 &&
      rsi1 < InpShortRSIMax &&
      rsi1 > InpShortRSIMin;

   if(longSignal)
   {
      atrValue = atr1;
      JournalEvent("SIGNAL", StringFormat("BUY close=%.5f fast=%.5f slow=%.5f ema200=%.5f rsi=%.2f atr=%.5f", bar.close, fast1, slow1, trend1, rsi1, atr1));
      return 1;
   }

   if(shortSignal)
   {
      atrValue = atr1;
      JournalEvent("SIGNAL", StringFormat("SELL close=%.5f fast=%.5f slow=%.5f ema200=%.5f rsi=%.2f atr=%.5f", bar.close, fast1, slow1, trend1, rsi1, atr1));
      return -1;
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Expert lifecycle                                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol = TradeSymbol();

   if(!SymbolReady())
   {
      Print("Symbol is not ready yet: ", g_symbol);
   }

   g_fastHandle = iMA(g_symbol, InpSignalTF, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_slowHandle = iMA(g_symbol, InpSignalTF, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_trendHandle = iMA(g_symbol, InpSignalTF, InpTrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_rsiHandle = iRSI(g_symbol, InpSignalTF, InpRSIPeriod, PRICE_CLOSE);
   g_atrHandle = iATR(g_symbol, InpSignalTF, InpATRPeriod);

   if(g_fastHandle == INVALID_HANDLE ||
      g_slowHandle == INVALID_HANDLE ||
      g_trendHandle == INVALID_HANDLE ||
      g_rsiHandle == INVALID_HANDLE ||
      g_atrHandle == INVALID_HANDLE)
   {
      Print("Indicator handle creation failed for ", g_symbol);
      return INIT_FAILED;
   }

   g_lastBarTime = iTime(g_symbol, InpSignalTF, 0);
   RefreshDailyCounters();

   JournalEvent("INIT",
                StringFormat("symbol=%s tf=%d fast=%d slow=%d trend=%d rsi=%d atr=%d session=%02d-%02d",
                             g_symbol,
                             (int)InpSignalTF,
                             InpFastEMAPeriod,
                             InpSlowEMAPeriod,
                             InpTrendEMAPeriod,
                             InpRSIPeriod,
                             InpATRPeriod,
                             InpSessionStartHour,
                             InpSessionEndHour));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_fastHandle != INVALID_HANDLE) IndicatorRelease(g_fastHandle);
   if(g_slowHandle != INVALID_HANDLE) IndicatorRelease(g_slowHandle);
   if(g_trendHandle != INVALID_HANDLE) IndicatorRelease(g_trendHandle);
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);

   JournalEvent("DEINIT", StringFormat("reason=%d", reason));
}

void OnTick()
{
   if(!SymbolReady())
      return;

   if(!NewBar())
      return;

   double atrValue = 0.0;
   int signal = ComputeSignal(atrValue);

   if(signal == 0)
      return;

   if(!SpreadOK())
   {
      JournalEvent("BLOCK", "spread");
      return;
   }

   if(!EntryCooldownOK())
   {
      JournalEvent("BLOCK", "entry_cooldown");
      return;
   }

   if(!EntryCountOK())
   {
      JournalEvent("BLOCK", "daily_entry_limit");
      return;
   }

   if(InpCloseOnOppositeSignal)
      CloseOppositePositions(signal);

   if(InpOnlyOnePosition && CountPositions() > 0)
   {
      JournalEvent("BLOCK", "existing_position");
      return;
   }

   SendMarketOrder(signal, atrValue);
}
