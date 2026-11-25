import { useState } from "react";
import { useAccount } from "wagmi";
import { parseUnits } from "viem";
import { marketAbi, usdcAbi, type Deployment, type Series } from "../lib/config";
import { useSeries, useTx } from "../lib/hooks";
import { num, usd } from "../lib/format";

const POOLS = [
  {
    key: "hearth",
    name: "Hearth",
    tag: "Hedged",
    about:
      "Hearth holds the real trader token as a hedge and earns fees on every ticket. When the token slides, its hedge pays its share, so it comes out even. It only loses if the token jumps past the zero line in one update (a liquidation fast enough to skip the stop).",
  },
  {
    key: "ember",
    name: "Ember",
    tag: "Unhedged",
    about:
      "Ember takes the other side of the boost with no hedge: it gains when the trader loses and pays when the trader wins, at most the full boost per ticket, which it locks up front. A bet against the trader, paid fees for taking it.",
  },
] as const;

export function PoolPage({ d, s }: { d: Deployment; s: Series }) {
  const st = useSeries(d, s);
  const { isConnected } = useAccount();
  const tx = useTx(d.chainId);
  const [pool, setPool] = useState<0 | 1>(0);
  const [mode, setMode] = useState<"deposit" | "withdraw">("deposit");
  const [amount, setAmount] = useState("");
  const P = POOLS[pool];
  const hearth = pool === 0;
  const amt = Number(amount) || 0;
  const myValue = st.myValue[pool] ?? 0;
  const share = (st.totalShares[pool] ?? 0n) > 0n ? Number(st.myShares[pool] ?? 0n) / Number(st.totalShares[pool]) : 0;

  async function submit() {
    if (!amt) return;
    if (mode === "deposit") {
      const v = parseUnits(amount, 6);
      if ((st.allowance ?? 0n) < v) {
        const ok = await tx.send("Approving USDC", d.usdc, usdcAbi, "approve", [s.market, 2n ** 256n - 1n]);
        if (!ok) return;
      }
      if (await tx.send(`Depositing in ${P.name}`, s.market, marketAbi, "requestDeposit", [hearth, v])) setAmount("");
    } else {
      // withdraw a dollar amount: the matching slice of the user's pool shares
      const mine = st.myShares[pool] ?? 0n;
      const frac = myValue > 0 ? Math.min(1, amt / myValue) : 0;
      const sh = frac >= 0.9999 ? mine : (mine * BigInt(Math.floor(frac * 1e9))) / 1_000_000_000n;
      if (sh > 0n && (await tx.send(`Withdrawing from ${P.name}`, s.market, marketAbi, "requestWithdraw", [hearth, sh]))) setAmount("");
    }
  }

  return (
    <div className="grid two">
      <section className="card swap">
        <div className="seg">
          {POOLS.map((p, i) => (
            <button key={p.key} className={pool === i ? "on" : ""} onClick={() => setPool(i as 0 | 1)}>
              {p.name} <span className="tag">{p.tag}</span>
            </button>
          ))}
        </div>
        <p className="muted">{P.about}</p>

        <div className="seg small">
          <button className={mode === "deposit" ? "on" : ""} onClick={() => setMode("deposit")}>
            Deposit
          </button>
          <button className={mode === "withdraw" ? "on" : ""} onClick={() => setMode("withdraw")}>
            Withdraw
          </button>
        </div>

        <label className="field">
          <span>{mode === "deposit" ? "Amount (USDC)" : "Amount to take out (USD)"}</span>
          <input inputMode="decimal" placeholder="0.00" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))} />
          <small className="muted">
            {mode === "deposit" ? `Balance ${usd(st.usdcBalanceNum)}` : `Your ${P.name} position ${usd(myValue)}`}
            {mode === "withdraw" && myValue > 0 && (
              <button className="link" onClick={() => setAmount(myValue.toFixed(2))}>
                Max
              </button>
            )}
          </small>
        </label>

        <button className="primary wide" disabled={!isConnected || !amt || !!tx.busy} onClick={submit}>
          {!isConnected ? "Connect a wallet" : tx.busy ?? (mode === "deposit" ? `Deposit in ${P.name}` : `Withdraw from ${P.name}`)}
        </button>
        {tx.error && <p className="note bad">{tx.error}</p>}
        <p className="note">
          Deposits and withdrawals settle at the next price update. You can only take out free money: what backs live tickets stays locked
          until those tickets are sold or the Series ends. Anything you take out is ready to collect on the Trade page.
        </p>
      </section>

      <section className="card">
        <h3>{P.name} in this Series</h3>
        <dl className="stats">
          <div>
            <dt>Pool value</dt>
            <dd>{usd(st.equity[pool])}</dd>
          </div>
          <div>
            <dt>Free to back new tickets</dt>
            <dd>{usd(st.free[pool])}</dd>
          </div>
          <div>
            <dt>Your position</dt>
            <dd>{usd(myValue)}</dd>
          </div>
          <div>
            <dt>Your share of the pool</dt>
            <dd>{num(share * 100, 2)}%</dd>
          </div>
          <div>
            <dt>Hearth / Ember split of every ticket’s boost</dt>
            <dd>
              {Math.round(s.hearthShare * 100)}% / {Math.round((1 - s.hearthShare) * 100)}%
            </dd>
          </div>
          <div>
            <dt>Most the pools pay per ticket (the full boost)</dt>
            <dd>{usd(st.maxBoost)}</dd>
          </div>
        </dl>
        <p className="muted small">
          LPs earn 60% of every buy and sell fee. Hearth also holds {s.boost - 1}x of the real token per ticket for its share, bought at
          LiquidV’s price.
        </p>
      </section>
    </div>
  );
}
