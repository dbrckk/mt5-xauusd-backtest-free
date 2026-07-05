#property strict
#property version "2.82"
#property description "V28 Contextual Router: balanced cross-period entry quality and normalized risk"
#include <Trade/Trade.mqh>
CTrade trade;

input string InpTradeSymbol="";
input double FixedLot=0.02;
input bool UseRiskPercent=true;
input double RiskPercent=0.20;
input bool UseEquityForRisk=true;
input double MaxRiskLot=2.00;
input double MinLotRiskTolerance=1.10;
input int MaxTradesPerDay=4;
input int CooldownMinutes=45;
input ulong MagicNumber=280100;
input int SlippagePoints=120;
input int BrokerStopBufferPoints=40;
input bool UseSession=true;
input int SessionStartHour=7;
input int SessionEndHour=20;
input bool BlockFridayLateEntries=true;
input int FridayLastEntryHour=17;
input bool CloseBeforeWeekend=true;
input int FridayCloseHour=19;
input bool EnableBuy=true;
input bool EnableSell=true;
input double MinSignalScore=78.0;
input double MinDirectionScoreGap=10.0;
input double MinADX=20.0;
input double MaxSpreadATRFraction=0.07;
input int FastLen=9;
input int SlowLen=21;
input int TrendLen=200;
input int BiasFastLen=50;
input int BiasSlowLen=200;
input int RsiLen=14;
input int AtrLen=14;
input int AdxLen=14;
input int VolLen=20;
input int BreakoutLookback=5;
input int SweepLookback=5;
input double PullbackTouchATR=0.20;
input double MinBodyRatio=0.34;
input double MinVolumeRatio=0.95;
input double BreakoutTP_ATR=1.55;
input double BreakoutSL_ATR=1.05;
input double PullbackTP_ATR=1.35;
input double PullbackSL_ATR=1.00;
input double ContinuationTP_ATR=1.30;
input double ContinuationSL_ATR=1.00;
input double SweepTP_ATR=1.45;
input double SweepSL_ATR=0.95;
input bool UseBreakEven=true;
input double BreakEvenTriggerATR=0.85;
input double BreakEvenOffsetATR=0.02;
input bool UseTrailingStop=true;
input double TrailStartATR=1.25;
input double TrailDistanceATR=0.70;
input int MaxHoldBars=28;
input double TimeExitMinProgressATR=0.20;
input bool UseCSVJournal=true;
input string CSVJournalName="V27_CLEAN_journal.csv";

string Sym,activeSetup="",activeRoute="";
int tradesToday=0,currentYear=-1,currentDay=-1;
datetime lastEntryTime=0,lastBarTime=0;
double activeATR=0.0,activeScore=0.0,activeRisk=0.0;
int fH=INVALID_HANDLE,sH=INVALID_HANDLE,tH=INVALID_HANDLE,rH=INVALID_HANDLE,aH=INVALID_HANDLE,dH=INVALID_HANDLE;
int h1f=INVALID_HANDLE,h1s=INVALID_HANDLE,h1r=INVALID_HANDLE,h4f=INVALID_HANDLE,h4s=INVALID_HANDLE,h4r=INVALID_HANDLE;

struct Candidate{int dir;string setup;string route;double score;double atr;};
void Reset(Candidate &c){c.dir=0;c.setup="";c.route="";c.score=0;c.atr=0;}

bool One(int h,int b,int sh,double &v){double x[];ArraySetAsSeries(x,true);if(h==INVALID_HANDLE||CopyBuffer(h,b,sh,1,x)!=1)return false;v=x[0];return MathIsValidNumber(v);}
bool Rates(ENUM_TIMEFRAMES tf,int n,MqlRates &r[]){ArraySetAsSeries(r,true);return CopyRates(Sym,tf,0,n,r)>=n;}
double VolSma(MqlRates &r[],int sh,int n){double s=0;for(int i=sh;i<sh+n;i++)s+=(double)r[i].tick_volume;return s/n;}
double HH(MqlRates &r[],int sh,int n){double v=r[sh].high;for(int i=sh+1;i<sh+n;i++)v=MathMax(v,r[i].high);return v;}
double LL(MqlRates &r[],int sh,int n){double v=r[sh].low;for(int i=sh+1;i<sh+n;i++)v=MathMin(v,r[i].low);return v;}

