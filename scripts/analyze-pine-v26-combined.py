import argparse, csv, json, re
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

MODES = ["sell_only", "sell_buy_quality", "sell_buy_frequency"]
PRIORITIES = ["sell_first", "buy_first"]


def dec(b):
    for e in ("utf-8", "utf-16", "cp1252", "latin1"):
        try: return b.decode(e, errors="replace")
        except Exception: pass
    return b.decode("utf-8", errors="replace")

def blob(root):
    out=[]
    for p in root.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".txt",".log",".json",".csv",".html",".htm"}:
            try: out.append(dec(p.read_bytes()))
            except Exception: pass
    return "\n".join(out)

def dates(text):
    fm=re.search(r"public_forced_from_date=(\d{4}\.\d{2}\.\d{2})",text) or re.search(r"input_from_date=(\d{4}\.\d{2}\.\d{2})",text)
    tm=re.search(r"public_forced_to_date=(\d{4}\.\d{2}\.\d{2})",text) or re.search(r"input_to_date=(\d{4}\.\d{2}\.\d{2})",text)
    return (datetime.strptime(fm.group(1),"%Y.%m.%d") if fm else None, datetime.strptime(tm.group(1),"%Y.%m.%d")+timedelta(days=1) if tm else None)

def load(root):
    fs=list(root.rglob("xau_public_m1.csv"))
    if not fs: return []
    rows=[]
    with fs[0].open("r",encoding="utf-8",newline="") as f:
        for r in csv.DictReader(f):
            try: rows.append({"time":datetime.strptime(r["time"],"%Y.%m.%d %H:%M"),"open":float(r["open"]),"high":float(r["high"]),"low":float(r["low"]),"close":float(r["close"]),"volume":float(r.get("tick_volume") or r.get("volume") or 0)})
            except Exception: pass
    rows.sort(key=lambda x:x["time"]); return rows

