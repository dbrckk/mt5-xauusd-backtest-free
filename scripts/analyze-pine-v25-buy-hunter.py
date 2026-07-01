import argparse, csv, json, re
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

TF_GRID = [5, 15, 30, 60]
TRIG_GRID = ["cross", "pullback", "breakout", "momentum"]
CONF_GRID = ["none", "h1", "m15m30h1", "h1_no_h2_bear", "h1_no_h2h4_bear"]
TP_GRID = [1.0, 1.25, 1.5, 1.8, 2.2, 2.5, 3.0]
SL_GRID = [0.6, 0.8, 1.0, 1.2, 1.5, 2.0]
RSI_GRID = [(48, 68), (50, 70), (52, 68), (55, 72)]


def decode(b):
    for enc in ("utf-8", "utf-16", "cp1252", "latin1"):
        try: return b.decode(enc, errors="replace")
        except Exception: pass
    return b.decode("utf-8", errors="replace")

def blob(root):
    out=[]
    for p in root.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".txt",".log",".json",".csv",".html",".htm"}:
            try: out.append(decode(p.read_bytes()))
            except Exception: pass
    return "\n".join(out)

def parse_dates(text):
    fm=re.search(r"public_forced_from_date=(\d{4}\.\d{2}\.\d{2})",text) or re.search(r"input_from_date=(\d{4}\.\d{2}\.\d{2})",text)
    tm=re.search(r"public_forced_to_date=(\d{4}\.\d{2}\.\d{2})",text) or re.search(r"input_to_date=(\d{4}\.\d{2}\.\d{2})",text)
    start=datetime.strptime(fm.group(1),"%Y.%m.%d") if fm else None
    end=datetime.strptime(tm.group(1),"%Y.%m.%d")+timedelta(days=1) if tm else None
    return start,end

def load_m1(root):
    files=list(root.rglob("xau_public_m1.csv"))
    if not files: return []
    rows=[]
    with files[0].open("r",encoding="utf-8",newline="") as f:
        for r in csv.DictReader(f):
            try:
                rows.append({"time":datetime.strptime(r["time"],"%Y.%m.%d %H:%M"),"open":float(r["open"]),"high":float(r["high"]),"low":float(r["low"]),"close":float(r["close"]),"volume":float(r.get("tick_volume") or r.get("volume") or 0)})
            except Exception: pass
    rows.sort(key=lambda x:x["time"]); return rows

