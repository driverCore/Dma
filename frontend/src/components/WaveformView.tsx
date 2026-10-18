import React, { useState, useEffect, useRef } from 'react';
import {
  Activity,
  ZoomIn,
  ZoomOut,
  ChevronLeft,
  ChevronRight,
  ChevronsLeft,
  ChevronsRight,
  Download,
  Filter,
  Info,
  CheckCircle2,
  AlertTriangle,
  Play,
  RotateCcw,
  Maximize2
} from 'lucide-react';
import { ApiService } from '../services/api';
import { ParsedWaveform, WaveformSample, HistoryItem } from '../types';

interface SignalConfig {
  key: string;
  label: string;
  type: 'bit' | 'bus';
  color: string;
  widthText: string;
}

const ALL_SIGNALS: SignalConfig[] = [
  { key: 'clk', label: 'clk', type: 'bit', color: '#8b949e', widthText: '1b' },
  { key: 'rst_n', label: 'rst_n', type: 'bit', color: '#ef4444', widthText: '1b' },
  { key: 'fsm_state', label: 'fsm_state', type: 'bus', color: '#06b6d4', widthText: '3b' },
  { key: 'req_valid', label: 'mem_req_valid', type: 'bit', color: '#10b981', widthText: '1b' },
  { key: 'req_ready', label: 'mem_req_ready', type: 'bit', color: '#10b981', widthText: '1b' },
  { key: 'req_rw', label: 'mem_req_rw', type: 'bus', color: '#f59e0b', widthText: '1b' },
  { key: 'req_addr', label: 'mem_req_addr', type: 'bus', color: '#a855f7', widthText: '32b' },
  { key: 'rsp_valid', label: 'mem_rsp_valid', type: 'bit', color: '#38bdf8', widthText: '1b' },
  { key: 'rsp_ready', label: 'mem_rsp_ready', type: 'bit', color: '#38bdf8', widthText: '1b' },
  { key: 'fifo_occ', label: 'fifo_occupancy', type: 'bus', color: '#f97316', widthText: '5b' },
  { key: 'arb_grant', label: 'arb_grant', type: 'bus', color: '#ec4899', widthText: '2b' },
  { key: 'ext_req', label: 'ext_req (M1)', type: 'bit', color: '#eab308', widthText: '1b' },
  { key: 'ext_grant', label: 'ext_grant (M1)', type: 'bit', color: '#eab308', widthText: '1b' },
  { key: 'irq', label: 'irq (complete)', type: 'bit', color: '#22c55e', widthText: '1b' }
];

