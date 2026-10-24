---
name: argusdesk
description: Your own quant desk: iShares peers, Bloomberg causal-ts drivers, Goldman gs-quant risk, Kronos forecast, BlackRock HOLA-tuned backtest, Alpaca paper trade. Use for "what drives X".
---

# ArgusDesk: peers, cause, risk, forecast, backtest, paper trade

One workflow built on official open-source libraries and free data:
- **BlackRock iShares** ETF holdings (a free CSV on ishares.com) pick the stock's real peers by fund weight.
- **Bloomberg causal-ts** (`pip install causalts`) finds who moves whom, and at what lag.
- **Goldman Sachs gs-quant** (`pip install gs-quant`) measures risk with its `gs_quant.timeseries` math. These functions run locally and need no Goldman login.
- **Kronos** (Tsinghua, MIT) forecasts the next 5 days of candles on CPU.
- **BlackRock HOLA** (Apache-2.0) tunes the trading rule on training data only.
- **Vibe-Trading** (HKU, MIT): the skill runs its three backtest checks (Bootstrap, Monte Carlo, Walk-Forward). Its optional MCP adds SEC 13F fund holdings.
- **Alpaca** (`pip install alpaca-py`) runs the rule on a free paper-trading account. This step is optional.

Work through the steps in order. Show the user a one-line status before each step. Never present results as financial advice.

**Auto-run mode.** When the prompt contains "auto-run" (a daily scheduled run), nobody is watching:
- Ask no questions. Use the ticker from the prompt and the default drivers from step 1.
- Skip steps 7 and 8. Never place an order in auto-run.
- Install missing packages yourself, and keep going if an optional step fails.
- Start the report with one line: date, ticker, tomorrow's signal, Kronos 5-day direction.
- Save it as `argusdesk_report.md` and as `argusdesk_<TICKER>_<YYYY-MM-DD>.md` in the current folder.

## 0. Setup

```bash
pip install causalts gs-quant yfinance pandas numpy requests
```

Check that `causal-ts --help` works. Kronos, HOLA and Vibe-Trading are installed in their own steps. Install `alpaca-py` only if the user wants step 8.

## 1. Pick the universe

- **Target:** the ticker the user named. If they named none, ask for one.
- **Candidate drivers:** 5-8 series, unless the user gave their own:
  - The target's iShares sector ETF, e.g. SOXX for chips.
  - 2-3 peers from that ETF's holdings (BlackRock iShares, see below). Add a key supplier or customer that isn't in the ETF, e.g. TSM for NVDA.
  - The market: SPY or QQQ.
  - Rates: TLT.
  - The dollar: UUP.
- Window: 2 years of daily data unless the user asks otherwise.

**Peers from BlackRock iShares holdings (free, no login).** iShares ETF pages on ishares.com have a "Download latest fund holdings CSV data" link ending in `latest-holdings.csv`. Find the page for the target's sector ETF and use that link. Example for SOXX:

```python
import io, requests, pandas as pd
url = "https://www.ishares.com/us/products/239705/ishares-semiconductor-etf/latest-holdings.csv"
lines = requests.get(url, headers={"User-Agent": "Mozilla/5.0"}, timeout=30).text.splitlines()
asof = next((l.split(",", 1)[1].strip('"') for l in lines if l.startswith("Fund Holdings as of")), "?")
start = next(i for i, l in enumerate(lines) if l.startswith("Ticker,"))
h = pd.read_csv(io.StringIO("\n".join(lines[start:])), on_bad_lines="skip")
h = h[h["Asset Class"] == "Equity"].dropna(subset=["Ticker"])
h["Weight (%)"] = pd.to_numeric(h["Weight (%)"], errors="coerce")
top = h.sort_values("Weight (%)", ascending=False)[["Ticker", "Name", "Weight (%)"]].head(10)
```

- Pick the 2-3 biggest holdings other than the target as peers. Also say the target's own weight in the fund.
- Tell the user: "peers from iShares <ETF> holdings as of <asof>".
- If the download fails or the target has no iShares sector ETF, pick peers yourself and say so.

Tell the user the list in one line and continue. Don't wait for approval unless they asked to choose.

## 2. Get the data

```python
import yfinance as yf, numpy as np, pandas as pd
tickers = ["NVDA", "TSM", "SOXX", "QQQ", "TLT", "UUP"]  # target first
px = yf.download(tickers, period="2y", interval="1d", auto_adjust=True, progress=False)["Close"]
px = px.dropna()
rets = np.log(px).diff().dropna()          # log returns, roughly stationary
split = int(len(rets) * 0.7)               # 70% to discover, 30% held out
rets.iloc[:split].to_csv("qd_train.csv", index_label="date")
rets.to_csv("qd_all.csv", index_label="date")
px.to_csv("qd_prices.csv", index_label="date")
```

