//+------------------------------------------------------------------+
//| XAUUSD_Master_V21_EA_PUBLIC.mq5                                  |
//| Pine conversion: EMA 9/21 cross + EMA200 + RSI + volume + session |
//| TP = 2.0 ATR, SL = 1.5 ATR.                                      |
//+------------------------------------------------------------------+
#property strict
#property version "21.00"

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

// Existing GitHub runner compatibility inputs. Not used by the V21 signal engine.
input int InpStrategyProfile=0; input bool InpUseRiskLot=false; input bool InpForceTenKLotBand=false;
input double InpMaxAllowedSingleLot=0.10, InpMaxAllowedTotalLots=0.20, InpMaxTotalLots=0.20;
input bool InpRiskThrottleOnDD=false, InpCapitalProtectionMode=false, InpUseDynamicScoreThreshold=false;
input double InpMinFreeMarginAfterTradePct=5.0, InpMinScoreToEnter=20.0, InpMinScoreGap=0.0;
input double InpMinADX=0.0, InpMaxADX=100.0, InpMinATRPct=0.0, InpMaxATRPct=10.0, InpMinRangeEfficiency=0.0;
input bool InpRequireMacroAlignment=false, InpAvoidDoji=false, InpUseVWAPFilter=false, InpUseSMCStructureScore=false;
input bool InpRejectLargeWickAgainstTrade=false, InpUseVolatilityShockFilter=false, InpUseTrendSlopeFilter=false;
input bool InpUseConsecutiveCloseFilter=false, InpUseAdaptiveGridStop=false, InpUseEquityCurvePause=false;
input bool InpUseATRAccelerationFilter=false, InpUseSessionQualityFilter=false, InpBlockAsianSession=false;
input bool InpUseSpreadSpikeFilter=false, InpCloseAtDailyProfitTarget=false, InpUseHardBasketTimeStop=false;
input bool InpUseSignalDecayExit=false, InpUseATRNormalizedSpread=false, InpUseLiquidityDistanceFilter=false;
input bool InpUseEntryScoreDecayBlock=false, InpUseV14ConvictionGate=false, InpV14RequireAlphaOrExplosive=false;
input double InpV14MinEntryScore=20.0, InpV14MinEntryGap=0.0;
input bool InpUseV14ShockPause=false, InpUseV15EliteProfitGate=false, InpV15RequireEliteTrend=false;
input bool InpUseV16ApexCompoundEngine=false, InpV16RequireConfirmedClose=false, InpV16RequireApexTrend=false;
input bool InpUseV17ProfitAsymmetry=false, InpV17BlockThreeBarReversal=false, InpUseAlphaHarvestEngine=false;
input bool InpUseAmbiguityPenalty=false, InpUseWeeklyProtection=false, InpVerboseDecisionLog=true;

string g_symbol="";
datetime g_lastBarTime=0, g_lastEntryTime=0;
int g_dayKey=0, g_entriesToday=0;
int hFast=INVALID_HANDLE, hSlow=INVALID_HANDLE, hTrend=INVALID_HANDLE, hRSI=INVALID_HANDLE, hATR=INVALID_HANDLE;

string Sym(){ return (StringLen(InpTradeSymbol)>0 ? InpTradeSymbol : _Symbol); }

int DayKey(datetime t)
{
   MqlDateTime d; TimeToStruct(t,d);
   return d.year*10000+d.mon*100+d.day;
}

void Journal(string e,string d)
{
   if(!InpUseCSVJournal) return;
   int f=FileOpen(InpCSVJournalName,FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON,';');
   if(f==INVALID_HANDLE) return;
   FileSeek(f,0,SEEK_END);
   FileWrite(f,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),g_symbol,e,d);
   FileClose(f);
}

void Log(string s){ if(InpVerboseLog) Print(s); }

bool Ready()
{
   if(g_symbol=="") g_symbol=Sym();
   if(!SymbolSelect(g_symbol,true)) return false;
   int need=MathMax(InpTrendEMAPeriod,MathMax(InpVolumeSMAPeriod,MathMax(InpRSIPeriod,InpATRPeriod)))+10;
   return (iBars(g_symbol,InpSignalTF)>=need);
}

bool NewBar()
{
   datetime t=iTime(g_symbol,InpSignalTF,0);
   if(t<=0 || t==g_lastBarTime) return false;
   g_lastBarTime=t;
   return true;
}

bool Buf(int h,int shift,double &v)
{
   double b[]; ArraySetAsSeries(b,true);
   if(h==INVALID_HANDLE || CopyBuffer(h,0,shift,1,b)!=1) return false;
   v=b[0]; return true;
}

bool ClosedBar(MqlRates &bar)
{
   MqlRates r[]; ArraySetAsSeries(r,true);
   if(CopyRates(g_symbol,InpSignalTF,1,1,r)!=1) return false;
   bar=r[0]; return true;
}

