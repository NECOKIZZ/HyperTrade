type Line = { label: string; color: string; values: number[]; dashed?: boolean };

/** A small dependency-free line chart. `times` are ms timestamps; every line has one value per time. */
export function LineChart({
  times,
  lines,
  unit,
  zero,
  minSpan = 0,
}: {
  times: number[];
  lines: Line[];
  unit?: (v: number) => string;
  zero?: boolean;
  minSpan?: number; // the y axis covers at least this much (keeps a flat line from looking like noise)
}) {
  const W = 640;
  const H = 200;
  const PAD = { l: 56, r: 12, t: 12, b: 24 };
  if (times.length < 2) return <div className="chart-empty">Collecting data…</div>;
  const all = lines.flatMap((l) => l.values).filter(Number.isFinite);
  let lo = Math.min(...all, ...(zero ? [0] : []));
  let hi = Math.max(...all, ...(zero ? [0] : []));
  const span = Math.max(minSpan, 1e-9);
  if (hi - lo < span) {
    const mid = (hi + lo) / 2;
    hi = mid + span / 2;
    lo = mid - span / 2;
  }
  const t0 = times[0];
  const t1 = times[times.length - 1];
  const X = (t: number) => PAD.l + ((t - t0) / (t1 - t0 || 1)) * (W - PAD.l - PAD.r);
  const Y = (v: number) => PAD.t + (1 - (v - lo) / (hi - lo)) * (H - PAD.t - PAD.b);
  const fmt = unit ?? ((v: number) => v.toFixed(4));
  const ticks = [lo, (lo + hi) / 2, hi];
  const time = (t: number) => new Date(t).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  return (
    <figure className="chart">
      <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={lines.map((l) => l.label).join(" vs ")}>
        {ticks.map((v, i) => (
          <g key={i}>
            <line x1={PAD.l} x2={W - PAD.r} y1={Y(v)} y2={Y(v)} className="grid-line" />
            <text x={PAD.l - 6} y={Y(v) + 4} textAnchor="end" className="axis">
              {fmt(v)}
            </text>
          </g>
        ))}
        {zero && lo < 0 && hi > 0 && <line x1={PAD.l} x2={W - PAD.r} y1={Y(0)} y2={Y(0)} className="zero-line" />}
        <text x={PAD.l} y={H - 6} className="axis">
          {time(t0)}
        </text>
        <text x={W - PAD.r} y={H - 6} textAnchor="end" className="axis">
          {time(t1)}
        </text>
        {lines.map((l) => (
          <polyline
            key={l.label}
            fill="none"
            stroke={l.color}
            strokeWidth={2}
            strokeDasharray={l.dashed ? "5 4" : undefined}
            points={l.values.map((v, i) => `${X(times[i]).toFixed(1)},${Y(v).toFixed(1)}`).join(" ")}
          />
        ))}
      </svg>
      <figcaption>
        {lines.map((l) => (
          <span key={l.label}>
            <i style={{ background: l.color }} /> {l.label}
          </span>
        ))}
      </figcaption>
    </figure>
  );
}