def buck(t,m):
    n=t.hour*60+t.minute; b=(n//m)*m
    return t.replace(hour=b//60,minute=b%60,second=0,microsecond=0)

def resample(rows,m):
    out=[]; key=None; cur=None
    for r in rows:
        k=buck(r["time"],m)
        if k!=key:
            if cur: out.append(cur)
            key=k; cur={"time":k,"open":r["open"],"high":r["high"],"low":r["low"],"close":r["close"],"volume":r["volume"]}
        else:
            cur["high"]=max(cur["high"],r["high"]); cur["low"]=min(cur["low"],r["low"]); cur["close"]=r["close"]; cur["volume"]+=r["volume"]
    if cur: out.append(cur)
    return out

def ema(v,n):
    out=[None]*len(v); a=2/(n+1); p=None
    for i,x in enumerate(v):
        p=x if p is None else a*x+(1-a)*p; out[i]=p
    return out

def rma(v,n):
    out=[None]*len(v)
    if len(v)<n: return out
    p=sum(v[:n])/n; out[n-1]=p
    for i in range(n,len(v)):
        p=(p*(n-1)+v[i])/n; out[i]=p
    return out

def rsi(c,n=14):
    g=[0]; l=[0]
    for i in range(1,len(c)):
        d=c[i]-c[i-1]; g.append(max(d,0)); l.append(max(-d,0))
    ag,al=rma(g,n),rma(l,n); out=[None]*len(c)
    for i in range(len(c)):
        if ag[i] is not None and al[i] is not None: out[i]=100 if al[i]==0 else 100-100/(1+ag[i]/al[i])
    return out

def atr(bars,n=14):
    tr=[]; pc=None
    for b in bars:
        x=b["high"]-b["low"] if pc is None else max(b["high"]-b["low"],abs(b["high"]-pc),abs(b["low"]-pc))
        tr.append(x); pc=b["close"]
    return rma(tr,n)

def sma(v,n,i): return None if i+1<n else sum(v[i-n+1:i+1])/n

def enrich(bars):
    c=[b["close"] for b in bars]; v=[b["volume"] for b in bars]
    f,s,t,rs,at=ema(c,9),ema(c,21),ema(c,200),rsi(c,14),atr(bars,14)
    for i,b in enumerate(bars): b.update({"ema9":f[i],"ema21":s[i],"ema200":t[i],"rsi":rs[i],"atr":at[i],"volsma":sma(v,20,i),"slope":None if i<3 or t[i] is None or t[i-3] is None else t[i]-t[i-3]})
    return bars

def session(t): return t.weekday()<5 and 8<=t.hour<21 and not (t.weekday()==4 and t.hour>=16)

def sell_sigs(h1,start,end):
    out=[]
    for i,b in enumerate(h1):
        if i<2: continue
        et=b["time"]+timedelta(minutes=55)
        if start and et<start: continue
        if end and et>=end: continue
        if not session(et): continue
        vals=[b.get("ema9"),b.get("ema21"),h1[i-1].get("ema9"),h1[i-1].get("ema21"),b.get("ema200"),b.get("rsi"),b.get("atr"),b.get("volsma")]
        if any(x is None for x in vals): continue
        ok=b["ema9"]<b["ema21"] and h1[i-1]["ema9"]>=h1[i-1]["ema21"] and b["close"]<b["ema200"] and 32<b["rsi"]<50 and b["volume"]>b["volsma"]*0.8
        if ok: out.append({"time":et,"src":b["time"],"side":"SELL","entry":b["close"],"atr":b["atr"],"profile":"V24_SELL"})
    return out

def buy_sigs(m15,start,end,kind):
    out=[]
    for i,b in enumerate(m15):
        if i<5: continue
        et=b["time"]+timedelta(minutes=10)
        if start and et<start: continue
        if end and et>=end: continue
        if not session(et): continue
        vals=[b.get("ema9"),b.get("ema21"),b.get("ema200"),b.get("rsi"),b.get("atr"),b.get("volsma"),b.get("slope")]
        if any(x is None for x in vals): continue
        rng=b["high"]-b["low"]; body=0 if rng==0 else abs(b["close"]-b["open"])/rng
        trend=b["close"]>b["ema200"] and b["ema9"]>b["ema21"] and b["slope"]>0 and 50<b["rsi"]<70 and b["volume"]>b["volsma"]*0.8 and body>=0.25
        if not trend: continue
        breakout=b["close"]>max(x["high"] for x in m15[i-3:i])
        momentum=b["close"]>b["open"] and b["close"]>m15[i-1]["high"]
        ok=breakout if kind=="quality" else momentum
        if ok: out.append({"time":et,"src":b["time"],"side":"BUY","entry":b["close"],"atr":b["atr"],"profile":"V25_BUY_"+kind.upper()})
    return out

def simulate(m5, signals, mode, priority, deposit):
    by=defaultdict(list)
    for s in signals: by[s["time"]].append(s)
    bal=deposit; balances=[deposit]; pos=None; trades=[]; td=0; day=None; last=None; blocked={"position":0,"cooldown":0,"daily":0}
    for b in m5:
        t=b["time"]; dk=t.strftime("%Y%m%d")
        if dk!=day: day=dk; td=0
        if pos:
            if pos["side"]=="BUY":
                tp=pos["entry"]+pos["atr"]*1.0; sl=pos["entry"]-pos["atr"]*2.0; hit_tp=b["high"]>=tp; hit_sl=b["low"]<=sl
            else:
                tp=pos["entry"]-pos["atr"]*2.5; sl=pos["entry"]+pos["atr"]*2.0; hit_tp=b["low"]<=tp; hit_sl=b["high"]>=sl
            if hit_tp or hit_sl:
                px=sl if hit_sl else tp; pts=px-pos["entry"] if pos["side"]=="BUY" else pos["entry"]-px; bal+=pts; balances.append(bal)
                trades.append({**pos,"exit_time":t,"exit":round(px,5),"exit_reason":"SL" if hit_sl else "TP","profit_money":round(pts,2),"balance_after":round(bal,2),"hold_minutes":int((t-pos["entry_time"]).total_seconds()//60)})
                pos=None
        sigs=by.get(t,[])
        if not sigs: continue
        if priority=="sell_first": sigs.sort(key=lambda x: 0 if x["side"]=="SELL" else 1)
        else: sigs.sort(key=lambda x: 0 if x["side"]=="BUY" else 1)
        s=sigs[0]
        if pos: blocked["position"]+=1; continue
        if td>=6: blocked["daily"]+=1; continue
        if last and (t-last).total_seconds()<30*60: blocked["cooldown"]+=1; continue
        pos={"entry_time":t,"source_time":s["src"],"side":s["side"],"entry":round(s["entry"],5),"atr":round(s["atr"],5),"profile":s["profile"],"mode":mode,"priority":priority}
        td+=1; last=t
    wins=sum(1 for x in trades if x["profit_money"]>0); gp=sum(x["profit_money"] for x in trades if x["profit_money"]>0); gl=sum(x["profit_money"] for x in trades if x["profit_money"]<0)
    peak=balances[0]; dd=0
    for x in balances: peak=max(peak,x); dd=min(dd,x-peak)
    days=len(set(x["entry_time"].strftime("%Y-%m-%d") for x in trades))
    by_side={}
    for side in ["BUY","SELL"]:
        ts=[x for x in trades if x["side"]==side]; by_side[side]={"trades":len(ts),"net":round(sum(x["profit_money"] for x in ts),2),"wins":sum(1 for x in ts if x["profit_money"]>0)}
    rows=[]
    for x in trades:
        r=dict(x); r["entry_time"]=x["entry_time"].strftime("%Y-%m-%d %H:%M:%S"); r["source_time"]=x["source_time"].strftime("%Y-%m-%d %H:%M:%S"); r["exit_time"]=x["exit_time"].strftime("%Y-%m-%d %H:%M:%S"); rows.append(r)
    return {"mode":mode,"priority":priority,"net_profit":round(bal-deposit,2),"final_balance":round(bal,2),"closed_trades":len(trades),"wins":wins,"losses":len(trades)-wins,"win_rate":round(wins/len(trades),3) if trades else None,"profit_factor":round(gp/abs(gl),3) if gl else None,"max_closed_drawdown_money":round(dd,2),"avg_trades_per_trade_day":round(len(trades)/days,2) if days else None,"by_side":by_side,"blocked":blocked,"trades":rows}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("reports_dir"); ap.add_argument("--deposit",type=float,default=10000.0); args=ap.parse_args()
    root=Path(args.reports_dir); text=blob(root); start,end=dates(text); m1=load(root)
    if not m1: print(json.dumps({"verdict":"NO_HISTORY"})); return 0
    m5=[b for b in enrich(resample(m1,5)) if (not start or b["time"]>=start) and (not end or b["time"]<end)]
    h1=enrich(resample(m1,60)); m15=enrich(resample(m1,15))
    sells=sell_sigs(h1,start,end); buys_q=buy_sigs(m15,start,end,"quality"); buys_f=buy_sigs(m15,start,end,"frequency")
    tests=[]
    for mode,sigs in [("sell_only",sells),("sell_buy_quality",sells+buys_q),("sell_buy_frequency",sells+buys_f)]:
        for pri in PRIORITIES: tests.append(simulate(m5,sigs,mode,pri,args.deposit))
    tests.sort(key=lambda x:(x["net_profit"],x.get("profit_factor") or 0,x.get("win_rate") or 0,x["closed_trades"]),reverse=True)
    clean=lambda x:{k:v for k,v in x.items() if k!="trades"}
    final={"verdict":"DONE","engine":"V26_COMBINED_REAL_ONE_POSITION_COOLDOWN_30","signal_counts":{"sell":len(sells),"buy_quality":len(buys_q),"buy_frequency":len(buys_f)},"best_by_profit":clean(tests[0]),"all_results":[clean(x) for x in tests]}
    (root/"PINE_V26_COMBINED_BACKTEST.json").write_text(json.dumps(final,indent=2),encoding="utf-8")
    with (root/"PINE_V26_COMBINED_RESULTS.csv").open("w",encoding="utf-8",newline="") as f:
        fields=["rank","mode","priority","net_profit","final_balance","closed_trades","wins","losses","win_rate","profit_factor","max_closed_drawdown_money","avg_trades_per_trade_day"]
        wr=csv.DictWriter(f,fieldnames=fields,extrasaction="ignore"); wr.writeheader(); [wr.writerow({"rank":i,**r}) for i,r in enumerate(tests,1)]
    with (root/"PINE_V26_COMBINED_BEST_TRADES.csv").open("w",encoding="utf-8",newline="") as f:
        fields=["entry_time","source_time","side","profile","entry","atr","mode","priority","exit_time","exit","exit_reason","profit_money","balance_after","hold_minutes"]
        wr=csv.DictWriter(f,fieldnames=fields,extrasaction="ignore"); wr.writeheader(); [wr.writerow(t) for t in tests[0].get("trades",[])]
    print(json.dumps(final,indent=2)); return 0
if __name__=="__main__": raise SystemExit(main())