void J(string ev,string dir,string setup,double score,double price,double atr,string details){
 if(!UseCSVJournal)return;int h=FileOpen(CSVJournalName,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');if(h==INVALID_HANDLE)return;
 if(FileSize(h)==0)FileWrite(h,"time","event","direction","setup","score","price","atr","details");FileSeek(h,0,SEEK_END);
 FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),ev,dir,setup,DoubleToString(score,2),DoubleToString(price,3),DoubleToString(atr,5),details);FileClose(h);
}

void ResetDay(){MqlDateTime x;TimeToStruct(TimeCurrent(),x);if(x.year!=currentYear||x.day_of_year!=currentDay){currentYear=x.year;currentDay=x.day_of_year;tradesToday=0;}}
bool SessionOpen(){if(!UseSession)return true;MqlDateTime x;TimeToStruct(TimeCurrent(),x);if(x.day_of_week==0||x.day_of_week==6)return false;if(x.hour<SessionStartHour||x.hour>=SessionEndHour)return false;if(BlockFridayLateEntries&&x.day_of_week==5&&x.hour>=FridayLastEntryHour)return false;return true;}
bool NewBar(){MqlRates r[];if(!Rates(PERIOD_M15,3,r)||r[1].time==lastBarTime)return false;lastBarTime=r[1].time;return true;}
bool Position(ulong &ticket){ticket=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=Sym)continue;if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;ticket=t;return true;}return false;}