bool SessionOK()
{
   if(!InpUseSessionFilter) return true;
   datetime bt=iTime(g_symbol,InpSignalTF,1);
   if(bt<=0) return false;
   MqlDateTime d; TimeToStruct(bt,d);
   if(InpMondayToFridayOnly && (d.day_of_week==0 || d.day_of_week==6)) return false;
   return (d.hour>=InpSessionStartHour && d.hour<InpSessionEndHour);
}

bool VolumeOK()
{
   if(InpVolumeSMAPeriod<=1) return true;
   MqlRates r[]; ArraySetAsSeries(r,true);
   int n=CopyRates(g_symbol,InpSignalTF,1,InpVolumeSMAPeriod,r);
   if(n<InpVolumeSMAPeriod) return false;
   double sum=0.0;
   for(int i=0;i<n;i++) sum+=(double)r[i].tick_volume;
   return ((double)r[0].tick_volume > (sum/(double)n)*InpVolumeMultiplier);
}

bool SpreadOK()
{
   double ask=SymbolInfoDouble(g_symbol,SYMBOL_ASK), bid=SymbolInfoDouble(g_symbol,SYMBOL_BID);
   double point=SymbolInfoDouble(g_symbol,SYMBOL_POINT);
   if(ask<=0.0 || bid<=0.0 || point<=0.0 || InpMaxSpreadPoints<=0.0) return true;
   return ((ask-bid)/point <= InpMaxSpreadPoints);
}

void ResetDay()
{
   int k=DayKey(TimeCurrent());
   if(k!=g_dayKey){ g_dayKey=k; g_entriesToday=0; }
}

int CountPos(int dir=0)
{
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=g_symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      if(dir>0 && type!=POSITION_TYPE_BUY) continue;
      if(dir<0 && type!=POSITION_TYPE_SELL) continue;
      c++;
   }
   return c;
}

double Lot()
{
   double v=InpFixedLot;
   double minv=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MIN), maxv=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_STEP);
   if(step>0.0) v=MathFloor(v/step+0.0000001)*step;
   if(minv>0.0) v=MathMax(v,minv);
   if(maxv>0.0) v=MathMin(v,maxv);
   return NormalizeDouble(v,2);
}

