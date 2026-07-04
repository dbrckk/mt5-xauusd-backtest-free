//+------------------------------------------------------------------+
//| XAUUSD_V27_Clean_MultiSetup.mq5                                  |
//| EA conversion of Ultimate Zero-Lag MTF Fully Automated Pine logic  |
//| Natural entries only: ZLEMA cross + HTF trend + ATR volatility.    |
//+------------------------------------------------------------------+
#property strict
#property version   "3.00"
#property description "ZLEMA-AUTO MTF strategy converted from Pine Script for MT5 backtests"

#include <Trade/Trade.mqh>
CTrade trade;

input string InpTradeSymbol="";
input bool UseAuto=true;
input int ManualFastLen=12;
input int ManualSlowLen=26;
input double ManualAtrMult=0.8;
input ENUM_TIMEFRAMES ManualHTF=PERIOD_H1;
input int AtrLen=14;
input double FixedLot=0.02;
input ulong MagicNumber=270300;
input int SlippagePoints=160;
input int StopBufferPoints=60;
input bool EnableBuy=true;
input bool EnableSell=true;
input int MaxTradesPerDay=8;
input int CooldownMinutes=15;
input bool CloseOnOppositeSignal=true;
input double StopATR=1.20;
input double TakeProfitATR=1.80;
input bool UseBreakEven=true;
input double BreakEvenTriggerATR=0.90;
input double BreakEvenOffsetATR=0.05;
input bool UseTrailing=true;
input double TrailStartATR=1.20;
input double TrailDistanceATR=0.85;
input bool UseCSVJournal=true;
input string CSVJournalName="ZLEMA_AUTO_journal.csv";

string Sym;
datetime lastBarTime=0;
datetime lastEntryTime=0;
int tradesToday=0;
int currentYear=-1;
int currentDay=-1;
double activeATR=0.0;

int PeriodMinutes(ENUM_TIMEFRAMES tf)
{
   int seconds=PeriodSeconds(tf);
   if(seconds<=0) return 15;
   return seconds/60;
}

void AutoParams(ENUM_TIMEFRAMES tf,int &fastLen,int &slowLen,double &atrMult,ENUM_TIMEFRAMES &htf)
{
   if(!UseAuto)
   {
      fastLen=ManualFastLen;
      slowLen=ManualSlowLen;
      atrMult=ManualAtrMult;
      htf=ManualHTF;
      return;
   }
   int m=PeriodMinutes(tf);
   if(m<=3){fastLen=8;slowLen=21;atrMult=0.6;htf=PERIOD_M15;return;}
   if(m<=15){fastLen=10;slowLen=24;atrMult=0.7;htf=PERIOD_H1;return;}
   if(m<=60){fastLen=12;slowLen=26;atrMult=0.8;htf=PERIOD_H4;return;}
   fastLen=15;slowLen=35;atrMult=0.9;htf=PERIOD_D1;
}

double TickSize()
{
   double v=SymbolInfoDouble(Sym,SYMBOL_TRADE_TICK_SIZE);
   if(v<=0.0) v=SymbolInfoDouble(Sym,SYMBOL_POINT);
   if(v<=0.0) v=0.001;
   return v;
}

double NormalizePrice(double price)
{
   int digits=(int)SymbolInfoInteger(Sym,SYMBOL_DIGITS);
   double step=TickSize();
   return NormalizeDouble(MathRound(price/step)*step,digits);
}

