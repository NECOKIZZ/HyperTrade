import { useState } from "react";
import { useAccount } from "wagmi";
import { parseUnits } from "viem";
import { marketAbi, usdcAbi, STATUS, type Deployment, type Series } from "../lib/config";
import { useSeries, useTracking, useTx } from "../lib/hooks";
import { num, pct, usd } from "../lib/format";

const mag = (v: number) => `${Math.abs(v * 100).toFixed(1)}%`;

const BUY_FEE = 0.003;
const SELL_FEE = 0.003;
const LV_MINT = 0.01;
const LV_EXIT = 0.003;
const TOLERANCE = 0.02; // the order fills at the next update, so allow 2% of movement

export function TradePage({ d, s }: { d: Deployment; s: Series }) {
  const st = useSeries(d, s);
  const { data: track } = useTracking(s.sourceVault);
  const { isConnected } = useAccount();
  const tx = useTx(d.chainId);
  const [side, setSide] = useState<"buy" | "sell">("buy");
  const [amount, setAmount] = useState("");

  const B = s.boost;
  const x = st.x ?? 1;
  const price = st.price ?? 1;
  const live = st.status === 0;
  const ended = st.status === 2 || st.status === 3;
  const tokenLev = track?.points.at(-1)?.vaultLev;

  // what one ticket costs and pays, as the contract computes it (fees on the holder's own share only)
  const hold = Math.min(price, x);
  const costPerTicket = price * (1 + BUY_FEE) + hold * LV_MINT + s.hearthShare * (B - 1) * x * LV_MINT;
  const payPerTicket = price * (1 - SELL_FEE) - hold * LV_EXIT - s.hearthShare * (B - 1) * x * LV_EXIT;
  const amt = Number(amount) || 0;
  const out = side === "buy" ? amt / costPerTicket : amt * Math.max(0, payPerTicket);
  const ticketsHeld = st.tickets !== undefined ? Number(st.tickets) / 1e18 : 0;

  // distances, in the trader token's own move since this Series launched
  const xStop = 1 - (1 - s.stopPrice) / B;
  const toStop = x > 0 ? xStop / x - 1 : undefined;
  const toCrown = st.xCrown ? st.xCrown / x - 1 : undefined;

  const blocked =
    !live ? "This Series has ended." : st.vaultStale || st.vaultPaused ? "LiquidV isn’t taking new money for this trader right now. Selling still works." : st.priceFresh === false ? "Waiting for a fresh price." : null;

  async function submit() {
    if (!amt) return;
    if (side === "buy") {
      const v = parseUnits(amount, 6);
      if ((st.allowance ?? 0n) < v) {
        const ok = await tx.send("Approving USDC", d.usdc, usdcAbi, "approve", [s.market, 2n ** 256n - 1n]);
        if (!ok) return;
      }
      const min = parseUnits((out * (1 - TOLERANCE)).toFixed(6), 18);
      if (await tx.send("Placing buy", s.market, marketAbi, "requestBuy", [v, min])) setAmount("");
    } else {
      const t = parseUnits(amount, 18);
      const min = parseUnits((out * (1 - TOLERANCE)).toFixed(6), 6);
      if (await tx.send("Placing sale", s.market, marketAbi, "requestSell", [t, min])) setAmount("");
    }
  }

  return (
    <div className="grid two">
      <section className="card swap">
        <div className="swap-head">
          <div>
            <div className="eyebrow">{s.traderName} · LiquidV trader token · {B}x</div>
            <h2>{s.name}</h2>
          </div>
          <span className={`pill ${live ? "good" : "warn"}`}>{STATUS[st.status ?? 0]}</span>
        </div>

        <div className="seg">
          <button className={side === "buy" ? "on" : ""} onClick={() => setSide("buy")}>
            Buy
          </button>
          <button className={side === "sell" ? "on" : ""} onClick={() => setSide("sell")}>
            Sell
          </button>
        </div>

        <label className="field">
          <span>{side === "buy" ? "You pay (USDC)" : "You sell (tickets)"}</span>
          <input inputMode="decimal" placeholder="0.00" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))} />
          <small className="muted">
            {side === "buy" ? `Balance ${usd(st.usdcBalanceNum)}` : `You hold ${num(ticketsHeld, 4)} tickets`}
            {side === "sell" && ticketsHeld > 0 && (
              <button className="link" onClick={() => setAmount(String(ticketsHeld))}>
                Max
              </button>
            )}
          </small>
        </label>

        <div className="quote">
          <div>
            <span>{side === "buy" ? "You get about" : "You receive about"}</span>
            <b>{side === "buy" ? `${num(out, 4)} tickets` : usd(out)}</b>
          </div>
          <div>
            <span>Ticket price now</span>
            <b>{usd(price, 4)}</b>
          </div>
          <div>
            <span>Fees</span>
            <b>0.3% ours · LiquidV {side === "buy" ? "1%" : "0.3%"} on your own share</b>
          </div>
        </div>

        {ended ? (
          <button
            className="primary wide"
            disabled={!isConnected || !ticketsHeld || !!tx.busy}
            onClick={() => st.tickets && tx.send("Redeeming", s.market, marketAbi, "redeem", [st.tickets])}
          >
            {tx.busy ?? "Redeem all tickets"}
          </button>
        ) : (
          <button className="primary wide" disabled={!isConnected || !amt || !!tx.busy || (side === "buy" && !!blocked)} onClick={submit}>
            {!isConnected ? "Connect a wallet" : tx.busy ?? (side === "buy" ? "Buy tickets" : "Sell tickets")}
          </button>
        )}
        {side === "buy" && blocked && <p className="note warn">{blocked}</p>}
        {tx.error && <p className="note bad">{tx.error}</p>}
        <p className="note">Orders fill at the next price update (about a second), never at a price anyone has already seen.</p>

        {(st.claimable ?? 0) > 0.000001 && (
          <div className="claim">
            <span>Ready to collect: {usd(st.claimable)}</span>
            <button className="primary small" disabled={!!tx.busy} onClick={() => tx.send("Collecting", s.market, marketAbi, "claim", [])}>
              Collect
            </button>
          </div>
        )}
        {d.usdcIsTest && <Faucet d={d} />}
      </section>

      <section className="card">
        <h3>How this ticket works</h3>
        <p className="muted">
          Your money buys the real <b>{s.traderName}</b> LiquidV token, which holds {s.traderName}’s Hyperliquid positions. The pools add
          another {B - 1}x of the token’s move since this Series launched, so the ticket moves about {B}x as much.
        </p>
        <dl className="stats">
          <div>
            <dt>Token move since launch</dt>
            <dd>{pct(x - 1)}</dd>
          </div>
          <div>
            <dt>Ticket</dt>
            <dd>{usd(price, 4)}</dd>
          </div>
          <div>
            <dt>Stops if the token falls another</dt>
            <dd>{toStop !== undefined ? mag(toStop) : "–"}</dd>
          </div>
          <div>
            <dt>Crowns (max {usd(s.maxPrice)}) if the token rises</dt>
            <dd>{toCrown !== undefined ? pct(toCrown) : "–"}</dd>
          </div>
          {tokenLev !== undefined && toStop !== undefined && (
            <div>
              <dt>…which takes a move against {s.traderName}’s book of about</dt>
              <dd>{mag(toStop / tokenLev)}</dd>
            </div>
          )}
          <div>
            <dt>Tickets out</dt>
            <dd>{num(st.supply, 2)}</dd>
          </div>
        </dl>
        <p className="muted small">
          At the stop ({usd(s.stopPrice)} a ticket, on 2 updates in a row) the real token is sold and you keep what’s left. At the Crown you get
          the token’s real value plus the pools’ full boost. Live positions and how closely the token follows {s.traderName} are on the{" "}
          <a href={`#/trader/${s.key}`}>Trader</a> page.
        </p>
      </section>
    </div>
  );
}

function Faucet({ d }: { d: Deployment }) {
  const { address, isConnected } = useAccount();
  const tx = useTx(d.chainId);
  return (
    <button
      className="ghost wide"
      disabled={!isConnected || !!tx.busy}
      onClick={() => address && tx.send("Minting test USDC", d.usdc, usdcAbi, "mint", [address, 1_000_000_000n])}
    >
      {tx.busy ?? "Get 1,000 test USDC"}
    </button>
  );
}