export const WaveformView: React.FC = () => {
  const [runs, setRuns] = useState<HistoryItem[]>([]);
  const [selectedRunId, setSelectedRunId] = useState<string>('latest');
  const [startCycle, setStartCycle] = useState<number>(0);
  const [cycleCount, setCycleCount] = useState<number>(60);
  const [waveform, setWaveform] = useState<ParsedWaveform | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  // Selected cursor cycle (index within timeline)
  const [cursorCycle, setCursorCycle] = useState<number | null>(null);

  // Enabled signal keys
  const [enabledSignals, setEnabledSignals] = useState<Set<string>>(
    new Set(['clk', 'rst_n', 'fsm_state', 'req_valid', 'req_ready', 'req_rw', 'req_addr', 'rsp_valid', 'fifo_occ', 'arb_grant', 'irq'])
  );

  const containerRef = useRef<HTMLDivElement>(null);

  // Fetch runs list on mount
  useEffect(() => {
    const fetchRuns = async () => {
      try {
        const hist = await ApiService.getHistory(30);
        setRuns(hist);
      } catch (err) {
        console.error('Failed to load runs for waveform view:', err);
      }
    };
    fetchRuns();
  }, []);

  // Fetch waveform data
  const loadWaveformData = async (runId: string, start: number, count: number) => {
    try {
      setLoading(true);
      setError(null);
      const data = await ApiService.getParsedWaveform(runId, start, count);
      setWaveform(data);
      if (cursorCycle === null && data.timeline.length > 0) {
        setCursorCycle(data.timeline[0].cycle);
      }
    } catch (err: any) {
      setError(err.message || 'Failed to load waveform data');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadWaveformData(selectedRunId, startCycle, cycleCount);
  }, [selectedRunId, startCycle, cycleCount]);

  // Jump to specific cycle
  const jumpToCycle = (targetCycle: number) => {
    const half = Math.floor(cycleCount / 2);
    const newStart = Math.max(0, targetCycle - half);
    setStartCycle(newStart);
    setCursorCycle(targetCycle);
  };

  // Toggle signal visibility
  const toggleSignal = (key: string) => {
    const next = new Set(enabledSignals);
    if (next.has(key)) {
      if (next.size > 1) next.delete(key);
    } else {
      next.add(key);
    }
    setEnabledSignals(next);
  };

  // Navigation step handlers
  const handlePan = (delta: number) => {
    setStartCycle((prev) => Math.max(0, prev + delta));
  };

  const handleZoom = (inOut: 'in' | 'out') => {
    if (inOut === 'in') {
      setCycleCount((prev) => Math.max(20, prev - 20));
    } else {
      setCycleCount((prev) => Math.min(160, prev + 20));
    }
  };

  // Timeline geometry
  const cycleWidth = Math.max(20, Math.min(48, Math.floor(960 / Math.max(1, cycleCount))));
  const traceHeight = 32;

  // Find currently selected sample by cursorCycle
  const activeSample: WaveformSample | undefined = waveform?.timeline.find(
    (s) => s.cycle === cursorCycle
  ) || waveform?.timeline[0];

  // Helper to color bus states
  const getFsmStateColor = (state: string) => {
    switch (state) {
      case 'IDLE': return '#475569';
      case 'VALIDATE': return '#6366f1';
      case 'READ_REQ': return '#0284c7';
      case 'READ_WAIT': return '#0369a1';
      case 'WRITE_REQ': return '#d97706';
      case 'WRITE_WAIT': return '#b45309';
      case 'CHECK_DONE': return '#059669';
      case 'DONE': return '#10b981';
      case 'ERROR': return '#ef4444';
      default: return '#334155';
    }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
      {/* Waveform Header & Controls */}
      <div className="glass-card" style={{ padding: '18px 24px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px', marginBottom: '16px' }}>
          <div>
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', marginBottom: '4px' }}>
              <span className="metric-pill pill-red">PHASE 8</span>
              <span className="metric-pill pill-cyan">CYCLE-ACCURATE TIMING</span>
              <span className="metric-pill pill-green">IEEE 1364 VCD</span>
            </div>
            <h2 style={{ fontFamily: 'var(--font-display)', fontSize: '1.45rem', fontWeight: 700, color: '#fff' }}>
              Waveform & Digital Timing Debugger
            </h2>
          </div>

          <div style={{ display: 'flex', gap: '10px', alignItems: 'center', flexWrap: 'wrap' }}>
            {/* Run Selector */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <span style={{ fontSize: '0.82rem', color: 'var(--text-muted)' }}>Simulation Run:</span>
              <select
                className="input-field"
                style={{ padding: '6px 12px', fontSize: '0.84rem', width: '220px' }}
                value={selectedRunId}
                onChange={(e) => setSelectedRunId(e.target.value)}
              >
                <option value="latest">⚡ Latest Simulation (Auto)</option>
                {runs.map((r) => (
                  <option key={r.run_id} value={r.run_id}>
                    {r.run_id} ({r.suite} - {r.verdict})
                  </option>
                ))}
              </select>
            </div>

            {/* Download VCD */}
            <a
              href={`/api/waveform/${selectedRunId}`}
              download={`${selectedRunId}_waveform.vcd`}
              className="btn-secondary"
              style={{ textDecoration: 'none', padding: '6px 12px', fontSize: '0.82rem' }}
              title="Download raw IEEE 1364 Value Change Dump for GTKWave or ModelSim"
            >
              <Download size={14} />
              Raw VCD
            </a>
          </div>
        </div>

        {/* Landmark Jump Navigation Bar */}
        {waveform && waveform.landmarks && waveform.landmarks.length > 0 && (
          <div style={{
            background: 'rgba(9, 12, 16, 0.6)',
            border: '1px solid var(--border-subtle)',
            borderRadius: '8px',
            padding: '10px 14px',
            display: 'flex',
            alignItems: 'center',
            gap: '10px',
            flexWrap: 'wrap'
          }}>
            <span style={{ fontSize: '0.78rem', fontWeight: 600, color: 'var(--cyan-accent)', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
              Landmark Markers:
            </span>
            {waveform.landmarks.map((lm, idx) => (
              <button
                key={idx}
                className="metric-pill"
                style={{
                  cursor: 'pointer',
                  border: '1px solid',
                  borderColor: lm.type === 'error' ? 'var(--ruby-error)' : lm.type === 'success' ? 'var(--emerald-success)' : 'var(--cyan-accent)',
                  background: cursorCycle === lm.cycle ? 'rgba(6, 182, 212, 0.25)' : 'rgba(255, 255, 255, 0.05)',
                  color: '#fff',
                  fontSize: '0.78rem',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '6px'
                }}
                onClick={() => jumpToCycle(lm.cycle)}
              >
                <span>Cycle {lm.cycle}:</span>
                <span style={{ fontWeight: 600 }}>{lm.label}</span>
              </button>
            ))}
          </div>
        )}

        {/* Timeline Navigation Controls */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '14px', flexWrap: 'wrap', gap: '12px' }}>
          {/* Pan controls */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
            <button className="btn-secondary" style={{ padding: '6px 10px' }} onClick={() => handlePan(-40)} title="Jump back 40 cycles">
              <ChevronsLeft size={14} /> -40
            </button>
            <button className="btn-secondary" style={{ padding: '6px 10px' }} onClick={() => handlePan(-10)} title="Step back 10 cycles">
              <ChevronLeft size={14} /> -10
            </button>
            <span style={{
              fontFamily: 'var(--font-mono)',
              fontSize: '0.85rem',
              color: 'var(--text-main)',
              padding: '0 8px',
              minWidth: '160px',
              textAlign: 'center'
            }}>
              Cycles: [{startCycle} .. {startCycle + cycleCount}]
            </span>
            <button className="btn-secondary" style={{ padding: '6px 10px' }} onClick={() => handlePan(10)} title="Step forward 10 cycles">
              +10 <ChevronRight size={14} />
            </button>
            <button className="btn-secondary" style={{ padding: '6px 10px' }} onClick={() => handlePan(40)} title="Jump forward 40 cycles">
              +40 <ChevronsRight size={14} />
            </button>
          </div>

          {/* Zoom controls */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>Window Size:</span>
            <button className="btn-secondary" style={{ padding: '6px 10px' }} onClick={() => handleZoom('in')} title="Zoom in">
              <ZoomIn size={14} /> Zoom In
            </button>
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: '0.84rem' }}>{cycleCount} cyc</span>
            <button className="btn-secondary" style={{ padding: '6px 10px' }} onClick={() => handleZoom('out')} title="Zoom out">
              <ZoomOut size={14} /> Zoom Out
            </button>
            <button className="btn-secondary" style={{ padding: '6px 10px' }} onClick={() => { setStartCycle(0); setCursorCycle(0); }}>
              <RotateCcw size={14} /> Reset
            </button>
          </div>
        </div>
      </div>

      {/* Signal Selection Bar */}
      <div className="glass-card" style={{ padding: '12px 20px', display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
        <span style={{ fontSize: '0.78rem', fontWeight: 600, color: 'var(--text-muted)', textTransform: 'uppercase' }}>
          Visible Signals:
        </span>
        {ALL_SIGNALS.map((sig) => {
          const active = enabledSignals.has(sig.key);
          return (
            <button
              key={sig.key}
              onClick={() => toggleSignal(sig.key)}
              style={{
                background: active ? 'rgba(6, 182, 212, 0.15)' : 'rgba(255, 255, 255, 0.04)',
                border: '1px solid',
                borderColor: active ? sig.color : 'rgba(255, 255, 255, 0.1)',
                borderRadius: '4px',
                padding: '4px 8px',
                fontSize: '0.76rem',
                fontFamily: 'var(--font-mono)',
                color: active ? '#fff' : 'var(--text-muted)',
                cursor: 'pointer',
                transition: 'all 0.15s ease'
              }}
            >
              {sig.label}
            </button>
          );
        })}
      </div>

      {/* Waveform Canvas Area */}
      <div className="glass-card" style={{ padding: '0', overflow: 'hidden' }}>
        {loading ? (
          <div style={{ padding: '60px', textAlign: 'center', color: 'var(--text-muted)' }}>
            <Activity className="spin" size={28} style={{ margin: '0 auto 12px auto', color: 'var(--cyan-accent)' }} />
            <div>Parsing cycle-accurate VCD trace...</div>
          </div>
        ) : error ? (
          <div style={{ padding: '40px', textAlign: 'center', color: 'var(--ruby-error)' }}>
            <AlertTriangle size={28} style={{ margin: '0 auto 12px auto' }} />
            <div>{error}</div>
            <div style={{ marginTop: '12px' }}>
              <button className="btn-primary" onClick={() => loadWaveformData(selectedRunId, startCycle, cycleCount)}>
                Retry
              </button>
            </div>
          </div>
        ) : waveform && waveform.timeline.length > 0 ? (
          <div style={{ display: 'flex', overflowX: 'auto', background: 'var(--bg-terminal)' }}>
            {/* Left Signal Names Column */}
            <div style={{
              width: '210px',
              flexShrink: 0,
              borderRight: '1px solid var(--border-subtle)',
              background: 'var(--bg-secondary)',
              position: 'sticky',
              left: 0,
              zIndex: 10
            }}>
              {/* Ruler Header Label */}
              <div style={{
                height: '42px',
                borderBottom: '1px solid var(--border-subtle)',
                display: 'flex',
                alignItems: 'center',
                padding: '0 12px',
                fontSize: '0.78rem',
                fontWeight: 700,
                color: 'var(--text-muted)',
                fontFamily: 'var(--font-mono)'
              }}>
                SIGNAL NAME
              </div>

              {/* Signal Names List */}
              {ALL_SIGNALS.filter((s) => enabledSignals.has(s.key)).map((sig) => {
                const val = activeSample?.signals[sig.key] ?? '-';
                return (
                  <div
                    key={sig.key}
                    style={{
                      height: `${traceHeight}px`,
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      padding: '0 10px',
                      borderBottom: '1px solid rgba(255, 255, 255, 0.05)',
                      fontFamily: 'var(--font-mono)',
                      fontSize: '0.76rem'
                    }}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px', overflow: 'hidden' }}>
                      <span style={{
                        display: 'inline-block',
                        width: '6px',
                        height: '6px',
                        borderRadius: '50%',
                        backgroundColor: sig.color
                      }}></span>
                      <span style={{ color: sig.color, fontWeight: 600, textOverflow: 'ellipsis', overflow: 'hidden', whiteSpace: 'nowrap' }}>
                        {sig.label}
                      </span>
                    </div>
                    <span style={{
                      fontSize: '0.7rem',
                      background: 'rgba(255, 255, 255, 0.08)',
                      padding: '1px 5px',
                      borderRadius: '3px',
                      color: 'var(--text-muted)'
                    }}>
                      {String(val)}
                    </span>
                  </div>
                );
              })}
            </div>

            {/* Right Waveform Canvas / SVG Container */}
            <div
              ref={containerRef}
              style={{
                flexGrow: 1,
                minWidth: `${waveform.timeline.length * cycleWidth}px`,
                position: 'relative'
              }}
            >
              {/* Timeline Header (Ruler with cycle ticks & landmark pins) */}
              <div style={{
                height: '42px',
                borderBottom: '1px solid var(--border-subtle)',
                display: 'flex',
                position: 'relative',
                background: 'rgba(13, 17, 23, 0.9)'
              }}>
                {waveform.timeline.map((sample, idx) => {
                  const isLandmark = waveform.landmarks.find((l) => l.cycle === sample.cycle);
                  const isCursor = cursorCycle === sample.cycle;
                  return (
                    <div
                      key={sample.cycle}
                      onClick={() => setCursorCycle(sample.cycle)}
                      style={{
                        width: `${cycleWidth}px`,
                        flexShrink: 0,
                        borderRight: '1px solid rgba(255, 255, 255, 0.06)',
                        height: '100%',
                        display: 'flex',
                        flexDirection: 'column',
                        justifyContent: 'center',
                        alignItems: 'center',
                        cursor: 'pointer',
                        background: isCursor ? 'rgba(6, 182, 212, 0.2)' : isLandmark ? 'rgba(237, 28, 36, 0.15)' : 'transparent',
                        position: 'relative'
                      }}
                      title={`Cycle ${sample.cycle} (${sample.time_ns} ns)`}
                    >
                      <span style={{
                        fontSize: '0.68rem',
                        fontFamily: 'var(--font-mono)',
                        color: isCursor ? '#38bdf8' : 'var(--text-muted)'
                      }}>
                        {sample.cycle}
                      </span>
                      <span style={{
                        fontSize: '0.6rem',
                        fontFamily: 'var(--font-mono)',
                        color: 'var(--text-faint)'
                      }}>
                        {sample.time_ns.toFixed(0)}ns
                      </span>
                      {isLandmark && (
                        <div style={{
                          position: 'absolute',
                          top: 2,
                          width: '6px',
                          height: '6px',
                          borderRadius: '50%',
                          backgroundColor: isLandmark.type === 'error' ? 'var(--ruby-error)' : 'var(--cyan-accent)'
                        }} />
                      )}
                    </div>
                  );
                })}
              </div>

              {/* Signal Traces SVG */}
              <svg
                width={waveform.timeline.length * cycleWidth}
                height={ALL_SIGNALS.filter((s) => enabledSignals.has(s.key)).length * traceHeight}
                style={{ display: 'block' }}
              >
                {/* Vertical Cycle Grid Lines */}
                {waveform.timeline.map((sample, idx) => (
                  <line
                    key={idx}
                    x1={idx * cycleWidth}
                    y1={0}
                    x2={idx * cycleWidth}
                    y2={ALL_SIGNALS.filter((s) => enabledSignals.has(s.key)).length * traceHeight}
                    stroke="rgba(255, 255, 255, 0.04)"
                    strokeWidth={1}
                  />
                ))}

                {/* Render Traces for each enabled signal */}
                {ALL_SIGNALS.filter((s) => enabledSignals.has(s.key)).map((sig, sigIdx) => {
                  const yBase = sigIdx * traceHeight;
                  const yTop = yBase + 6;
                  const yBot = yBase + traceHeight - 6;

                  if (sig.type === 'bit') {
                    // Generate polyline points for 1-bit waveform
                    let points = '';
                    waveform.timeline.forEach((sample, idx) => {
                      const val = sample.signals[sig.key];
                      const isHigh = val === 1 || val === '1';
                      const xStart = idx * cycleWidth;
                      const xEnd = (idx + 1) * cycleWidth;

                      if (sig.key === 'clk') {
                        // Clock pulse: half low, half high
                        const xMid = xStart + cycleWidth / 2;
                        if (idx === 0) {
                          points += `${xStart},${yBot} `;
                        }
                        points += `${xStart},${yTop} ${xMid},${yTop} ${xMid},${yBot} ${xEnd},${yBot} `;
                      } else {
                        const y = isHigh ? yTop : yBot;
                        if (idx === 0) {
                          points += `${xStart},${y} `;
                        } else {
                          // Step transition
                          const prevVal = waveform.timeline[idx - 1].signals[sig.key];
                          const prevHigh = prevVal === 1 || prevVal === '1';
                          if (isHigh !== prevHigh) {
                            points += `${xStart},${prevHigh ? yTop : yBot} `;
                          }
                        }
                        points += `${xEnd},${y} `;
                      }
                    });

                    return (
                      <g key={sig.key}>
                        {/* Horizontal subtle guide */}
                        <line x1={0} y1={yBot} x2={waveform.timeline.length * cycleWidth} y2={yBot} stroke="rgba(255,255,255,0.06)" strokeWidth={1} />
                        {/* Waveform trace line */}
                        <polyline
                          points={points}
                          fill="none"
                          stroke={sig.color}
                          strokeWidth={2}
                          strokeLinejoin="round"
                        />
                      </g>
                    );
                  } else {
                    // Render Multi-bit Bus
                    return (
                      <g key={sig.key}>
                        {waveform.timeline.map((sample, idx) => {
                          const val = String(sample.signals[sig.key] ?? '');
                          const x = idx * cycleWidth;
                          const w = cycleWidth;
                          const fillCol = sig.key === 'fsm_state' ? getFsmStateColor(val) : 'rgba(168, 85, 247, 0.25)';

                          return (
                            <g key={idx}>
                              <rect
                                x={x + 1}
                                y={yTop}
                                width={w - 2}
                                height={yBot - yTop}
                                fill={fillCol}
                                rx={2}
                                stroke={sig.color}
                                strokeWidth={1}
                              />
                              {cycleWidth >= 32 && (
                                <text
                                  x={x + w / 2}
                                  y={yTop + 14}
                                  fill="#fff"
                                  fontSize="9"
                                  fontFamily="var(--font-mono)"
                                  textAnchor="middle"
                                  style={{ pointerEvents: 'none' }}
                                >
                                  {val.length > 5 && cycleWidth < 44 ? val.substring(0, 4) : val}
                                </text>
                              )}
                            </g>
                          );
                        })}
                      </g>
                    );
                  }
                })}

                {/* Vertical Cursor Indicator Line */}
                {cursorCycle !== null && (
                  (() => {
                    const sampleIdx = waveform.timeline.findIndex((s) => s.cycle === cursorCycle);
                    if (sampleIdx !== -1) {
                      const cx = sampleIdx * cycleWidth + cycleWidth / 2;
                      return (
                        <g>
                          <line
                            x1={cx}
                            y1={0}
                            x2={cx}
                            y2={ALL_SIGNALS.filter((s) => enabledSignals.has(s.key)).length * traceHeight}
                            stroke="#38bdf8"
                            strokeWidth={2}
                            strokeDasharray="4 2"
                          />
                        </g>
                      );
                    }
                    return null;
                  })()
                )}
              </svg>
            </div>
          </div>
        ) : null}
      </div>

      {/* Cycle State Inspector Card & Hardware Telemetry */}
      {activeSample && (
        <div className="grid-2col" style={{ gap: '20px' }}>
          {/* Active Cycle Inspector */}
          <div className="glass-card" style={{ padding: '18px 22px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '14px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <span className="metric-pill pill-cyan">INSPECTOR</span>
                <h3 style={{ fontSize: '1.05rem', fontWeight: 700, color: '#fff' }}>
                  Cycle {activeSample.cycle} Snapshot
                </h3>
              </div>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: '0.85rem', color: 'var(--text-muted)' }}>
                T+ {activeSample.time_ns} ns
              </span>
            </div>

            <div style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fill, minmax(130px, 1fr))',
              gap: '10px'
            }}>
              {Object.entries(activeSample.signals).map(([k, v]) => (
                <div key={k} style={{
                  background: 'rgba(9, 12, 16, 0.7)',
                  border: '1px solid var(--border-subtle)',
                  borderRadius: '6px',
                  padding: '8px 10px'
                }}>
                  <div style={{ fontSize: '0.68rem', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>
                    {k}
                  </div>
                  <div style={{
                    fontSize: '0.92rem',
                    fontWeight: 700,
                    fontFamily: 'var(--font-mono)',
                    color: k === 'fsm_state' ? getFsmStateColor(String(v)) : '#f0f6fc',
                    marginTop: '2px'
                  }}>
                    {String(v)}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Engineering Protocol Analysis */}
          <div className="glass-card" style={{ padding: '18px 22px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '14px' }}>
              <span className="metric-pill pill-green">PROTOCOL DIAGNOSTICS</span>
              <h3 style={{ fontSize: '1.05rem', fontWeight: 700, color: '#fff' }}>
                Hardware Bus Status
              </h3>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', fontSize: '0.85rem' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid var(--border-subtle)', paddingBottom: '6px' }}>
                <span style={{ color: 'var(--text-muted)' }}>Active FSM Operation:</span>
                <span style={{ fontWeight: 600, color: getFsmStateColor(String(activeSample.signals.fsm_state)) }}>
                  {String(activeSample.signals.fsm_state)}
                </span>
              </div>

              <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid var(--border-subtle)', paddingBottom: '6px' }}>
                <span style={{ color: 'var(--text-muted)' }}>Memory Bus Handshake:</span>
                <span style={{
                  fontWeight: 600,
                  color: activeSample.signals.req_valid === 1 && activeSample.signals.req_ready === 1 ? 'var(--emerald-success)' : 'var(--text-muted)'
                }}>
                  {activeSample.signals.req_valid === 1 && activeSample.signals.req_ready === 1
                    ? 'TRANSFER ACTIVE (VALID & READY)'
                    : activeSample.signals.req_valid === 1
                    ? 'WAITING ON READY'
                    : 'BUS IDLE'}
                </span>
              </div>

              <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid var(--border-subtle)', paddingBottom: '6px' }}>
                <span style={{ color: 'var(--text-muted)' }}>FIFO Buffer Occupancy:</span>
                <span style={{ fontWeight: 600, fontFamily: 'var(--font-mono)' }}>
                  {activeSample.signals.fifo_occ ?? 0} / 16 words ({(((Number(activeSample.signals.fifo_occ) || 0) / 16) * 100).toFixed(0)}%)
                </span>
              </div>

              <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid var(--border-subtle)', paddingBottom: '6px' }}>
                <span style={{ color: 'var(--text-muted)' }}>Arbiter Active Master:</span>
                <span style={{ fontWeight: 600, color: 'var(--cyan-accent)' }}>
                  {String(activeSample.signals.arb_grant ?? 'NONE')}
                </span>
              </div>

              <div style={{ display: 'flex', justifyContent: 'space-between', paddingTop: '2px' }}>
                <span style={{ color: 'var(--text-muted)' }}>Interrupt Status (irq):</span>
                <span style={{
                  fontWeight: 600,
                  color: activeSample.signals.irq === 1 ? 'var(--emerald-success)' : 'var(--text-muted)'
                }}>
                  {activeSample.signals.irq === 1 ? 'ASSERTED (Transfer Done)' : 'DEASSERTED'}
                </span>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
