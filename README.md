# ArgusDesk

One Claude Code skill that turns a single prompt into a small quant research desk:

1. **Who to compare with:** BlackRock's public **iShares** ETF holdings pick the stock's real peers by fund weight (e.g. SOXX for chips).
2. **What moves the stock:** Bloomberg's open-source **causal-ts** finds which tickers drive your stock, and with what lag (for example "TSM → NVDA @ 1 day"). It also removes links that are only shared market moves.
3. **How risky it is:** Goldman Sachs' open-source **gs-quant** measures volatility, max drawdown, beta, correlation, z-score and RSI.
4. **Where it may go next:** **Kronos**, Tsinghua's open-source candlestick model, forecasts the next 5 days on your CPU. It also checks its own hit rate on the last 20 days.
5. **Does the idea hold up:** the strongest stable link becomes one simple rule. BlackRock's open-source **HOLA** optimizer tunes it on training data only. The skill then tests the rule once on data it has never seen and compares it with buy and hold.
6. **Is it luck:** the result goes through the same three checks **Vibe-Trading** (HKU) runs on its backtests: Bootstrap, Monte Carlo and Walk-Forward.
7. **What big funds did (optional):** Vibe-Trading's free SEC 13F tool shows whether well-known funds added or cut the stock.
8. **Paper trade (optional):** it runs the rule on a free **Alpaca** paper account, and only if you say yes.

Everything runs locally on free data, and no Bloomberg, Goldman or BlackRock account is needed.

## Install

The skill folder installs into `~/.claude/skills`. Use either option:

```bash
npx skills add Bodila51/ArgusDesk
```

or

```bash
git clone https://github.com/Bodila51/ArgusDesk ~/.claude/skills/argusdesk
```

You need Python 3.10+. The skill installs its Python packages itself: `causalts`, `gs-quant`, `yfinance`, `requests`, Kronos (PyTorch, CPU is fine), `hola-opt`, and the optional `vibe-trading-ai` and `alpaca-py`.

## Use

Open Claude Code and type:

```
/argusdesk find what really moves NVDA and test a trading rule on it
```

You get:
- the peers from iShares holdings;
- the drivers with their lags, each marked stable or fragile;
- the risk numbers, with a plain-English line for each;
- a Kronos 5-day forecast with its own hit rate;
- a HOLA-tuned rule, tested out of sample against buy and hold, with Bootstrap, Monte Carlo and Walk-Forward checks;
- optionally, 13F moves of big funds;
- optionally, a paper order on Alpaca.

For the paper-trading step, create a free paper account at alpaca.markets. Then set `ALPACA_API_KEY` and `ALPACA_SECRET_KEY` in your environment.

## Built on

- [bloomberg/causal-ts](https://github.com/bloomberg/causal-ts): GPL-3.0, installed from PyPI as `causalts`.
- [goldmansachs/gs-quant](https://github.com/goldmansachs/gs-quant): Apache-2.0. Only the local `gs_quant.timeseries` functions are used, with no Goldman login.
- [iShares by BlackRock](https://www.ishares.com): the free "latest fund holdings" CSV on iShares ETF pages.
- [blackrock/HOLA](https://github.com/blackrock/HOLA): Apache-2.0, installed as `hola-opt`.
- [shiyu-coder/Kronos](https://github.com/shiyu-coder/Kronos): MIT, models from Hugging Face (NeoQuasar).
- [HKUDS/Vibe-Trading](https://github.com/HKUDS/Vibe-Trading): MIT. The skill runs its checks itself, and the MCP is optional.
- [alpacahq/alpaca-py](https://github.com/alpacahq/alpaca-py): Apache-2.0.

This skill isn't affiliated with or endorsed by Bloomberg, Goldman Sachs, BlackRock, Tsinghua University, HKU or Alpaca.

## Disclaimer

This is for research and education only. It isn't financial advice. Causal links in markets drift over time, and past results don't guarantee future returns.