double NormalizeVolume(double lot)
{
   double minLot=SymbolInfoDouble(Sym,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(Sym,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(Sym,SYMBOL_VOLUME_STEP);
   if(step<=0.0) step=0.01;
   if(lot<minLot || lot>maxLot) return 0.0;
   double normalized=minLot+MathRound((lot-minLot)/step)*step;
   return NormalizeDouble(normalized,2);
}

double MinStopDistance()
{
   double point=SymbolInfoDouble(Sym,SYMBOL_POINT);
   if(point<=0.0) point=0.001;
   int stopLevel=(int)SymbolInfoInteger(Sym,SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel=(int)SymbolInfoInteger(Sym,SYMBOL_TRADE_FREEZE_LEVEL);
   int pts=(int)MathMax(stopLevel,freezeLevel)+StopBufferPoints;
   return MathMax(pts*point,2.0*TickSize());
}

bool CopyCloseData(ENUM_TIMEFRAMES tf,int count,double &closes[])
{
   ArraySetAsSeries(closes,true);
   return CopyClose(Sym,tf,0,count,closes)>=count;
}

bool CopyRatesData(ENUM_TIMEFRAMES tf,int count,MqlRates &rates[])
{
   ArraySetAsSeries(rates,true);
   return CopyRates(Sym,tf,0,count,rates)>=count;
}

double Zlema(ENUM_TIMEFRAMES tf,int len,int shift)
{
   int lag=(int)MathFloor((len-1)/2.0);
   int count=MathMax(len*8+lag+shift+20,80);
   double c[];
   if(!CopyCloseData(tf,count,c)) return EMPTY_VALUE;
   double alpha=2.0/(len+1.0);
   double ema=0.0;
   bool seeded=false;
   for(int i=count-1-lag;i>=shift;i--)
   {
      double data=c[i]+(c[i]-c[i+lag]);
      if(!seeded){ema=data;seeded=true;}
      else ema=alpha*data+(1.0-alpha)*ema;
   }
   if(!seeded) return EMPTY_VALUE;
   return ema;
}

double TrueRange(MqlRates &r[],int i)
{
   double a=r[i].high-r[i].low;
   double b=MathAbs(r[i].high-r[i+1].close);
   double c=MathAbs(r[i].low-r[i+1].close);
   return MathMax(a,MathMax(b,c));
}

double ATR(ENUM_TIMEFRAMES tf,int len,int shift)
{
   int count=len+shift+5;
   MqlRates r[];
   if(!CopyRatesData(tf,count,r)) return 0.0;
   double sum=0.0;
   for(int i=shift;i<shift+len;i++) sum+=TrueRange(r,i);
   return sum/len;
}

double ATRSMA(ENUM_TIMEFRAMES tf,int atrLen,int smaLen,int shift)
{
   double sum=0.0;
   for(int i=shift;i<shift+smaLen;i++) sum+=ATR(tf,atrLen,i);
   return sum/smaLen;
}

int HTFTrend(ENUM_TIMEFRAMES htf,int fastLen,int slowLen)
{
   double f=Zlema(htf,fastLen,1);
   double s=Zlema(htf,slowLen,1);
   if(f==EMPTY_VALUE || s==EMPTY_VALUE) return 0;
   return f>s?1:-1;
}

void Journal(string eventName,string direction,double price,double atr,string details)
{
   if(!UseCSVJournal) return;
   int h=FileOpen(CSVJournalName,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0) FileWrite(h,"time","event","direction","price","atr","details");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),eventName,direction,DoubleToString(price,3),DoubleToString(atr,5),details);
   FileClose(h);
}

void ResetDaily()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   if(t.year!=currentYear || t.day_of_year!=currentDay)
   {
      currentYear=t.year;
      currentDay=t.day_of_year;
      tradesToday=0;
   }
}

bool NewBar()
{
   MqlRates r[];
   if(!CopyRatesData((ENUM_TIMEFRAMES)_Period,3,r)) return false;
   if(r[1].time==lastBarTime) return false;
   lastBarTime=r[1].time;
   return true;
}

bool FindPosition(ulong &ticket)
{
   ticket=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=Sym) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      ticket=t;
      return true;
   }
   return false;
}

int Signal(double &atrOut)
{
   ENUM_TIMEFRAMES tf=(ENUM_TIMEFRAMES)_Period;
   int fastLen,slowLen; double atrMult; ENUM_TIMEFRAMES htf;
   AutoParams(tf,fastLen,slowLen,atrMult,htf);
   double f1=Zlema(tf,fastLen,1), f2=Zlema(tf,fastLen,2);
   double s1=Zlema(tf,slowLen,1), s2=Zlema(tf,slowLen,2);
   if(f1==EMPTY_VALUE || f2==EMPTY_VALUE || s1==EMPTY_VALUE || s2==EMPTY_VALUE) return 0;
   double atr=ATR(tf,AtrLen,1);
   double ma=ATRSMA(tf,AtrLen,20,1);
   if(atr<=0.0 || ma<=0.0) return 0;
   atrOut=atr;
   bool volOk=atr>ma*atrMult;
   if(!volOk) return 0;
   int trend=HTFTrend(htf,fastLen,slowLen);
   bool bullCross=f2<=s2 && f1>s1;
   bool bearCross=f2>=s2 && f1<s1;
   if(EnableBuy && bullCross && trend==1) return 1;
   if(EnableSell && bearCross && trend==-1) return -1;
   return 0;
}

bool BuildStops(int dir,double entry,double atr,double &sl,double &tp)
{
   double minD=MinStopDistance();
   double slD=MathMax(atr*StopATR,minD);
   double tpD=MathMax(atr*TakeProfitATR,minD);
   if(dir>0)
   {
      sl=NormalizePrice(entry-slD);
      tp=NormalizePrice(entry+tpD);
      return sl<entry && tp>entry;
   }
   sl=NormalizePrice(entry+slD);
   tp=NormalizePrice(entry-tpD);
   return sl>entry && tp<entry;
}