- If a ticker fails to download, drop it and say so.
- Discover on `qd_train.csv` only. The last 30% stays unseen until the backtest, so the test is honest.

## 3. Find what moves the target (Bloomberg causal-ts)

1. **Inspect:**
   ```bash
   causal-ts inspect qd_train.csv
   ```
   - It returns JSON with `facts`, `recommendation`, `cost_class` and `warnings`. Use it; don't re-derive the facts.
   - Tell the user every warning.
   - The data is already log returns, so you may drop the C node (`include_C`) if the tool suggests it for trends.
   - Run `causal-ts ci-test-info` if you're unsure about the CI test.
2. **Cost gate:**
   - `cheap`: run it.
   - `moderate`: run it and say what you're running.
   - `expensive`: offer a cheaper config first, and stay inside causal-ts: `cdnots` or `cedar` with `parcorr-gpu`, `splitkci` instead of `kci`, or a lower max lag. Wait for the user's ok.
3. **Discover** with the recommended config. `-o` is a global option and goes before `discover`:
   ```bash
   causal-ts -o qd_out discover qd_train.csv --json \
     --algorithm <rec.algorithm> --ci-test <rec.ci_test> --max-lag <rec.max_lag>
   ```
   Read the `edges` list (`source → target @ lag`) and the `diagnostics` block from stdout.
4. **Deconfound** if `facts.latent_factor.detected` is true or there are many lag-0 edges. A market-wide factor often causes this:
   ```bash
   causal-ts deconfound qd_out/estimated_graph.npy --data qd_train.csv
   ```
   Report the edges before and after. Removed edges were judged confounded, not disproven.
5. **Robustness** (optional, it costs extra runtime): re-run `discover` with `--validate`. Edges with `persistence >= 0.6` are stable; the rest are fragile. High persistence means "not a sampling fluke", not "certainly causal".
6. **Read the graph:**
   - An empty graph means the test may be too strict or the max lag too small. Suggest a looser alpha.
   - A near-complete graph suggests unhandled nonstationarity. Suggest a stricter alpha such as 0.01.
   - Self-loops are just a series' own past.
   - Lag k means `source(t-k) → target(t)`.

**Output of this step:** the drivers of the target as `source → target @ lag`, in plain English, e.g. "TSM's move yesterday helps explain NVDA today". Mark each driver stable or fragile.

## 4. Measure risk (Goldman gs-quant)

```python
import pandas as pd
from gs_quant.timeseries import (volatility, max_drawdown, beta, correlation,
    zscores, relative_strength_index, bollinger_bands)
px = pd.read_csv("qd_prices.csv", index_col="date", parse_dates=True)
t = px["NVDA"]                                   # target
vol   = volatility(t, 63).iloc[-1]               # 3-month annualized vol, %
mdd   = max_drawdown(t).iloc[-1]                 # worst peak-to-trough
b     = beta(t, px["SPY"] if "SPY" in px else px["QQQ"], 126).iloc[-1]
corr  = {d: correlation(t, px[d], 126).iloc[-1] for d in px.columns if d != "NVDA"}
z     = zscores(t, 63).iloc[-1]                  # how stretched the price is now
rsi   = relative_strength_index(t, 14).iloc[-1]
```

- Use a DatetimeIndex `pd.Series` for every call. Don't call `sharpe_ratio` or any pricing or dataset API: those need a Goldman session. Compute Sharpe yourself if needed.
- Explain each number in one plain sentence, e.g. "volatility 48%: a normal year swings about ±48%".
- Contrast correlation with the causal drivers from step 3. A ticker can be highly correlated and still not be a driver.

## 5. Forecast the next days (Kronos, Tsinghua)

Kronos is an open-source foundation model for candlesticks (MIT license, models on Hugging Face). The paper says it was pre-trained on "over 12 billion K-line records from 45 global exchanges". It runs on CPU. The first run downloads PyTorch and the model, so it takes a few minutes.

```bash
[ -d ~/.argusdesk/Kronos ] || git clone --depth 1 https://github.com/shiyu-coder/Kronos ~/.argusdesk/Kronos
pip install torch einops huggingface_hub safetensors tqdm
```