ENUM_ORDER_TYPE_FILLING Fill()
{
   long m=SymbolInfoInteger(g_symbol,SYMBOL_FILLING_MODE);
   if((m&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   if((m&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

bool CloseTicket(ulong ticket)
{
   if(ticket==0 || !PositionSelectByTicket(ticket)) return false;
   long ptype=PositionGetInteger(POSITION_TYPE);
   double vol=PositionGetDouble(POSITION_VOLUME);
   MqlTick tick; if(!SymbolInfoTick(g_symbol,tick)) return false;

   MqlTradeRequest q; MqlTradeResult r; ZeroMemory(q); ZeroMemory(r);
   q.action=TRADE_ACTION_DEAL; q.position=ticket; q.symbol=g_symbol; q.magic=InpMagic;
   q.volume=vol; q.type=(ptype==POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   q.price=(ptype==POSITION_TYPE_BUY ? tick.bid : tick.ask);
   q.deviation=InpDeviationPoints; q.type_filling=Fill(); q.type_time=ORDER_TIME_GTC;
   q.comment="Master V21 close";
   bool ok=OrderSend(q,r);
   Journal(ok?"CLOSE":"CLOSE_FAIL",StringFormat("ticket=%I64u retcode=%u",ticket,r.retcode));
   return (ok && (r.retcode==TRADE_RETCODE_DONE || r.retcode==TRADE_RETCODE_DONE_PARTIAL || r.retcode==TRADE_RETCODE_PLACED));
}

void CloseOpposite(int dir)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=g_symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      if(dir>0 && type==POSITION_TYPE_SELL) CloseTicket(ticket);
      if(dir<0 && type==POSITION_TYPE_BUY) CloseTicket(ticket);
   }
}

bool OpenOrder(int dir,double atr)
{
   if(dir==0 || atr<=0.0) return false;
   MqlTick tick; if(!SymbolInfoTick(g_symbol,tick)) return false;
   int digits=(int)SymbolInfoInteger(g_symbol,SYMBOL_DIGITS);
   double point=SymbolInfoDouble(g_symbol,SYMBOL_POINT);
   double minDist=MathMax((double)SymbolInfoInteger(g_symbol,SYMBOL_TRADE_STOPS_LEVEL)*point,point);
   double price=(dir>0 ? tick.ask : tick.bid);
   double sl=(dir>0 ? price-atr*InpSL_ATR_Multiplier : price+atr*InpSL_ATR_Multiplier);
   double tp=(dir>0 ? price+atr*InpTP_ATR_Multiplier : price-atr*InpTP_ATR_Multiplier);
   if(dir>0){ if(price-sl<minDist) sl=price-minDist; if(tp-price<minDist) tp=price+minDist; }
   else { if(sl-price<minDist) sl=price+minDist; if(price-tp<minDist) tp=price-minDist; }

   MqlTradeRequest q; MqlTradeResult r; ZeroMemory(q); ZeroMemory(r);
   q.action=TRADE_ACTION_DEAL; q.symbol=g_symbol; q.magic=InpMagic; q.volume=Lot();
   q.type=(dir>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   q.price=NormalizeDouble(price,digits); q.sl=NormalizeDouble(sl,digits); q.tp=NormalizeDouble(tp,digits);
   q.deviation=InpDeviationPoints; q.type_filling=Fill(); q.type_time=ORDER_TIME_GTC;
   q.comment=(dir>0 ? "Master V21 BUY" : "Master V21 SELL");

   bool ok=OrderSend(q,r);
   string side=(dir>0?"BUY":"SELL");
   Journal(ok?"OPEN":"OPEN_FAIL",StringFormat("%s retcode=%u price=%.5f sl=%.5f tp=%.5f atr=%.5f",side,r.retcode,q.price,q.sl,q.tp,atr));
   Log(StringFormat("%s retcode=%u",side,r.retcode));
   if(ok && (r.retcode==TRADE_RETCODE_DONE || r.retcode==TRADE_RETCODE_DONE_PARTIAL || r.retcode==TRADE_RETCODE_PLACED))
   {
      g_lastEntryTime=TimeCurrent(); g_entriesToday++; return true;
   }
   return false;
}

int Signal(double &atr)
{
   atr=0.0;
   if(!SessionOK() || !VolumeOK()) return 0;

   double f1,f2,s1,s2,e200,rsi,a;
   if(!Buf(hFast,1,f1) || !Buf(hFast,2,f2) || !Buf(hSlow,1,s1) || !Buf(hSlow,2,s2)) return 0;
   if(!Buf(hTrend,1,e200) || !Buf(hRSI,1,rsi) || !Buf(hATR,1,a)) return 0;

   MqlRates bar; if(!ClosedBar(bar)) return 0;
   bool longSig=(f1>s1 && f2<=s2 && bar.close>e200 && rsi>InpLongRSIMin && rsi<InpLongRSIMax);
   bool shortSig=(f1<s1 && f2>=s2 && bar.close<e200 && rsi<InpShortRSIMax && rsi>InpShortRSIMin);

   if(longSig){ atr=a; Journal("SIGNAL","BUY"); return 1; }
   if(shortSig){ atr=a; Journal("SIGNAL","SELL"); return -1; }
   return 0;
}

int OnInit()
{
   g_symbol=Sym();
   SymbolSelect(g_symbol,true);
   hFast=iMA(g_symbol,InpSignalTF,InpFastEMAPeriod,0,MODE_EMA,PRICE_CLOSE);
   hSlow=iMA(g_symbol,InpSignalTF,InpSlowEMAPeriod,0,MODE_EMA,PRICE_CLOSE);
   hTrend=iMA(g_symbol,InpSignalTF,InpTrendEMAPeriod,0,MODE_EMA,PRICE_CLOSE);
   hRSI=iRSI(g_symbol,InpSignalTF,InpRSIPeriod,PRICE_CLOSE);
   hATR=iATR(g_symbol,InpSignalTF,InpATRPeriod);
   if(hFast==INVALID_HANDLE || hSlow==INVALID_HANDLE || hTrend==INVALID_HANDLE || hRSI==INVALID_HANDLE || hATR==INVALID_HANDLE) return INIT_FAILED;
   g_lastBarTime=iTime(g_symbol,InpSignalTF,0);
   ResetDay();
   Journal("INIT",StringFormat("symbol=%s tf=%d",g_symbol,(int)InpSignalTF));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hFast!=INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow!=INVALID_HANDLE) IndicatorRelease(hSlow);
   if(hTrend!=INVALID_HANDLE) IndicatorRelease(hTrend);
   if(hRSI!=INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
   Journal("DEINIT",IntegerToString(reason));
}

void OnTick()
{
   if(!Ready() || !NewBar()) return;
   ResetDay();

   double atr=0.0;
   int sig=Signal(atr);
   if(sig==0) return;

   if(!SpreadOK()){ Journal("BLOCK","spread"); return; }
   if(InpMinMinutesBetweenEntries>0 && g_lastEntryTime>0 && TimeCurrent()-g_lastEntryTime<InpMinMinutesBetweenEntries*60){ Journal("BLOCK","cooldown"); return; }
   if(InpMaxNewEntriesPerDay>0 && g_entriesToday>=InpMaxNewEntriesPerDay){ Journal("BLOCK","daily_limit"); return; }

   if(InpCloseOnOppositeSignal) CloseOpposite(sig);
   if(InpOnlyOnePosition && CountPos()>0){ Journal("BLOCK","existing_position"); return; }

   OpenOrder(sig,atr);
}