bool OpenTrade(int dir,double atr)
{
   MqlTick tick;
   if(!SymbolInfoTick(Sym,tick)) return false;
   double lot=NormalizeVolume(FixedLot);
   if(lot<=0.0) return false;
   double entry=NormalizePrice(dir>0?tick.ask:tick.bid);
   double sl=0.0,tp=0.0;
   if(!BuildStops(dir,entry,atr,sl,tp)) return false;
   trade.SetExpertMagicNumber((int)MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(Sym);
   string direction=dir>0?"BUY":"SELL";
   bool ok=dir>0?trade.Buy(lot,Sym,entry,sl,tp,"ZLEMA AUTO BUY"):trade.Sell(lot,Sym,entry,sl,tp,"ZLEMA AUTO SELL");
   if(!ok)
   {
      Journal("OPEN_FAIL",direction,entry,atr,StringFormat("retcode=%u %s",trade.ResultRetcode(),trade.ResultComment()));
      return false;
   }
   tradesToday++;
   lastEntryTime=TimeCurrent();
   activeATR=atr;
   Journal("OPEN_ENTRY",direction,entry,atr,"zlema_cross_htf_volatility");
   return true;
}

void ManagePosition(int freshSignal,double freshATR)
{
   ulong ticket=0;
   if(!FindPosition(ticket)) return;
   if(!PositionSelectByTicket(ticket)) return;
   long type=PositionGetInteger(POSITION_TYPE);
   bool isBuy=type==POSITION_TYPE_BUY;
   if(CloseOnOppositeSignal && ((isBuy && freshSignal<0) || (!isBuy && freshSignal>0)))
   {
      trade.PositionClose(ticket);
      Journal("CLOSE_OPPOSITE",isBuy?"BUY":"SELL",PositionGetDouble(POSITION_PRICE_CURRENT),freshATR,"opposite_zlema_signal");
      return;
   }
   MqlTick tick;
   if(!SymbolInfoTick(Sym,tick)) return;
   double atr=activeATR>0.0?activeATR:freshATR;
   if(atr<=0.0) return;
   double open=PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL=PositionGetDouble(POSITION_SL);
   double currentTP=PositionGetDouble(POSITION_TP);
   double market=isBuy?tick.bid:tick.ask;
   double fav=isBuy?market-open:open-market;
   double desired=currentSL;
   bool change=false;
   if(UseBreakEven && fav>=atr*BreakEvenTriggerATR)
   {
      double be=isBuy?open+atr*BreakEvenOffsetATR:open-atr*BreakEvenOffsetATR;
      if((isBuy && (currentSL==0.0 || be>desired)) || (!isBuy && (currentSL==0.0 || be<desired))){desired=be;change=true;}
   }
   if(UseTrailing && fav>=atr*TrailStartATR)
   {
      double tr=isBuy?market-atr*TrailDistanceATR:market+atr*TrailDistanceATR;
      if((isBuy && (currentSL==0.0 || tr>desired)) || (!isBuy && (currentSL==0.0 || tr<desired))){desired=tr;change=true;}
   }
   if(!change) return;
   desired=NormalizePrice(desired);
   double minD=MinStopDistance();
   if(isBuy && desired<market-minD && (currentSL==0.0 || desired>currentSL+TickSize())) trade.PositionModify(ticket,desired,currentTP);
   if(!isBuy && desired>market+minD && (currentSL==0.0 || desired<currentSL-TickSize())) trade.PositionModify(ticket,desired,currentTP);
}

int OnInit()
{
   Sym=InpTradeSymbol==""?_Symbol:InpTradeSymbol;
   if(!SymbolSelect(Sym,true)) return INIT_FAILED;
   trade.SetExpertMagicNumber((int)MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(Sym);
   ResetDaily();
   Journal("EA_START","",0.0,0.0,"ZLEMA_AUTO_MTF");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   ResetDaily();
   if(!NewBar()) return;
   double atr=0.0;
   int sig=Signal(atr);
   ManagePosition(sig,atr);
   ulong ticket=0;
   if(FindPosition(ticket)) return;
   if(tradesToday>=MaxTradesPerDay) return;
   if(lastEntryTime>0 && TimeCurrent()-lastEntryTime<CooldownMinutes*60) return;
   if(sig!=0) OpenTrade(sig,atr);
}
//+------------------------------------------------------------------+
