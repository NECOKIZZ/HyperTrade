import { useEffect, useState } from "react";
import { useAccount, useConnect, useDisconnect } from "wagmi";
import { deployment, NETWORKS, type NetKey } from "./lib/config";
import { short } from "./lib/format";
import { TradePage } from "./pages/Trade";
import { PoolPage } from "./pages/Pool";
import { TraderPage } from "./pages/Trader";

type Page = "trade" | "pool" | "trader";

function readHash(): { page: Page; series?: string } {
  const [page, series] = window.location.hash.replace(/^#\/?/, "").split("/");
  return { page: (["trade", "pool", "trader"].includes(page) ? page : "trade") as Page, series };
}

export function App() {
  const [route, setRoute] = useState(readHash);
  const [net, setNet] = useState<NetKey>(() => {
    try {
      return (localStorage.getItem("net") as NetKey) || "elysiumTestnet";
    } catch {
      return "elysiumTestnet";
    }
  });
  useEffect(() => {
    const on = () => setRoute(readHash());
    window.addEventListener("hashchange", on);
    return () => window.removeEventListener("hashchange", on);
  }, []);
  const pickNet = (n: NetKey) => {
    setNet(n);
    try {
      localStorage.setItem("net", n);
    } catch {
      /* private window */
    }
  };

  const d = deployment(net);
  const series = d?.series.find((s) => s.key === route.series) ?? d?.series[0];
  const go = (page: Page) => (window.location.hash = `/${page}${series ? `/${series.key}` : ""}`);

  return (
    <div className="shell">
      <header className="top">
        <a className="brand" href="#/trade">
          <span className="mark">✦</span> Asphodel
        </a>
        <nav className="tabs">
          {(["trade", "pool", "trader"] as Page[]).map((p) => (
            <button key={p} className={route.page === p ? "on" : ""} onClick={() => go(p)}>
              {p === "trade" ? "Trade" : p === "pool" ? "Pool" : "Trader"}
            </button>
          ))}
        </nav>
        <div className="right">
          <select value={net} onChange={(e) => pickNet(e.target.value as NetKey)} aria-label="Network">
            {NETWORKS.map((n) => (
              <option key={n.key} value={n.key}>
                {n.label}
              </option>
            ))}
          </select>
          <Wallet />
        </div>
      </header>

      <main>
        {!d ? (
          <NotLive net={net} />
        ) : !series ? (
          <div className="card">No Series on this network yet.</div>
        ) : (
          <>
            {d.series.length > 1 && (
              <div className="series-pick">
                {d.series.map((s) => (
                  <a key={s.key} href={`#/${route.page}/${s.key}`} className={s.key === series.key ? "on" : ""}>
                    {s.name}
                  </a>
                ))}
              </div>
            )}
            {route.page === "trade" && <TradePage d={d} s={series} />}
            {route.page === "pool" && <PoolPage d={d} s={series} />}
            {route.page === "trader" && <TraderPage d={d} s={series} />}
          </>
        )}
      </main>

      <footer>
        You’re trading a Hyperliquid trader, not us. Every ticket holds the real LiquidV trader token; the pools only pay the
        boost. You can lose what you put in.
      </footer>
    </div>
  );
}

function NotLive({ net }: { net: NetKey }) {
  return (
    <div className="card hero">
      <h1>{net === "elysium" ? "Mainnet opens with Elysium’s HyperCore precompiles" : "Not deployed here yet"}</h1>
      <p className="muted">
        {net === "elysium"
          ? "Asphodel goes live on Elysium mainnet the day Elysium’s live HyperCore reads ship, so every ticket is priced from Hyperliquid in real time. Try it on Elysium Testnet now."
          : "Run the deploy script for this network (see the README)."}
      </p>
    </div>
  );
}

function Wallet() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  if (isConnected && address)
    return (
      <button className="ghost" onClick={() => disconnect()} title="Disconnect">
        {short(address)}
      </button>
    );
  const c = connectors[0];
  return (
    <button className="primary small" disabled={!c || isPending} onClick={() => c && connect({ connector: c })}>
      {isPending ? "Connecting…" : "Connect wallet"}
    </button>
  );
}