```python
import os, sys, numpy as np, pandas as pd, yfinance as yf
sys.path.insert(0, os.path.expanduser("~/.argusdesk/Kronos"))
from model import Kronos, KronosTokenizer, KronosPredictor
tok = KronosTokenizer.from_pretrained("NeoQuasar/Kronos-Tokenizer-base")
mdl = Kronos.from_pretrained("NeoQuasar/Kronos-small")
kp = KronosPredictor(mdl, tok, device="cpu", max_context=512)

h = yf.Ticker("NVDA").history(period="2y", auto_adjust=True)     # target candles
h.index = h.index.tz_localize(None)
df = h.rename(columns=str.lower)[["open", "high", "low", "close", "volume"]]

def kronos(x, future):
    return kp.predict(df=x.reset_index(drop=True), x_timestamp=pd.Series(x.index),
                      y_timestamp=pd.Series(future), pred_len=len(future),
                      T=1.0, top_p=0.9, sample_count=5, verbose=False)

x = df.iloc[-400:]
fut = pd.bdate_range(x.index[-1] + pd.Timedelta(days=1), periods=5)
f = kronos(x, fut)
k_change = f["close"].iloc[-1] / x["close"].iloc[-1] - 1        # 5-day forecast, %

# Honesty check: walk forward over the last 20 days, one day ahead each time
hits = []
for i in range(len(df) - 20, len(df)):
    xi = df.iloc[i - 400:i]
    p = kronos(xi, [df.index[i]])["close"].iloc[0]
    hits.append(np.sign(p - xi["close"].iloc[-1]) == np.sign(df["close"].iloc[i] - xi["close"].iloc[-1]))
k_hit = float(np.mean(hits))
```

- Report the 5-day forecast path and `k_change`.
- Report `k_hit` next to 50%, which is a coin flip. If it is near 50%, say the forecast is just one more opinion.
- The Kronos authors warn that raw forecasts are not alpha. Never present this step as a trade signal on its own.

## 6. Backtest one rule (tuned by BlackRock HOLA, checked like Vibe-Trading)

Build the rule only from **stable lagged** edges (lag 1 or more) from step 3. If there are none, say so and stop here. Don't invent a signal.

**The rule:** go long the target when the driver's lagged move, in train-window standard deviations and in the edge's direction, is above `k`. Hold the position `hold` days. Otherwise stay flat. Each entry or exit costs 5 bp.

```python
import numpy as np, pandas as pd
rets = pd.read_csv("qd_all.csv", index_col="date", parse_dates=True)
split = int(len(rets) * 0.7)
train, test = rets.iloc[:split], rets.iloc[split:]
T = "NVDA"                                   # target
edges = {"TSM": 1}                           # stable lagged edges from step 3: driver -> lag

def stats(d):                                # train-window mean, std and edge direction
    s = np.sign(train[d].shift(edges[d]).corr(train[T])) or 1.0
    return train[d].mean(), train[d].std(), s

def run(r, d, k, hold):
    mu, sd, s = stats(d)
    z = (r[d].shift(edges[d]) - mu) / sd     # driver move known before day t
    pos = (s * z > k).astype(float).rolling(hold, min_periods=1).max()
    cost = pos.diff().abs().fillna(pos) * 0.0005
    return pos * r[T] - cost, pos

def sharpe(x):
    return float(x.mean() / x.std() * np.sqrt(252)) if x.std() > 0 else 0.0
```

**Tune on the train window only, with BlackRock's HOLA optimizer** (Apache-2.0, github.com/blackrock/HOLA):

```bash
pip install --pre hola-opt --extra-index-url https://blackrock.github.io/HOLA/simple/
```

```python
from hola_opt import Study, Space, Real, Integer, Categorical, Maximize
study = Study(space=Space(edge=Categorical(list(edges)), k=Real(0.5, 2.5), hold=Integer(1, 5)),
              objectives=[Maximize("sharpe")], seed=42)

def objective(p):
    r, pos = run(train, p["edge"], p["k"], int(p["hold"]))
    entries = int((pos.diff() > 0).sum())
    return {"sharpe": sharpe(r) if entries >= 8 else -5.0}   # too few trades is not a rule

study.run(objective, n_trials=80)
best = study.top_k(1)[0].params
```

If `hola-opt` won't install, use a small grid instead: `k` from 0.5 to 2.5 in steps of 0.25, `hold` from 1 to 5, every edge. Say which one you used.

**Score once on the unseen 30%.** Never re-tune after looking at these numbers.

```python
r_all, pos_all = run(rets, best["edge"], best["k"], int(best["hold"]))
r, pos = r_all.loc[test.index], pos_all.loc[test.index]
bh = test[T]                                  # buy and hold, same days
```

