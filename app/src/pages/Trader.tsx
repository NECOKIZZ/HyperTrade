import type { Deployment, Series } from "../lib/config";
import { useTracking } from "../lib/hooks";
import { num, short, usd } from "../lib/format";
import { LineChart } from "../components/LineChart";

export function TraderPage({ s }: { d: Deployment; s: Series }) {
  const { data, error } = useTracking(s.sourceVault);
  const pts = data?.points ?? [];
  const last = pts.at(-1);
  const times = pts.map((p) => p.t);
  const ratio = data?.ratio;
  const age = data?.updatedAt ? Math.round((Date.now() - data.updatedAt) / 1000) : null;

  return (
    <div className="stack">
      <section className="card">
        <div className="swap-head">
          <div>
            <div className="eyebrow">Hyperliquid trader</div>
            <h2>{s.traderName}</h2>
            <p className="muted small">
              Wallet{" "}
              <a href={`https://app.hyperliquid.xyz/explorer/address/${s.trader}`} target="_blank" rel="noreferrer">
                {short(s.trader)}
              </a>{" "}
              · LiquidV vault{" "}
              <a href={`https://hyperevmscan.io/address/${s.sourceVault}`} target="_blank" rel="noreferrer">
                {short(s.sourceVault)}
              </a>
            </p>
          </div>
          <span className={`pill ${data?.stale || data?.paused ? "warn" : "good"}`}>
            {data?.paused ? "LiquidV paused" : data?.stale ? "LiquidV stale" : "Mirroring"}
          </span>
        </div>
        <p className="muted">
          Your ticket holds this LiquidV token. LiquidV’s vault copies {s.traderName}’s positions at a fixed size ratio, a few seconds behind. Below
          is what {s.traderName} holds right now, what the vault holds, and how closely the token has followed, measured by our own watcher.
        </p>
        {error && <p className="note warn">{error}</p>}
        <dl className="stats four">
          <div>
            <dt>{s.traderName}’s account</dt>
            <dd>{usd(last?.traderValue, 0)}</dd>
          </div>
          <div>
            <dt>Vault size ratio</dt>
            <dd>{ratio ? `1 : ${num(1 / ratio, 0)}` : "–"}</dd>
          </div>
          <div>
            <dt>{s.traderName}’s exposure</dt>
            <dd>{last ? `${num(last.traderLev, 2)}x` : "–"}</dd>
          </div>
          <div>
            <dt>The token’s exposure</dt>
            <dd>{last ? `${num(last.vaultLev, 2)}x` : "–"}</dd>
          </div>
        </dl>
        <p className="muted small">
          Exposure is position size ÷ account value: a 1% move in {s.traderName}’s markets moves the token about {last ? num(last.vaultLev, 1) : "–"}%.
          The token’s exposure counts the vault’s idle cash, kept aside to pay sellers.
        </p>
      </section>

      <section className="card">
        <h3>Live positions</h3>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Market</th>
                <th>{s.traderName}</th>
                <th>Vault</th>
                <th>Vault should hold</th>
                <th>Match</th>
                <th>{s.traderName}’s liquidation</th>
              </tr>
            </thead>
            <tbody>
              {(data?.positions ?? []).map((p) => (
                <tr key={p.coin}>
                  <td>{p.coin}</td>
                  <td className={side(p.trader?.szi)}>
                    {p.trader ? `${p.trader.szi > 0 ? "Long" : "Short"} ${num(Math.abs(p.trader.szi), 4)}` : "–"}
                    <small>{p.trader ? ` ${usd(p.trader.value, 0)} · ${p.trader.leverage}` : ""}</small>
                  </td>
                  <td className={side(p.vault?.szi)}>
                    {p.vault ? `${p.vault.szi > 0 ? "Long" : "Short"} ${num(Math.abs(p.vault.szi), 5)}` : "–"}
                    <small>{p.vault ? ` ${usd(p.vault.value)}` : ""}</small>
                  </td>
                  <td>{p.expectedVaultSzi ? num(Math.abs(p.expectedVaultSzi), 5) : "–"}</td>
                  <td>{p.match !== null ? `${num(p.match * 100, 1)}%` : "–"}</td>
                  <td>{p.trader?.liqPx ? usd(p.trader.liqPx, 0) : "–"}</td>
                </tr>
              ))}
              {data && data.positions.length === 0 && (
                <tr>
                  <td colSpan={6} className="muted">
                    No open positions: the vault holds cash.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
        <p className="muted small">
          From Hyperliquid on {data?.dexes.join(" and ") ?? "…"} {age !== null ? `· ${age}s ago` : ""}. Small positions can be skipped: LiquidV
          doesn’t copy changes under $10.
        </p>
      </section>

      <section className="card">
        <h3>Does the token follow {s.traderName}?</h3>
        <p className="muted">
          The dashed line is what one token would be worth if the vault had held exactly {ratio ? `1/${num(1 / ratio, 0)}` : "its share"} of{" "}
          {s.traderName}’s positions the whole time, LiquidV’s own rule. The solid line is what it is actually worth. The gap is LiquidV’s tracking
          cost: fees, funding, and copying a few seconds late.
        </p>
        <LineChart
          times={times}
          lines={[
            { label: "Token value (LiquidV)", color: "var(--accent)", values: pts.map((p) => p.nav) },
            { label: `Expected from ${s.traderName}’s positions`, color: "var(--muted)", values: pts.map((p) => p.expected), dashed: true },
          ]}
          unit={(v) => `$${v.toFixed(4)}`}
        />
        <h4>Gap, in basis points (0.01%)</h4>
        <LineChart times={times} lines={[{ label: "Token vs expected", color: "var(--warn)", values: pts.map((p) => p.devBps) }]} unit={(v) => v.toFixed(1)} zero minSpan={2} />
        {last && (
          <p className="muted small">
            Now: {last.devBps >= 0 ? "+" : ""}
            {last.devBps.toFixed(1)} bps. The expected line restarts at the token’s real value whenever the watcher has been offline.
          </p>
        )}
      </section>
    </div>
  );
}

const side = (szi?: number) => (szi === undefined ? "" : szi > 0 ? "long" : "short");
