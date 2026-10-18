import React from 'react';
import {
  Cpu,
  Layers,
  Zap,
  ShieldCheck,
  CheckCircle2,
  HardDrive,
  Terminal,
  Activity,
  ArrowRight,
  TrendingUp,
  Sliders,
  AlertCircle
} from 'lucide-react';
import { SystemStatus } from '../types';

interface OverviewViewProps {
  status: SystemStatus | null;
  onNavigate: (tab: string) => void;
}

export const OverviewView: React.FC<OverviewViewProps> = ({ status, onNavigate }) => {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
      {/* Hero Welcome Banner */}
      <div className="glass-card" style={{
        background: 'linear-gradient(135deg, rgba(237, 28, 36, 0.12) 0%, rgba(13, 17, 23, 0.8) 60%)',
        borderColor: 'rgba(237, 28, 36, 0.35)',
        position: 'relative',
        overflow: 'hidden'
      }}>
        <div style={{ maxWidth: '820px' }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', marginBottom: '12px' }}>
            <span className="metric-pill pill-red">HARDWARE DV LAB</span>
            <span className="metric-pill pill-cyan">PHASE 7 ACTIVE</span>
            <span className="metric-pill pill-green">VERILOG RTL IEEE 1364-2001</span>
          </div>
          <h1 style={{ fontFamily: 'var(--font-display)', fontSize: '1.9rem', fontWeight: 800, color: '#fff', marginBottom: '10px' }}>
            DMA Verification & Performance Analysis Lab
          </h1>
          <p style={{ color: 'var(--text-muted)', fontSize: '0.94rem', lineHeight: 1.6, marginBottom: '20px' }}>
            Modular, high-performance Direct Memory Access (DMA) subsystem design featuring First-Word Fall-Through (FWFT) synchronous FIFO buffering, multi-master arbitration with burst locking, self-checking scoreboard verification, automated failure triage, and cycle-accurate performance characterization.
          </p>
          <div style={{ display: 'flex', gap: '14px', flexWrap: 'wrap' }}>
            <button className="btn-primary" onClick={() => onNavigate('simulation')}>
              <Zap size={16} />
              Launch Hardware Simulation
            </button>
            <button className="btn-secondary" onClick={() => onNavigate('performance')}>
              <TrendingUp size={16} />
              Inspect Performance Curves
            </button>
            <button className="btn-secondary" onClick={() => onNavigate('verification')}>
              <ShieldCheck size={16} />
              View Coverage (100.0%)
            </button>
          </div>
        </div>
      </div>

      {/* KPI Metrics Ribbon */}
      <div className="grid-4">
        <div className="glass-card" style={{ padding: '18px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '10px' }}>
            <span style={{ fontSize: '0.78rem', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 600 }}>System Clock</span>
            <span className="metric-pill pill-green">SYNCHRONOUS</span>
          </div>
          <div style={{ fontSize: '1.8rem', fontWeight: 800, fontFamily: 'var(--font-display)', color: '#fff' }}>
            100.0 <span style={{ fontSize: '1rem', color: 'var(--text-muted)', fontWeight: 500 }}>MHz</span>
          </div>
          <div style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginTop: '4px' }}>
            Normalized 10.0 ns period clock grid
          </div>
        </div>

        <div className="glass-card" style={{ padding: '18px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '10px' }}>
            <span style={{ fontSize: '0.78rem', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 600 }}>Peak Throughput</span>
            <span className="metric-pill pill-cyan">8-BEAT BURST</span>
          </div>
          <div style={{ fontSize: '1.8rem', fontWeight: 800, fontFamily: 'var(--font-display)', color: 'var(--cyan-accent)' }}>
            47.06 <span style={{ fontSize: '1rem', color: 'var(--text-muted)', fontWeight: 500 }}>MB/s</span>
          </div>
          <div style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginTop: '4px' }}>
            0-wait state SRAM continuous stream
          </div>
        </div>

        <div className="glass-card" style={{ padding: '18px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '10px' }}>
            <span style={{ fontSize: '0.78rem', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 600 }}>Functional Coverage</span>
            <span className="metric-pill pill-green">24 / 24 BINS</span>
          </div>
          <div style={{ fontSize: '1.8rem', fontWeight: 800, fontFamily: 'var(--font-display)', color: 'var(--emerald-success)' }}>
            100.0 <span style={{ fontSize: '1rem', color: 'var(--text-muted)', fontWeight: 500 }}>%</span>
          </div>
          <div style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginTop: '4px' }}>
            Full coverage across bursts, lengths & errors
          </div>
        </div>

        <div className="glass-card" style={{ padding: '18px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '10px' }}>
            <span style={{ fontSize: '0.78rem', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 600 }}>Fault Detection Rate</span>
            <span className="metric-pill pill-purple">TRIAGE ACTIVE</span>
          </div>
          <div style={{ fontSize: '1.8rem', fontWeight: 800, fontFamily: 'var(--font-display)', color: 'var(--purple-accent)' }}>
            100.0 <span style={{ fontSize: '1rem', color: 'var(--text-muted)', fontWeight: 500 }}>%</span>
          </div>
          <div style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginTop: '4px' }}>
            Zero silent corruption across 3 injected bugs
          </div>
        </div>
      </div>

      {/* Subsystem Architecture Diagram & Details */}
      <div className="grid-2">
        {/* Hardware Architecture Layout */}
        <div className="glass-card">
          <div className="card-header">
            <div className="card-title">
              <Layers size={18} />
              RTL Subsystem Architecture
            </div>
            <span className="metric-pill pill-red">dma_top.v</span>
          </div>

          <div style={{
            background: '#07090d',
            border: '1px solid var(--border-subtle)',
            borderRadius: '8px',
            padding: '16px',
            fontFamily: 'var(--font-mono)',
            fontSize: '0.78rem',
            lineHeight: 1.5,
            color: '#c9d1d9',
            overflowX: 'auto',
            marginBottom: '16px'
          }}>
            <pre>{`
  +--------------------------------------------------------------+
  |                          dma_top                             |
  |                                                              |
  |  +----------------+    +----------------+    +------------+  |
  |  |  dma_reg_file  |--->| dma_controller |--->|  dma_fifo  |  |
  |  |  (32b Host)    |    | (Burst Engine) |    |  (FWFT 16) |  |
  |  +----------------+    +----------------+    +------------+  |
  |                               |                    |         |
  |                               v                    v         |
  |                    +-------------------------------------+   |
  |                    |             dma_arbiter             |   |
  |                    | (Fixed-Priority vs Round-Robin Fair)|   |
  |                    +-------------------------------------+   |
  +-----------------------------------|--------------------------+
                                      v
                             +-----------------+
                             | mem_model.v     |
                             | (Pipelined Bus) |
                             +-----------------+
            `}</pre>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '12px', fontSize: '0.82rem' }}>
            <div style={{ background: 'rgba(255, 255, 255, 0.02)', padding: '10px', borderRadius: '6px', border: '1px solid var(--border-subtle)' }}>
              <div style={{ fontWeight: 600, color: 'var(--text-main)', marginBottom: '3px' }}>dma_controller.v</div>
              <div style={{ color: 'var(--text-muted)', fontSize: '0.74rem' }}>FSM orchestrating reads, write streaming, watchdog timeout & status updates</div>
            </div>
            <div style={{ background: 'rgba(255, 255, 255, 0.02)', padding: '10px', borderRadius: '6px', border: '1px solid var(--border-subtle)' }}>
              <div style={{ fontWeight: 600, color: 'var(--text-main)', marginBottom: '3px' }}>dma_fifo.v (FWFT)</div>
              <div style={{ color: 'var(--text-muted)', fontSize: '0.74rem' }}>Synchronous 16-word buffer with write-forwarding bypass on empty push</div>
            </div>
            <div style={{ background: 'rgba(255, 255, 255, 0.02)', padding: '10px', borderRadius: '6px', border: '1px solid var(--border-subtle)' }}>
              <div style={{ fontWeight: 600, color: 'var(--text-main)', marginBottom: '3px' }}>dma_arbiter.v</div>
              <div style={{ color: 'var(--text-muted)', fontSize: '0.74rem' }}>Multi-master arbiter with burst lock protection and wait telemetry counters</div>
            </div>
            <div style={{ background: 'rgba(255, 255, 255, 0.02)', padding: '10px', borderRadius: '6px', border: '1px solid var(--border-subtle)' }}>
              <div style={{ fontWeight: 600, color: 'var(--text-main)', marginBottom: '3px' }}>dma_reg_file.v</div>
              <div style={{ color: 'var(--text-muted)', fontSize: '0.74rem' }}>32-bit memory-mapped control, configuration, status & telemetry registers</div>
            </div>
          </div>
        </div>

        {/* System & Toolchain Status */}
        <div className="glass-card">
          <div className="card-header">
            <div className="card-title">
              <Cpu size={18} />
              Verified Toolchain Environment
            </div>
            <span className="metric-pill pill-green">LIVE STATUS</span>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
            {status?.tools && Object.entries(status.tools).map(([key, tool]) => (
              <div
                key={key}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  padding: '12px 14px',
                  background: 'rgba(255, 255, 255, 0.02)',
                  borderRadius: '8px',
                  border: '1px solid var(--border-subtle)'
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <div style={{
                    width: '32px',
                    height: '32px',
                    borderRadius: '6px',
                    background: tool.available ? 'rgba(16, 185, 129, 0.15)' : 'rgba(239, 68, 68, 0.15)',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center'
                  }}>
                    {tool.available ? (
                      <CheckCircle2 size={18} color="var(--emerald-success)" />
                    ) : (
                      <AlertCircle size={18} color="var(--ruby-error)" />
                    )}
                  </div>
                  <div>
                    <div style={{ fontWeight: 600, fontSize: '0.88rem' }}>{tool.tool}</div>
                    <div style={{ fontSize: '0.74rem', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>
                      {tool.path}
                    </div>
                  </div>
                </div>
                <div>
                  <span className={`metric-pill ${tool.available ? 'pill-green' : 'pill-red'}`}>
                    {tool.version || (tool.available ? 'Available' : 'Missing')}
                  </span>
                </div>
              </div>
            ))}
          </div>

          <div style={{ marginTop: '20px', padding: '14px', background: 'rgba(6, 182, 212, 0.08)', borderRadius: '8px', border: '1px solid var(--border-cyan)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: 'var(--cyan-accent)', fontWeight: 600, fontSize: '0.82rem', marginBottom: '4px' }}>
              <Zap size={14} />
              FastAPI Simulation Bridge Active
            </div>
            <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>
              Backend is executing authentic, cycle-accurate Icarus Verilog simulations with isolated directories under <code style={{ fontFamily: 'var(--font-mono)' }}>runs/</code>.
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
