import os
import sys
import time
import datetime as dt

try:
    import MetaTrader5 as mt5
except Exception as exc:
    print("IMPORT_ERROR", repr(exc))
    sys.exit(10)


def env(name, default=""):
    return os.environ.get(name, default).strip()


def parse_date(value, add_day=False):
    parsed = dt.datetime.strptime(value, "%Y.%m.%d")
    if add_day:
        parsed += dt.timedelta(days=1)
    return parsed.replace(tzinfo=dt.timezone.utc)


TIMEFRAMES = {
    "M1": mt5.TIMEFRAME_M1,
    "M5": mt5.TIMEFRAME_M5,
    "M15": mt5.TIMEFRAME_M15,
    "M30": mt5.TIMEFRAME_M30,
    "H1": mt5.TIMEFRAME_H1,
    "H4": mt5.TIMEFRAME_H4,
    "D1": mt5.TIMEFRAME_D1,
}

terminal_path = env("MT5_TERMINAL_PATH")
login = int(env("MT5_LOGIN"))
secret = env("MT5_PASSWORD")
server = env("MT5_SERVER")
symbol = env("BT_SYMBOL", "XAUUSD")
period = env("BT_PERIOD", "M15").upper()
from_s = env("BT_FROM_DATE", "2025.01.01")
to_s = env("BT_TO_DATE", "2025.01.15")
sync_minutes = max(3, min(60, int(env("BT_SYNC_MINUTES", "15"))))
data_path_file = env("MT5_DATA_PATH_FILE")

print("terminal_path=", terminal_path)
print("server=", server)
print("login=", login)
print("symbol=", symbol)
print("period=", period)
print("from=", from_s, "to=", to_s, "sync_minutes=", sync_minutes)

connected = False
attempts = max(4, min(20, sync_minutes))
for attempt in range(1, attempts + 1):
    print(f"initialize_attempt={attempt}/{attempts}")
    methods = [
        ("normal", dict(path=terminal_path, timeout=90000)),
        ("with_login", dict(path=terminal_path, login=login, password=secret, server=server, timeout=90000)),
        ("portable", dict(path=terminal_path, timeout=90000, portable=True)),
    ]
    for label, kwargs in methods:
        ok = mt5.initialize(**kwargs)
        print(f"initialize_{label}=", ok, "last_error=", mt5.last_error())
        if ok:
            login_ok = mt5.login(login, password=secret, server=server, timeout=90000)
            print("login_result=", login_ok, "last_error=", mt5.last_error())
            if login_ok:
                connected = True
                break
            mt5.shutdown()
    if connected:
        break
    time.sleep(30)

if not connected:
    print("IPC_OR_LOGIN_FAILED_AFTER_RETRIES")
    sys.exit(12)

account = mt5.account_info()
print("account_info=", account)
if account is None:
    print("NO_ACCOUNT_INFO", mt5.last_error())
    mt5.shutdown()
    sys.exit(13)

term_info = mt5.terminal_info()
print("terminal_info=", term_info)
if data_path_file and term_info is not None:
    with open(data_path_file, "w", encoding="utf-8") as f:
        f.write(str(term_info.data_path))
    print("DATA_PATH_WRITTEN=", term_info.data_path)

symbols = mt5.symbols_get()
if symbols is None:
    print("SYMBOLS_GET_FAILED", mt5.last_error())
    symbols = []

names = [item.name for item in symbols]
gold_candidates = sorted([name for name in names if "XAU" in name.upper() or "GOLD" in name.upper()])
print("XAU/GOLD candidates count=", len(gold_candidates))
print("XAU/GOLD candidates=", gold_candidates[:150])

if symbol not in names:
    print(f"REQUESTED_SYMBOL_NOT_FOUND: {symbol}")
    print("Use one exact candidate from XAU/GOLD candidates as workflow symbol.")
    mt5.shutdown()
    sys.exit(14)

print("symbol_info_before_select=", mt5.symbol_info(symbol))
if not mt5.symbol_select(symbol, True):
    print("SYMBOL_SELECT_FAILED", mt5.last_error())
    mt5.shutdown()
    sys.exit(15)

start = parse_date(from_s)
end = parse_date(to_s, add_day=True)
requested_tf = TIMEFRAMES.get(period, mt5.TIMEFRAME_M15)


def fetch_rates(tf_name, tf):
    last_count = 0
    for attempt in range(1, sync_minutes + 1):
        rates = mt5.copy_rates_range(symbol, tf, start, end)
        count = 0 if rates is None else len(rates)
        print(f"fetch_rates attempt={attempt}/{sync_minutes} tf={tf_name} count={count} last_error={mt5.last_error()}")
        if count > 0:
            print("first_bar=", rates[0])
            print("last_bar=", rates[-1])
            return count
        last_count = count
        time.sleep(60)
    return last_count

m1_count = fetch_rates("M1", mt5.TIMEFRAME_M1)
tf_count = fetch_rates(period, requested_tf) if period != "M1" else m1_count

tick_end = min(end, start + dt.timedelta(days=2))
ticks = mt5.copy_ticks_range(symbol, start, tick_end, mt5.COPY_TICKS_ALL)
tick_count = 0 if ticks is None else len(ticks)
print("tick_probe_count_first_2_days=", tick_count, "last_error=", mt5.last_error())

mt5.shutdown()

if m1_count <= 0 and tf_count <= 0:
    print("NO_HISTORY_DOWNLOADED_FOR_SYMBOL")
    print("Most likely causes: wrong symbol, wrong server, broker blocks history on runner, or demo lacks XAU/GOLD data.")
    sys.exit(20)

print("PREFETCH_OK m1_count=", m1_count, "tf_count=", tf_count, "tick_probe_count=", tick_count)
sys.exit(0)
