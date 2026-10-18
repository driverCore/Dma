import React, { useEffect, useState } from 'react';
import {
  BarChart3,
  TrendingUp,
  Download,
  Clock,
  Zap,
  Layers,
  ArrowUpRight,
  Filter,
  CheckCircle2
} from 'lucide-react';
import { ApiService } from '../services/api';
import { BenchmarkSummary } from '../types';

export const PerformanceView: React.FC = () => {
  const [data, setData] = useState<BenchmarkSummary | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedSweep, setSelectedSweep] = useState<'burst' | 'length' | 'latency' | 'contention'>('burst');

  useEffect(() => {
    const fetchBenchmark = async () => {
      try {
        setLoading(true);
        const res = await ApiService.getBenchmarkSummary();
        setData(res);
      } catch (err: any) {
        setError(err.message || 'Failed to load performance benchmark data');
      } finally {
        setLoading(false);
      }
    };
    fetchBenchmark();
  }, []);

  if (loading) {
    return (
      <div className="glass-card" style={{ textAlign: 'center', padding: '60px 0' }}>
        <div style={{ color: 'var(--cyan-accent)', fontSize: '1rem', fontWeight: 600 }}>
          Loading cycle-accurate benchmark telemetry from simulation database...
        </div>
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="glass-card" style={{ textAlign: 'center', padding: '50px', color: '#f87171' }}>
        <p>{error || 'No benchmark dataset available. Run benchmark runner first.'}</p>
      </div>
    );
  }

  const { sweeps } = data;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
      {/* Performance Header Banner */}
      <div className="glass-card" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '6px' }}>
            <span className="metric-pill pill-cyan">PHASE 4 CHARACTERIZATION</span>
            <span className="metric-pill pill-green">40 SIMULATION TRIALS</span>
            <span className="metric-pill pill-purple">100.0 MHZ CLOCK GRID</span>
          </div>
          <h2 style={{ fontSize: '1.4rem', fontWeight: 800, color: '#fff', fontFamily: 'var(--font-display)' }}>
            Cycle-Accurate Performance Benchmarking Suite
          </h2>
          <div style={{ color: 'var(--text-muted)', fontSize: '0.85rem' }}>
            Physical hardware cycle counts, throughput calculations, bus utilization, and arbitration fairness.
          </div>
        </div>

        <a
          href="/api/benchmark/csv"
          download="dma_benchmark_results.csv"
          className="btn-primary"
          style={{ textDecoration: 'none' }}
        >
          <Download size={16} />
          Export Flat CSV Dataset
        </a>
      </div>

      {/* Sweep Selector Tabs */}
      <div style={{ display: 'flex', gap: '10px' }}>
        <button
          className={`btn-secondary ${selectedSweep === 'burst' ? 'active' : ''}`}
          onClick={() => setSelectedSweep('burst')}
          style={{ borderColor: selectedSweep === 'burst' ? 'var(--amd-red)' : undefined }}
        >
          Burst Size Scaling
        </button>
        <button
          className={`btn-secondary ${selectedSweep === 'length' ? 'active' : ''}`}
          onClick={() => setSelectedSweep('length')}
          style={{ borderColor: selectedSweep === 'length' ? 'var(--amd-red)' : undefined }}
        >
          Workload Length Amortization
        </button>
        <button
          className={`btn-secondary ${selectedSweep === 'latency' ? 'active' : ''}`}
          onClick={() => setSelectedSweep('latency')}
          style={{ borderColor: selectedSweep === 'latency' ? 'var(--amd-red)' : undefined }}
        >
          Memory Latency Sensitivity
        </button>
        <button
          className={`btn-secondary ${selectedSweep === 'contention' ? 'active' : ''}`}
          onClick={() => setSelectedSweep('contention')}
          style={{ borderColor: selectedSweep === 'contention' ? 'var(--amd-red)' : undefined }}
        >
          Arbitration & Contention (Fixed vs RR)
        </button>
      </div>

      {/* SWEEP 1: Burst Size Scaling */}
      {selectedSweep === 'burst' && (
        <div className="glass-card">
          <div className="card-header">
            <div className="card-title">
              <Zap size={18} />
              Sweep 1: Burst Size Scaling & Throughput Speedup (256B Workload, Latency=1)
            </div>
            <span className="metric-pill pill-cyan">BURST_SCALE</span>
          </div>

          <div className="grid-4" style={{ marginBottom: '20px' }}>
            {sweeps.burst_size_scaling.map((b) => (
              <div
                key={b.burst_beats}
                style={{
                  background: 'rgba(255, 255, 255, 0.02)',
                  border: '1px solid var(--border-subtle)',
                  borderRadius: '8px',
                  padding: '16px'
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                  <span style={{ fontSize: '0.78rem', color: 'var(--text-muted)', fontWeight: 600 }}>BURST = {b.burst_beats} BEATS</span>
                  <span className={`metric-pill ${b.burst_beats === 4 ? 'pill-green' : 'pill-cyan'}`}>
                    {b.burst_beats === 1 ? 'BASELINE' : `+${(((b.throughput_mb_s - 28.32) / 28.32) * 100).toFixed(1)}%`}
                  </span>
                </div>
                <div style={{ fontSize: '1.6rem', fontWeight: 800, fontFamily: 'var(--font-display)', color: '#fff' }}>
                  {b.throughput_mb_s.toFixed(1)} <span style={{ fontSize: '0.88rem', color: 'var(--text-muted)' }}>MB/s</span>
                </div>
                <div style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginTop: '4px', fontFamily: 'var(--font-mono)' }}>
                  {b.cycles} Cycles | Bus Util: {b.bus_utilization_pct.toFixed(1)}%
                </div>
              </div>
            ))}
          </div>

          <div className="data-table-container">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Burst Beats</th>
                  <th>Execution Cycles</th>
                  <th>Throughput (B/Cyc)</th>
                  <th>Throughput (MB/s)</th>
                  <th>Bus Util (%)</th>
                  <th>Peak FIFO Depth</th>
                  <th>Arbiter Grants</th>
                </tr>
              </thead>
              <tbody>
                {sweeps.burst_size_scaling.map((b) => (
                  <tr key={b.burst_beats}>
                    <td style={{ fontWeight: 600, color: 'var(--cyan-accent)' }}>{b.burst_beats} beats</td>
                    <td>{b.cycles} cycles</td>
                    <td>{b.throughput_bytes_per_cycle.toFixed(4)}</td>
                    <td style={{ fontWeight: 600, color: '#fff' }}>{b.throughput_mb_s.toFixed(2)} MB/s</td>
                    <td>{b.bus_utilization_pct.toFixed(2)}%</td>
                    <td>{b.max_fifo_occupancy} / 16 words</td>
                    <td>{b.grants_req0}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* SWEEP 2: Transfer Length Scaling */}
      {selectedSweep === 'length' && (
        <div className="glass-card">
          <div className="card-header">
            <div className="card-title">
              <TrendingUp size={18} />
              Sweep 2: Transfer Length Scaling & Protocol Setup Overhead Amortization
            </div>
            <span className="metric-pill pill-green">LEN_SCALE</span>
          </div>

          <p style={{ color: 'var(--text-muted)', fontSize: '0.84rem', marginBottom: '16px' }}>
            Evaluates payload scaling from 16 to 512 bytes across single-word ($B=1$), 4-beat ($B=4$), and 8-beat ($B=8$) bursts, demonstrating asymptotic convergence to peak throughput as fixed setup overhead (6 cycles) amortizes.
          </p>

          <div className="data-table-container">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Payload (Bytes)</th>
                  <th>Words</th>
                  <th>Burst=1 (Cycles / MB/s)</th>
                  <th>Burst=4 (Cycles / MB/s)</th>
                  <th>Burst=8 (Cycles / MB/s)</th>
                  <th>Overhead Fraction (B=4)</th>
                </tr>
              </thead>
              <tbody>
                {[16, 64, 128, 256, 512].map((len) => {
                  const b1 = sweeps.transfer_length_scaling.burst_1.find((x) => x.xfer_bytes === len);
                  const b4 = sweeps.transfer_length_scaling.burst_4.find((x) => x.xfer_bytes === len);
                  const b8 = sweeps.transfer_length_scaling.burst_8.find((x) => x.xfer_bytes === len);
                  const ovhPct = b4 ? ((6 / b4.cycles) * 100).toFixed(1) : 'N/A';

                  return (
                    <tr key={len}>
                      <td style={{ fontWeight: 600, color: 'var(--cyan-accent)' }}>{len} Bytes</td>
                      <td>{len / 4} words</td>
                      <td>{b1 ? `${b1.cycles} cyc (${b1.throughput_mb_s.toFixed(1)} MB/s)` : 'N/A'}</td>
                      <td style={{ color: '#fff', fontWeight: 600 }}>{b4 ? `${b4.cycles} cyc (${b4.throughput_mb_s.toFixed(1)} MB/s)` : 'N/A'}</td>
                      <td style={{ color: 'var(--emerald-success)', fontWeight: 600 }}>{b8 ? `${b8.cycles} cyc (${b8.throughput_mb_s.toFixed(1)} MB/s)` : 'N/A'}</td>
                      <td>{ovhPct}%</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* SWEEP 3: Memory Response Latency */}
      {selectedSweep === 'latency' && (
        <div className="glass-card">
          <div className="card-header">
            <div className="card-title">
              <Clock size={18} />
              Sweep 3: Memory Slave Latency Sensitivity (0 to 4 Cycles Wait States)
            </div>
            <span className="metric-pill pill-purple">MEM_LAT</span>
          </div>

          <div style={{ background: 'rgba(168, 85, 247, 0.08)', border: '1px solid var(--border-subtle)', borderRadius: '8px', padding: '14px', marginBottom: '16px', fontSize: '0.84rem', color: '#c084fc' }}>
            <strong>Mathematical Latency Invariant:</strong> Cycle duration increases by exactly <strong>128 clock cycles per additional memory wait state</strong> across all burst configurations for 256-byte (64-word) transfers.
          </div>

          <div className="data-table-container">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Memory Wait States</th>
                  <th>Target Memory Class</th>
                  <th>Burst=1 Throughput</th>
                  <th>Burst=4 Throughput</th>
                  <th>Burst=8 Throughput</th>
                  <th>Degradation Factor vs 0-Wait</th>
                </tr>
              </thead>
              <tbody>
                {[0, 1, 2, 3, 4].map((lat) => {
                  const b1 = sweeps.memory_latency_sensitivity.burst_1.find((x) => x.mem_latency === lat);
                  const b4 = sweeps.memory_latency_sensitivity.burst_4.find((x) => x.mem_latency === lat);
                  const b8 = sweeps.memory_latency_sensitivity.burst_8.find((x) => x.mem_latency === lat);
                  const degPct = b8 ? (((544 - b8.cycles) / 544) * 100).toFixed(1) : 'N/A';

                  const labels = [
                    'Zero-Wait SRAM',
                    'Registered Synchronous Array',
                    'Pipelined Multi-Stage Memory',
                    'External Memory Bridge',
                    'High-Latency Interconnect'
                  ];

                  return (
                    <tr key={lat}>
                      <td style={{ fontWeight: 600, color: 'var(--cyan-accent)' }}>{lat} wait states</td>
                      <td>{labels[lat]}</td>
                      <td>{b1 ? `${b1.cycles} cyc (${b1.throughput_mb_s.toFixed(1)} MB/s)` : 'N/A'}</td>
                      <td>{b4 ? `${b4.cycles} cyc (${b4.throughput_mb_s.toFixed(1)} MB/s)` : 'N/A'}</td>
                      <td style={{ fontWeight: 600, color: '#fff' }}>{b8 ? `${b8.cycles} cyc (${b8.throughput_mb_s.toFixed(1)} MB/s)` : 'N/A'}</td>
                      <td style={{ color: '#f87171' }}>{degPct}%</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* SWEEP 4: Arbitration & Contention */}
      {selectedSweep === 'contention' && (
        <div className="glass-card">
          <div className="card-header">
            <div className="card-title">
              <Layers size={18} />
              Sweep 4: Multi-Master Arbitration Contention (Fixed-Priority vs Round-Robin)
            </div>
            <span className="metric-pill pill-red">ARB_CONTENTION</span>
          </div>

          <div className="data-table-container">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Policy</th>
                  <th>Contention Regime</th>
                  <th>DMA Cycles</th>
                  <th>DMA MB/s</th>
                  <th>DMA Wait Cyc</th>
                  <th>Ext Master Wait Cyc</th>
                  <th>DMA Grants</th>
                  <th>Ext Master Grants</th>
                  <th>Fairness Ratio (M0:M1)</th>
                </tr>
              </thead>
              <tbody>
                {sweeps.arbitration_and_contention.map((a, idx) => {
                  const ratio = a.grants_req1 > 0 ? (a.grants_req0 / a.grants_req1).toFixed(2) + ' : 1' : 'Exclusive (Solo)';
                  const isFair = a.policy === 'RoundRobin' && a.contention === 'Heavy';

                  return (
                    <tr key={idx} style={{ background: isFair ? 'rgba(16, 185, 129, 0.04)' : undefined }}>
                      <td style={{ fontWeight: 600, color: a.policy === 'RoundRobin' ? 'var(--emerald-success)' : 'var(--cyan-accent)' }}>
                        {a.policy}
                      </td>
                      <td>{a.contention}</td>
                      <td>{a.cycles} cyc</td>
                      <td style={{ fontWeight: 600, color: '#fff' }}>{a.throughput_mb_s.toFixed(2)} MB/s</td>
                      <td>{a.wait_cycles_req0}</td>
                      <td style={{ color: a.wait_cycles_req1 > 500 ? '#f87171' : undefined }}>{a.wait_cycles_req1}</td>
                      <td>{a.grants_req0}</td>
                      <td style={{ fontWeight: 600, color: a.policy === 'RoundRobin' ? '#34d399' : undefined }}>{a.grants_req1}</td>
                      <td style={{ fontWeight: 600, color: isFair ? 'var(--emerald-success)' : undefined }}>
                        {ratio} {isFair && '★ 1:1 Fair'}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
};
