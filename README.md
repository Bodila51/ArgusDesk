# ArgusDesk

One Claude Code skill that turns a single prompt into a small quant research desk:

1. **Who to compare with:** BlackRock's public **iShares** ETF holdings pick the stock's real peers by fund weight (e.g. SOXX for chips).
2. **What moves the stock:** Bloomberg's open-source **causal-ts** finds which tickers drive your stock, and with what lag (for example "TSM → NVDA @ 1 day"). It also removes links that are only shared market moves.
3. **How risky it is:** Goldman Sachs' open-source **gs-quant** measures volatility, max drawdown, beta, correlation, z-score and RSI.
4. **Does the idea hold up:** the skill turns the strongest stable link into one simple rule. It then backtests the rule on data it has never seen and compares it with buy and hold.
5. **Paper trade (optional):** it runs the rule on a free **Alpaca** paper account, and only if you say yes.

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

You need Python 3.10+. The skill installs its Python packages itself: `causalts`, `gs-quant`, `yfinance`, `requests`, and `alpaca-py` for the optional step.

## Use

Open Claude Code and type:

```
/argusdesk find what really moves NVDA and test a trading rule on it
```

You get:
- the peers from iShares holdings;
- the drivers with their lags, each marked stable or fragile;
- the risk numbers, with a plain-English line for each;
- an out-of-sample backtest against buy and hold;
- optionally, a paper order on Alpaca.

For the paper-trading step, create a free paper account at alpaca.markets. Then set `ALPACA_API_KEY` and `ALPACA_SECRET_KEY` in your environment.

## Built on

- [bloomberg/causal-ts](https://github.com/bloomberg/causal-ts): GPL-3.0, installed from PyPI as `causalts`.
- [goldmansachs/gs-quant](https://github.com/goldmansachs/gs-quant): Apache-2.0. Only the local `gs_quant.timeseries` functions are used, with no Goldman login.
- [iShares by BlackRock](https://www.ishares.com): the free "latest fund holdings" CSV on iShares ETF pages.
- [alpacahq/alpaca-py](https://github.com/alpacahq/alpaca-py): Apache-2.0.

This skill isn't affiliated with or endorsed by Bloomberg, Goldman Sachs, BlackRock or Alpaca.

## Disclaimer

This is for research and education only. It isn't financial advice. Causal links in markets drift over time, and past results don't guarantee future returns.