def bucket(t,m):
    total=t.hour*60+t.minute; b=(total//m)*m
    return t.replace(hour=b//60,minute=b%60,second=0,microsecond=0)

def resample(rows,m):
    out=[]; key=None; cur=None
    for r in rows:
        k=bucket(r["time"],m)
        if k!=key:
            if cur: out.append(cur)
            key=k; cur={"time":k,"open":r["open"],"high":r["high"],"low":r["low"],"close":r["close"],"volume":r["volume"]}
        else:
            cur["high"]=max(cur["high"],r["high"]); cur["low"]=min(cur["low"],r["low"]); cur["close"]=r["close"]; cur["volume"]+=r["volume"]
    if cur: out.append(cur)
    return out

def ema(vals,n):
    out=[None]*len(vals); a=2/(n+1); prev=None
    for i,v in enumerate(vals):
        prev=v if prev is None else a*v+(1-a)*prev; out[i]=prev
    return out

def rma(vals,n):
    out=[None]*len(vals)
    if len(vals)<n: return out
    prev=sum(vals[:n])/n; out[n-1]=prev
    for i in range(n,len(vals)):
        prev=(prev*(n-1)+vals[i])/n; out[i]=prev
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
    for i,b in enumerate(bars):
        b.update({"ema9":f[i],"ema21":s[i],"ema200":t[i],"rsi":rs[i],"atr":at[i],"volsma":sma(v,20,i),"slope":None if i<3 or t[i] is None or t[i-3] is None else t[i]-t[i-3]})
    return bars

def session(t): return t.weekday()<5 and 8<=t.hour<21 and not (t.weekday()==4 and t.hour>=16)

def state_maps(bars_by_tf):
    maps={}
    for tf,bars in bars_by_tf.items():
        if tf==5: continue
        mp={}
        for b in bars:
            if None in (b.get("ema9"),b.get("ema21"),b.get("ema200"),b.get("rsi"),b.get("slope")): continue
            bull=b["close"]>b["ema200"] and b["ema9"]>b["ema21"] and b["slope"]>0 and b["rsi"]>50
            bear=b["close"]<b["ema200"] and b["ema9"]<b["ema21"] and b["slope"]<0 and b["rsi"]<50
            mp[b["time"]+timedelta(minutes=tf-5)]=1 if bull else -1 if bear else 0
        maps[tf]=mp
    return maps

def build_state_timeline(m5,maps):
    cur={15:0,30:0,60:0,120:0,240:0}; out={}
    for b in m5:
        for tf,mp in maps.items():
            if b["time"] in mp: cur[tf]=mp[b["time"]]
        out[b["time"]]=dict(cur)
    return out

def signal_list(bars,tf,trig,rlo,rhi,vol_mult,body_min,start,end):
    out=[]
    for i,b in enumerate(bars):
        if i<5: continue
        et=b["time"]+timedelta(minutes=tf-5)
        if start and et<start: continue
        if end and et>=end: continue
        if not session(et): continue
        if None in (b.get("ema9"),b.get("ema21"),b.get("ema200"),b.get("rsi"),b.get("atr"),b.get("volsma"),b.get("slope")): continue
        rng=b["high"]-b["low"]; body=0 if rng==0 else abs(b["close"]-b["open"])/rng
        trend=b["close"]>b["ema200"] and b["ema9"]>b["ema21"] and b["slope"]>0 and rlo<b["rsi"]<rhi and b["volume"]>b["volsma"]*vol_mult and body>=body_min
        if not trend: continue
        if trig=="cross": ok=b["ema9"]>b["ema21"] and bars[i-1]["ema9"]<=bars[i-1]["ema21"]
        elif trig=="pullback": ok=b["close"]>b["ema9"] and b["low"]<=b["ema9"] and b["close"]>b["open"]
        elif trig=="breakout": ok=b["close"]>max(x["high"] for x in bars[i-3:i])
        else: ok=b["close"]>b["open"] and b["close"]>bars[i-1]["high"]
        if ok: out.append({"time":et,"source":b["time"],"entry":b["close"],"atr":b["atr"],"tf":tf,"trigger":trig})
    return out

def conf_ok(t,conf,states):
    st=states.get(t,{})
    if conf=="none": return True
    if conf=="h1": return st.get(60,0)==1
    if conf=="m15m30h1": return st.get(15,0)==1 and st.get(30,0)==1 and st.get(60,0)==1
    if conf=="h1_no_h2_bear": return st.get(60,0)==1 and st.get(120,0)!=-1
    if conf=="h1_no_h2h4_bear": return st.get(60,0)==1 and st.get(120,0)!=-1 and st.get(240,0)!=-1
    return True

def simulate(m5,sigs,tp,sl,max_day=4,cool=90):
    by=defaultdict(list)
    for s in sigs: by[s["time"]].append(s)
    bal=10000.0; pos=None; trades=[]; day=None; td=0; last=None; balances=[bal]
    for b in m5:
        t=b["time"]; dk=t.strftime("%Y%m%d")
        if dk!=day: day=dk; td=0
        if pos:
            target=pos["entry"]+pos["atr"]*tp; stop=pos["entry"]-pos["atr"]*sl
            hit_tp=b["high"]>=target; hit_sl=b["low"]<=stop
            if hit_tp or hit_sl:
                px=stop if hit_sl else target
                profit=px-pos["entry"]; bal+=profit; balances.append(bal)
                trades.append({**pos,"exit_time":t,"exit":round(px,5),"exit_reason":"SL" if hit_sl else "TP","profit_money":round(profit,2),"balance_after":round(bal,2),"hold_minutes":int((t-pos["entry_time"]).total_seconds()//60)})
                pos=None
        if t in by and pos is None and td<max_day and (last is None or (t-last).total_seconds()>=cool*60):
            s=by[t][0]
            pos={"entry_time":t,"source_time":s["source"],"dir":"BUY","entry":round(s["entry"],5),"atr":round(s["atr"],5),"tf":s["tf"],"trigger":s["trigger"]}
            td+=1; last=t
    wins=sum(1 for x in trades if x["profit_money"]>0); gp=sum(x["profit_money"] for x in trades if x["profit_money"]>0); gl=sum(x["profit_money"] for x in trades if x["profit_money"]<0)
    peak=balances[0]; dd=0
    for x in balances: peak=max(peak,x); dd=min(dd,x-peak)
    days=len(set(x["entry_time"].strftime("%Y-%m-%d") for x in trades))
    for x in trades:
        x["entry_time"]=x["entry_time"].strftime("%Y-%m-%d %H:%M:%S"); x["source_time"]=x["source_time"].strftime("%Y-%m-%d %H:%M:%S"); x["exit_time"]=x["exit_time"].strftime("%Y-%m-%d %H:%M:%S")
    return {"net_profit":round(bal-10000,2),"closed_trades":len(trades),"wins":wins,"losses":len(trades)-wins,"win_rate":round(wins/len(trades),3) if trades else None,"profit_factor":round(gp/abs(gl),3) if gl else None,"max_closed_drawdown_money":round(dd,2),"avg_trades_per_trade_day":round(len(trades)/days,2) if days else None,"trades":trades}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("reports_dir"); ap.add_argument("--deposit",type=float,default=10000.0); args=ap.parse_args()
    root=Path(args.reports_dir); text=blob(root); start,end=parse_dates(text); m1=load_m1(root)
    if not m1:
        print(json.dumps({"verdict":"NO_HISTORY"})); return 0
    bars={tf:enrich(resample(m1,tf)) for tf in [5,15,30,60,120,240]}
    m5=[b for b in bars[5] if (not start or b["time"]>=start) and (not end or b["time"]<end)]
    states=build_state_timeline(m5,state_maps(bars))
    results=[]
    for tf in TF_GRID:
      for trig in TRIG_GRID:
        for rlo,rhi in RSI_GRID:
          base=signal_list(bars[tf],tf,trig,rlo,rhi,0.8,0.25,start,end)
          for conf in CONF_GRID:
            sigs=[s for s in base if conf_ok(s["time"],conf,states)]
            if len(sigs)<2: continue
            for tp in TP_GRID:
              for sl in SL_GRID:
                res=simulate(m5,sigs,tp,sl)
                results.append({"tf":tf,"trigger":trig,"conf":conf,"rsi_min":rlo,"rsi_max":rhi,"signals":len(sigs),"tp":tp,"sl":sl,**res})
    results.sort(key=lambda x:(x["net_profit"],x.get("profit_factor") or 0,x.get("win_rate") or 0,x["closed_trades"]),reverse=True)
    clean=lambda x:{k:v for k,v in x.items() if k!="trades"}
    final={"verdict":"DONE","engine":"V25_BUY_HUNTER_OPTIMIZER","goal":"Find BUY-only add-on candidates to increase total trade count without weakening V24 SELL Ultimate","variant_count":len(results),"best_by_profit":clean(results[0]) if results else None,"top_20":[clean(x) for x in results[:20]]}
    (root/"PINE_V25_BUY_HUNTER_OPTIMIZATION.json").write_text(json.dumps(final,indent=2),encoding="utf-8")
    with (root/"PINE_V25_BUY_HUNTER_VARIANTS.csv").open("w",encoding="utf-8",newline="") as f:
        fields=["rank","tf","trigger","conf","rsi_min","rsi_max","signals","tp","sl","net_profit","closed_trades","wins","losses","win_rate","profit_factor","max_closed_drawdown_money","avg_trades_per_trade_day"]
        wr=csv.DictWriter(f,fieldnames=fields,extrasaction="ignore"); wr.writeheader()
        for i,r in enumerate(results,1): wr.writerow({"rank":i,**r})
    if results:
        with (root/"PINE_V25_BUY_HUNTER_BEST_TRADES.csv").open("w",encoding="utf-8",newline="") as f:
            fields=["entry_time","source_time","dir","tf","trigger","entry","atr","exit_time","exit","exit_reason","profit_money","balance_after","hold_minutes"]
            wr=csv.DictWriter(f,fieldnames=fields,extrasaction="ignore"); wr.writeheader(); [wr.writerow(t) for t in results[0].get("trades",[])]
    print(json.dumps(final,indent=2)); return 0

if __name__=="__main__":
    raise SystemExit(main())
