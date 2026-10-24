---
name: argusdesk
description: Pick peers from BlackRock iShares holdings, find what moves a stock (Bloomberg causal-ts), measure risk (Goldman gs-quant), backtest and paper-trade on Alpaca. Use for "what drives X" or trade ideas.
---

# ArgusDesk: cause, risk, backtest, paper trade

One workflow built on official open-source libraries and free data:
- **BlackRock iShares** ETF holdings (a free CSV on ishares.com) pick the stock's real peers by fund weight.
- **Bloomberg causal-ts** (`pip install causalts`) finds who moves whom, and at what lag.
- **Goldman Sachs gs-quant** (`pip install gs-quant`) measures risk with its `gs_quant.timeseries` math. These functions run locally and need no Goldman login.
- **Alpaca** (`pip install alpaca-py`) runs the rule on a free paper-trading account. This step is optional.

Work through the steps in order. Show the user a one-line status before each step. Never present results as financial advice.

## 0. Setup

```bash
pip install causalts gs-quant yfinance pandas numpy requests
```

Check that `causal-ts --help` works. Install `alpaca-py` only if the user wants step 6.

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

## 5. Backtest one rule

Build one simple rule from the strongest **stable lagged** edge. If there's none, say so and stop here. Don't invent a signal.

- **Example rule:** go long the target tomorrow when the driver's return today is above +1 standard deviation, measured on the train window. Otherwise stay flat. Use the edge's lag and the edge's sign.
- **Run it on the held-out 30% only.**
  - Subtract 5 bp per trade.
  - Compare with buy and hold over the same days.
- **Report:** total return, annualized volatility, Sharpe (computed in pandas), max drawdown (use gs-quant `max_drawdown` on the equity curve), number of trades and hit rate.
- Say plainly whether the rule beat buy and hold on unseen data. A losing result is a valid answer.

## 6. Paper trade on Alpaca (optional, only on an explicit yes)

Ask: "Run this rule on your free Alpaca paper account?" Only continue on a clear yes.

- The user needs a free Alpaca paper account and its keys in `ALPACA_API_KEY` and `ALPACA_SECRET_KEY`. Never ask them to paste keys into chat.
- Always paper. Never switch to live trading inside this skill.

```python
import os
from alpaca.trading.client import TradingClient
from alpaca.trading.requests import MarketOrderRequest
from alpaca.trading.enums import OrderSide, TimeInForce
tc = TradingClient(os.environ["ALPACA_API_KEY"], os.environ["ALPACA_SECRET_KEY"], paper=True)
# signal_today = True/False from the step-5 rule on the latest data
if signal_today:
    tc.submit_order(MarketOrderRequest(symbol="NVDA", qty=1,
        side=OrderSide.BUY, time_in_force=TimeInForce.DAY))
```

Show the order id and status. Offer to re-run the check daily. The user can also connect Alpaca's official MCP server instead of using this code.

## 7. Final report

Keep it short, in plain language:
1. **What moves the stock:** the peers used (iShares ETF and as-of date), then the drivers with their lags, each marked stable or fragile.
2. **Risk:** volatility, max drawdown, beta, z-score and RSI, one line each.
3. **Backtest:** the rule, the unseen-data result against buy and hold, and the trade count.
4. **Paper trade:** the order details, if one was placed.
5. **Caveats:**
   - Causal links in markets drift over time.
   - A backtest is not a forecast.
   - Data is free Yahoo data.
   - This is research, not financial advice.

Save the report as `argusdesk_report.md` next to the data files.