Report total return (`np.exp(r.sum()) - 1`) against buy and hold, Sharpe, max drawdown (gs-quant `max_drawdown` on `np.exp(r.cumsum())`), entries and hit rate.

**Robustness checks, the same three Vibe-Trading (HKU) runs on its backtests:**

```python
rng = np.random.default_rng(0)
boot = [sharpe(pd.Series(rng.choice(r.values, len(r)))) for _ in range(2000)]
sr_lo, sr_hi = np.percentile(boot, [5, 95])            # Bootstrap: Sharpe range

def mdd(x):
    e = np.exp(np.cumsum(x))
    return float((e / np.maximum.accumulate(e) - 1).min())
mc_dd = np.percentile([mdd(rng.permutation(r.values)) for _ in range(2000)], 5)   # Monte Carlo: bad-luck drawdown

chunks = np.array_split(np.arange(len(r)), 3)          # Walk-forward: 3 slices of unseen data
wf_wins = sum(r.iloc[c].sum() > bh.iloc[c].sum() for c in chunks)
```

- **Bootstrap:** if `sr_lo` is below 0, the result could be luck. Say so.
- **Monte Carlo:** `mc_dd` is the drawdown to expect in a bad-luck ordering of the same days.
- **Walk-forward:** say how many of the 3 slices beat buy and hold.
- Say plainly whether the rule beat buy and hold on unseen data. A losing result is a valid answer.

**Tomorrow's signal** (used in step 8):

```python
nxt = pd.concat([rets, pd.DataFrame(index=[rets.index[-1] + pd.offsets.BDay()])]).fillna(0.0)
signal_tomorrow = bool(run(nxt, best["edge"], best["k"], int(best["hold"]))[1].iloc[-1])
```

Say whether the rule and the Kronos 5-day view agree.

## 7. What big funds did (optional, Vibe-Trading MCP)

Vibe-Trading (HKUDS, MIT) has a free, read-only SEC 13F tool, `get_institutional_holdings`: a fund's 13F book with quarter-over-quarter changes.

- If its tools are loaded in this session, read the tool's schema. Check 3-5 well-known 13F filers, e.g. Bridgewater, Renaissance Technologies, Citadel Advisors, Berkshire Hathaway. Report whether each added, cut or holds the target. Note that 13F data is quarterly and filed up to 45 days late.
- If its tools aren't loaded, offer the setup in one line and skip the step:
  ```bash
  pip install vibe-trading-ai
  claude mcp add vibe-trading -- vibe-trading-mcp
  ```
  The user then restarts Claude Code. Use only its read-only research tools, never its `trading_*` tools.

## 8. Paper trade on Alpaca (optional, only on an explicit yes)

Ask: "Run this rule on your free Alpaca paper account?" Only continue on a clear yes.

- The user needs a free Alpaca paper account and its keys in `ALPACA_API_KEY` and `ALPACA_SECRET_KEY`. Never ask them to paste keys into chat.
- Always paper. Never switch to live trading inside this skill.

```python
import os
from alpaca.trading.client import TradingClient
from alpaca.trading.requests import MarketOrderRequest
from alpaca.trading.enums import OrderSide, TimeInForce
tc = TradingClient(os.environ["ALPACA_API_KEY"], os.environ["ALPACA_SECRET_KEY"], paper=True)
if signal_tomorrow:                              # from step 6
    tc.submit_order(MarketOrderRequest(symbol="NVDA", qty=1,
        side=OrderSide.BUY, time_in_force=TimeInForce.DAY))
```

Show the order id and status. Offer to re-run the check daily (see "Run it every day" in the README). The user can also connect Alpaca's official MCP server instead of using this code.

## 9. Final report

Keep it short, in plain language:
1. **Peers:** the iShares ETF and its as-of date.
2. **What moves the stock:** the drivers with their lags, each marked stable or fragile.
3. **Risk:** volatility, max drawdown, beta, z-score and RSI, one line each.
4. **Kronos:** the 5-day forecast and its 20-day hit rate against a coin flip.
5. **Backtest:** the HOLA-tuned rule (driver, `k`, `hold`), the unseen-data result against buy and hold, the bootstrap Sharpe range, the Monte Carlo drawdown and the walk-forward score.
6. **Big funds:** the 13F changes, if step 7 ran.
7. **Paper trade:** the order details, if one was placed.
8. **Caveats:**
   - Causal links in markets drift over time.
   - A backtest is not a forecast, and neither is Kronos.
   - Data is free Yahoo data.
   - This is research, not financial advice.

Save the report as `argusdesk_report.md` next to the data files.