int Bias(ENUM_TIMEFRAMES tf){int fh=tf==PERIOD_H1?h1f:h4f,sh=tf==PERIOD_H1?h1s:h4s,rh=tf==PERIOD_H1?h1r:h4r;MqlRates r[];double f,s,rs;if(!Rates(tf,4,r)||!One(fh,0,1,f)||!One(sh,0,1,s)||!One(rh,0,1,rs))return 0;if(r[1].close>s&&f>s&&rs>=52)return 1;if(r[1].close<s&&f<s&&rs<=48)return -1;return 0;}
double Tick(){double v=SymbolInfoDouble(Sym,SYMBOL_TRADE_TICK_SIZE);if(v<=0)v=SymbolInfoDouble(Sym,SYMBOL_POINT);return v>0?v:0.001;}
double Price(double p){return NormalizeDouble(MathRound(p/Tick())*Tick(),(int)SymbolInfoInteger(Sym,SYMBOL_DIGITS));}
double MinStop(){double p=SymbolInfoDouble(Sym,SYMBOL_POINT);if(p<=0)p=0.001;int n=(int)MathMax(SymbolInfoInteger(Sym,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(Sym,SYMBOL_TRADE_FREEZE_LEVEL))+BrokerStopBufferPoints;return MathMax(n*p,2*Tick());}

void Multipliers(string setup,double &tp,double &sl){tp=ContinuationTP_ATR;sl=ContinuationSL_ATR;if(setup=="BREAKOUT"){tp=BreakoutTP_ATR;sl=BreakoutSL_ATR;}else if(setup=="PULLBACK"){tp=PullbackTP_ATR;sl=PullbackSL_ATR;}else if(setup=="SWEEP"){tp=SweepTP_ATR;sl=SweepSL_ATR;}}
bool Stops(int dir,double entry,double atr,string setup,double &sl,double &tp){double tm,sm;Multipliers(setup,tm,sm);double md=MinStop(),td=MathMax(atr*tm,md),sd=MathMax(atr*sm,md);if(dir>0){sl=Price(entry-sd);tp=Price(entry+td);return sl<entry&&tp>entry;}sl=Price(entry+sd);tp=Price(entry-td);return sl>entry&&tp<entry;}

bool RiskMoney(int dir,double lot,double entry,double sl,double &risk){ENUM_ORDER_TYPE type=dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;double p=0;if(OrderCalcProfit(type,Sym,lot,entry,sl,p)){risk=MathAbs(p);return risk>0;}double cs=SymbolInfoDouble(Sym,SYMBOL_TRADE_CONTRACT_SIZE);if(cs<=0)cs=100;risk=MathAbs(entry-sl)*cs*lot;return risk>0;}
double VolDown(double lot){double mn=SymbolInfoDouble(Sym,SYMBOL_VOLUME_MIN),mx=SymbolInfoDouble(Sym,SYMBOL_VOLUME_MAX),st=SymbolInfoDouble(Sym,SYMBOL_VOLUME_STEP);if(st<=0)st=0.01;if(mn<=0)mn=st;if(MaxRiskLot>0)mx=MathMin(mx,MaxRiskLot);if(lot<mn)return 0;double v=MathFloor((lot+1e-10)/st)*st;v=MathMin(v,mx);return v>=mn?NormalizeDouble(v,st<0.01?3:2):0;}
bool Size(int dir,double entry,double sl,double &lot,double &plan,double &actual){lot=plan=actual=0;if(!UseRiskPercent){lot=VolDown(FixedLot);return lot>0&&RiskMoney(dir,lot,entry,sl,actual)&&(plan=actual)>0;}double base=UseEquityForRisk?AccountInfoDouble(ACCOUNT_EQUITY):AccountInfoDouble(ACCOUNT_BALANCE);if(base<=0||RiskPercent<=0)return false;plan=base*RiskPercent/100.0;double one;if(!RiskMoney(dir,1.0,entry,sl,one)||one<=0)return false;lot=VolDown(plan/one);double mn=SymbolInfoDouble(Sym,SYMBOL_VOLUME_MIN);if(mn<=0)mn=0.01;if(lot<=0){double mr;if(!RiskMoney(dir,mn,entry,sl,mr)||mr>plan*MinLotRiskTolerance)return false;lot=mn;}if(!RiskMoney(dir,lot,entry,sl,actual))return false;return actual<=plan*MinLotRiskTolerance;}

bool Route(string setup,int dir,int hour,string &name){name="";if(setup=="BREAKOUT"&&dir>0&&hour>=7&&hour<9){name="BREAKOUT_BUY_07_08";return true;}if(setup=="PULLBACK"&&dir>0&&hour>=13&&hour<17){name="PULLBACK_BUY_13_16";return true;}if(setup=="CONTINUATION"&&dir<0&&hour>=7&&hour<9){name="CONTINUATION_SELL_07_08";return true;}if(setup=="SWEEP"&&dir<0&&hour>=13&&hour<17){name="SWEEP_SELL_13_16";return true;}return false;}

bool RouteQuality(string setup,int dir,double rs,double adx,double vr,double br,int b1,int b4){
 if((dir>0&&b1<0)||(dir<0&&b1>0))return false;
 if((dir>0&&b4<0)||(dir<0&&b4>0))return false;
 if(setup=="PULLBACK"&&dir>0)return b1>0&&rs>49&&rs<69&&adx>=MinADX&&vr>=0.92&&br>=0.30;
 if(setup=="SWEEP"&&dir<0)return b1<0&&rs>31&&rs<53&&adx>=MinADX&&vr>=0.92&&br>=0.30;
 if(setup=="BREAKOUT"&&dir>0)return b1>=0&&adx>=MinADX&&vr>=0.90&&br>=0.30;
 if(setup=="CONTINUATION"&&dir<0)return b1<=0&&adx>=MinADX&&vr>=0.90&&br>=0.30;
 return true;
}

double BaseScore(bool buy,MqlRates &r[],double f,double s,double trend,double rs,double adx,double atr,double vr,double br,int b1,int b4){
 bool local=buy?(r[1].close>trend&&f>s):(r[1].close<trend&&f<s);if(!local)return -1000;if((buy&&b1<0)||(!buy&&b1>0))return -1000;MqlTick t;if(!SymbolInfoTick(Sym,t))return -1000;if(atr<=0||MathMax(0.0,t.ask-t.bid)>atr*MaxSpreadATRFraction)return -1000;
 double z=20;z+=((buy&&b1>0)||(!buy&&b1<0))?20:7;if((buy&&b4>0)||(!buy&&b4<0))z+=10;else if(b4==0)z+=4;else z-=8;
 if(buy){if(rs>=52&&rs<=66)z+=10;else if(rs>48&&rs<72)z+=5;}else{if(rs>=34&&rs<=48)z+=10;else if(rs>28&&rs<52)z+=5;}
 if(adx>=25)z+=10;else if(adx>=MinADX)z+=7;if(vr>=1.10)z+=10;else if(vr>=MinVolumeRatio)z+=6;if(br>=0.55)z+=8;else if(br>=MinBodyRatio)z+=4;return z;
}

void Consider(int dir,string setup,double score,double atr,int hour,double rs,double adx,double vr,double br,int b1,int b4,Candidate &c){if(score<MinSignalScore)return;if(!RouteQuality(setup,dir,rs,adx,vr,br,b1,b4))return;string route;if(!Route(setup,dir,hour,route))return;if(c.dir==0||score>c.score){c.dir=dir;c.setup=setup;c.route=route;c.score=score;c.atr=atr;}}

bool Signals(Candidate &best){
 Reset(best);int need=(int)MathMax(VolLen+10,MathMax(BreakoutLookback+10,SweepLookback+10));MqlRates r[];if(!Rates(PERIOD_M15,need,r))return false;
 double f1,f2,s1,tr,rs,atr,adx;if(!One(fH,0,1,f1)||!One(fH,0,2,f2)||!One(sH,0,1,s1)||!One(tH,0,1,tr)||!One(rH,0,1,rs)||!One(aH,0,1,atr)||!One(dH,0,1,adx)||atr<=0)return false;
 double range=r[1].high-r[1].low;if(range<=0)return false;double br=MathAbs(r[1].close-r[1].open)/range,vs=VolSma(r,2,VolLen),vr=vs>0?(double)r[1].tick_volume/vs:0;int b1=Bias(PERIOD_H1),b4=Bias(PERIOD_H4);MqlDateTime tm;TimeToStruct(TimeCurrent(),tm);
 Candidate buy,sell;Reset(buy);Reset(sell);double bb=BaseScore(true,r,f1,s1,tr,rs,adx,atr,vr,br,b1,b4),sb=BaseScore(false,r,f1,s1,tr,rs,adx,atr,vr,br,b1,b4);
 if(EnableBuy&&bb>0){double ph=HH(r,2,BreakoutLookback),pl=LL(r,2,SweepLookback);if(r[1].close>ph&&r[1].close>r[1].open&&br>=0.30&&vr>=0.90)Consider(1,"BREAKOUT",bb+24,atr,tm.hour,rs,adx,vr,br,b1,b4,buy);bool touch=r[1].low<=s1+atr*PullbackTouchATR||r[2].low<=s1+atr*PullbackTouchATR;if(touch&&r[1].close>f1&&r[1].close>r[1].open&&rs>49&&rs<69)Consider(1,"PULLBACK",bb+22,atr,tm.hour,rs,adx,vr,br,b1,b4,buy);if(r[1].close>r[2].high&&r[2].close>r[2].open&&f1>f2&&br>=0.35&&vr>=MinVolumeRatio)Consider(1,"CONTINUATION",bb+18,atr,tm.hour,rs,adx,vr,br,b1,b4,buy);if(b1>0&&r[1].low<pl&&r[1].close>pl&&r[1].close>r[1].open&&rs>45)Consider(1,"SWEEP",bb+23,atr,tm.hour,rs,adx,vr,br,b1,b4,buy);}
 if(EnableSell&&sb>0){double pl=LL(r,2,BreakoutLookback),ph=HH(r,2,SweepLookback);if(r[1].close<pl&&r[1].close<r[1].open&&br>=0.30&&vr>=0.90)Consider(-1,"BREAKOUT",sb+24,atr,tm.hour,rs,adx,vr,br,b1,b4,sell);bool touch=r[1].high>=s1-atr*PullbackTouchATR||r[2].high>=s1-atr*PullbackTouchATR;if(touch&&r[1].close<f1&&r[1].close<r[1].open&&rs>31&&rs<51)Consider(-1,"PULLBACK",sb+22,atr,tm.hour,rs,adx,vr,br,b1,b4,sell);if(r[1].close<r[2].low&&r[2].close<r[2].open&&f1<f2&&br>=0.35&&vr>=MinVolumeRatio)Consider(-1,"CONTINUATION",sb+18,atr,tm.hour,rs,adx,vr,br,b1,b4,sell);if(b1<0&&r[1].high>ph&&r[1].close<ph&&r[1].close<r[1].open&&rs<55)Consider(-1,"SWEEP",sb+23,atr,tm.hour,rs,adx,vr,br,b1,b4,sell);}
 if(buy.dir!=0&&sell.dir!=0){if(MathAbs(buy.score-sell.score)<MinDirectionScoreGap)return false;best=buy.score>sell.score?buy:sell;return true;}if(buy.dir!=0){best=buy;return true;}if(sell.dir!=0){best=sell;return true;}return false;
}

bool Open(const Candidate &c){MqlTick t;if(!SymbolInfoTick(Sym,t))return false;double entry=Price(c.dir>0?t.ask:t.bid),sl,tp;if(!Stops(c.dir,entry,c.atr,c.setup,sl,tp))return false;double lot,plan,actual;string dir=c.dir>0?"BUY":"SELL";if(!Size(c.dir,entry,sl,lot,plan,actual)){J("RISK_SKIP",dir,c.setup,c.score,entry,c.atr,"route="+c.route);return false;}
 trade.SetExpertMagicNumber((int)MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(Sym);string comment="V28 "+dir+" "+c.setup;bool ok=c.dir>0?trade.Buy(lot,Sym,0,sl,tp,comment):trade.Sell(lot,Sym,0,sl,tp,comment);
 if(!ok){J("OPEN_RETRY",dir,c.setup,c.score,entry,c.atr,StringFormat("route=%s retcode=%u lot=%.2f",c.route,trade.ResultRetcode(),lot));ok=c.dir>0?trade.Buy(lot,Sym,0,0,0,comment+" retry"):trade.Sell(lot,Sym,0,0,0,comment+" retry");if(ok){ulong tk;if(!Position(tk)||!PositionSelectByTicket(tk))ok=false;else{double ae=PositionGetDouble(POSITION_PRICE_OPEN);if(!Stops(c.dir,ae,c.atr,c.setup,sl,tp)||!trade.PositionModify(Sym,sl,tp)){trade.PositionClose(Sym);ok=false;}}}}
 if(!ok){J("OPEN_FAIL",dir,c.setup,c.score,entry,c.atr,StringFormat("route=%s retcode=%u comment=%s",c.route,trade.ResultRetcode(),trade.ResultComment()));return false;}
 tradesToday++;lastEntryTime=TimeCurrent();activeATR=c.atr;activeSetup=c.setup;activeRoute=c.route;activeScore=c.score;activeRisk=plan;J("OPEN_ENTRY",dir,c.setup,c.score,entry,c.atr,StringFormat("natural_signal=true route=%s lot=%.2f planned_risk=%.2f actual_risk=%.2f risk_pct=%.3f",c.route,lot,plan,actual,RiskPercent));return true;}

bool Close(string reason){ulong tk;if(!Position(tk)||!PositionSelectByTicket(tk))return false;string dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"BUY":"SELL";double p=PositionGetDouble(POSITION_PRICE_CURRENT);bool ok=trade.PositionClose(tk);J(ok?"CLOSE_EVENT":"CLOSE_FAIL",dir,activeSetup,activeScore,p,activeATR,"reason="+reason+" route="+activeRoute);if(ok){activeATR=0;activeSetup="";activeRoute="";activeScore=0;activeRisk=0;}return ok;}

void Manage(){ulong tk;if(!Position(tk)||!PositionSelectByTicket(tk))return;long type=PositionGetInteger(POSITION_TYPE);bool buy=type==POSITION_TYPE_BUY;double op=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);datetime ot=(datetime)PositionGetInteger(POSITION_TIME);MqlTick t;if(!SymbolInfoTick(Sym,t))return;double atr=activeATR;if(atr<=0&&(!One(aH,0,1,atr)||atr<=0))return;activeATR=atr;double mp=buy?t.bid:t.ask,fd=buy?mp-op:op-mp;MqlDateTime n;TimeToStruct(TimeCurrent(),n);if(CloseBeforeWeekend&&n.day_of_week==5&&n.hour>=FridayCloseHour){Close("WEEKEND_PROTECTION");return;}if(MaxHoldBars>0&&TimeCurrent()-ot>=MaxHoldBars*900&&fd<atr*TimeExitMinProgressATR){Close("TIME_STOP_NO_PROGRESS");return;}
 double ds=sl;bool ch=false;if(UseBreakEven&&fd>=atr*BreakEvenTriggerATR){double be=buy?op+atr*BreakEvenOffsetATR:op-atr*BreakEvenOffsetATR;if((buy&&(sl==0||be>ds))||(!buy&&(sl==0||be<ds))){ds=be;ch=true;}}if(UseTrailingStop&&fd>=atr*TrailStartATR){double ts=buy?mp-atr*TrailDistanceATR:mp+atr*TrailDistanceATR;if((buy&&(sl==0||ts>ds))||(!buy&&(sl==0||ts<ds))){ds=ts;ch=true;}}if(!ch)return;ds=Price(ds);double md=MinStop();if(buy){if(ds>=mp-md||(sl>0&&ds<=sl+Tick()))return;}else{if(ds<=mp+md||(sl>0&&ds>=sl-Tick()))return;}if(trade.PositionModify(Sym,ds,tp))J("STOP_UPDATE",buy?"BUY":"SELL",activeSetup,activeScore,mp,atr,"adaptive_protection route="+activeRoute);}

int OnInit(){Sym=InpTradeSymbol==""?_Symbol:InpTradeSymbol;if(!SymbolSelect(Sym,true)||RiskPercent<=0||RiskPercent>2)return INIT_FAILED;trade.SetExpertMagicNumber((int)MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(Sym);fH=iMA(Sym,PERIOD_M15,FastLen,0,MODE_EMA,PRICE_CLOSE);sH=iMA(Sym,PERIOD_M15,SlowLen,0,MODE_EMA,PRICE_CLOSE);tH=iMA(Sym,PERIOD_M15,TrendLen,0,MODE_EMA,PRICE_CLOSE);rH=iRSI(Sym,PERIOD_M15,RsiLen,PRICE_CLOSE);aH=iATR(Sym,PERIOD_M15,AtrLen);dH=iADX(Sym,PERIOD_M15,AdxLen);h1f=iMA(Sym,PERIOD_H1,BiasFastLen,0,MODE_EMA,PRICE_CLOSE);h1s=iMA(Sym,PERIOD_H1,BiasSlowLen,0,MODE_EMA,PRICE_CLOSE);h1r=iRSI(Sym,PERIOD_H1,RsiLen,PRICE_CLOSE);h4f=iMA(Sym,PERIOD_H4,BiasFastLen,0,MODE_EMA,PRICE_CLOSE);h4s=iMA(Sym,PERIOD_H4,BiasSlowLen,0,MODE_EMA,PRICE_CLOSE);h4r=iRSI(Sym,PERIOD_H4,RsiLen,PRICE_CLOSE);if(fH==INVALID_HANDLE||sH==INVALID_HANDLE||tH==INVALID_HANDLE||rH==INVALID_HANDLE||aH==INVALID_HANDLE||dH==INVALID_HANDLE||h1f==INVALID_HANDLE||h1s==INVALID_HANDLE||h1r==INVALID_HANDLE||h4f==INVALID_HANDLE||h4s==INVALID_HANDLE||h4r==INVALID_HANDLE)return INIT_FAILED;ResetDay();J("EA_START","","",0,0,0,"V28_CONTEXTUAL_ROUTER risk_normalized=true quality_gate=balanced_htf_alignment routes=BREAKOUT_BUY_07_08|PULLBACK_BUY_13_16|CONTINUATION_SELL_07_08|SWEEP_SELL_13_16");return INIT_SUCCEEDED;}
void OnDeinit(const int reason){IndicatorRelease(fH);IndicatorRelease(sH);IndicatorRelease(tH);IndicatorRelease(rH);IndicatorRelease(aH);IndicatorRelease(dH);IndicatorRelease(h1f);IndicatorRelease(h1s);IndicatorRelease(h1r);IndicatorRelease(h4f);IndicatorRelease(h4s);IndicatorRelease(h4r);}
void OnTick(){ResetDay();Manage();ulong tk;if(Position(tk)||!SessionOpen()||tradesToday>=MaxTradesPerDay||(lastEntryTime>0&&TimeCurrent()-lastEntryTime<CooldownMinutes*60)||!NewBar())return;Candidate c;if(Signals(c))Open(c);}
