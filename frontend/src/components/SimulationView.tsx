import React, { useState } from 'react';
import {
  Play,
  RotateCcw,
  Zap,
  Terminal,
  CheckCircle2,
  XCircle,
  AlertTriangle,
  Clock,
  Layers,
  ShieldCheck,
  Flame,
  Shuffle,
  Sliders
} from 'lucide-react';
import { ApiService } from '../services/api';
import { SimRunSummary } from '../types';

export const SimulationView: React.FC = () => {
  // Configuration State
  const [suite, setSuite] = useState<string>('top');
  const [seed, setSeed] = useState<number>(305419896); // 0x12345678
  const [bugInjection, setBugInjection] = useState<string>('none');
  const [timeoutSec, setTimeoutSec] = useState<number>(60);
  const [isRunning, setIsRunning] = useState<boolean>(false);
  const [activeJobId, setActiveJobId] = useState<string | null>(null);

  // Result State
  const [runResult, setRunResult] = useState<SimRunSummary | null>(null);
  const [rawLog, setRawLog] = useState<string>('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const handleRandomizeSeed = () => {
    const newSeed = Math.floor(Math.random() * 0x7fffffff);
    setSeed(newSeed);
  };

  const handleRunSimulation = async () => {
    setIsRunning(true);
    setErrorMessage(null);
    setRunResult(null);
    setRawLog('');

    try {
      // Launch synchronous simulation
      const result = await ApiService.runSimulation({
        suite,
        seed,
        bug_injection: bugInjection,
        timeout_sec: timeoutSec,
        async_exec: false
      });

      if ('verdict' in result) {
        setRunResult(result);
        setActiveJobId(result.run_id);
        // Fetch raw log
        const log = await ApiService.getRunLog(result.run_id).catch(() => '');
        setRawLog(log);
      }
    } catch (err: any) {
      setErrorMessage(err.message || 'Simulation execution failed');
    } finally {
      setIsRunning(false);
    }
  };

  const handleRunBatch = async () => {
    setIsRunning(true);
    setErrorMessage(null);
    setRunResult(null);
    setRawLog('');

    try {
      const res = await ApiService.runBatchRegression({
        suite,
        seed_count: 5,
        bug_injection: bugInjection,
        timeout_sec: timeoutSec
      });

      if (res.runs && res.runs.length > 0) {
        const lastRun = res.runs[res.runs.length - 1];
        setRunResult(lastRun);
        setActiveJobId(lastRun.run_id);
        const log = await ApiService.getRunLog(lastRun.run_id).catch(() => '');
        setRawLog(log);
      }
    } catch (err: any) {
      setErrorMessage(err.message || 'Batch regression failed');
    } finally {
      setIsRunning(false);
    }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
      {/* Simulation Controls Panel */}
      <div className="glass-card">
        <div className="card-header">
          <div className="card-title">
            <Sliders size={18} />
            Hardware Simulation Launcher
          </div>
          <span className="metric-pill pill-cyan">Icarus Verilog + VVP Engine</span>
        </div>

        <div className="grid-4" style={{ marginBottom: '16px' }}>
          {/* Suite Selector */}
          <div className="form-group">
            <label className="form-label">Verification Target Suite</label>
            <select
              className="form-select"
              value={suite}
              onChange={(e) => setSuite(e.target.value)}
              disabled={isRunning}
            >
              <option value="top">Top Subsystem (22 TCs + 25 Rand)</option>
              <option value="fifo">FIFO Unit Test (10 Boundary TCs)</option>
              <option value="arbiter">Arbiter Unit Test (7 Arbitration TCs)</option>
              <option value="benchmark">Benchmark Sweeps (40 Trials)</option>
            </select>
          </div>

          {/* Seed Input */}
          <div className="form-group">
            <label className="form-label" style={{ display: 'flex', justifyContent: 'space-between' }}>
              <span>Random Seed</span>
              <button
                type="button"
                onClick={handleRandomizeSeed}
                disabled={isRunning}
                style={{ background: 'none', border: 'none', color: 'var(--cyan-accent)', cursor: 'pointer', fontSize: '0.72rem', display: 'flex', alignItems: 'center', gap: '4px' }}
              >
                <Shuffle size={12} /> Randomize
              </button>
            </label>
            <input
              type="number"
              className="form-input"
              value={seed}
              onChange={(e) => setSeed(parseInt(e.target.value) || 0)}
              disabled={isRunning}
            />
          </div>

          {/* Bug Injection Selector */}
          <div className="form-group">
            <label className="form-label">Controlled Fault Injection</label>
            <select
              className="form-select"
              value={bugInjection}
              onChange={(e) => setBugInjection(e.target.value)}
              disabled={isRunning}
            >
              <option value="none">None (Golden RTL - Clean)</option>
              <option value="fifo_overflow">Bug A: FIFO Full Overwrite</option>
              <option value="arbiter_starve">Bug B: Arbiter Priority Inversion</option>
              <option value="addr_stride">Bug C: Memory Address Stride (+8)</option>
            </select>
          </div>

          {/* Timeout */}
          <div className="form-group">
            <label className="form-label">Watchdog Timeout (Sec)</label>
            <input
              type="number"
              className="form-input"
              value={timeoutSec}
              onChange={(e) => setTimeoutSec(parseInt(e.target.value) || 60)}
              disabled={isRunning}
              min={1}
              max={300}
            />
          </div>
        </div>

        {/* Action Buttons */}
        <div style={{ display: 'flex', gap: '14px', alignItems: 'center' }}>
          <button
            className="btn-primary"
            onClick={handleRunSimulation}
            disabled={isRunning}
          >
            {isRunning ? (
              <>
                <RotateCcw className="animate-spin" size={16} />
                Executing Simulation with VVP...
              </>
            ) : (
              <>
                <Play size={16} />
                Execute Simulation
              </>
            )}
          </button>

          <button
            className="btn-secondary"
            onClick={handleRunBatch}
            disabled={isRunning}
          >
            <Zap size={16} />
            Run 5-Seed Batch Regression
          </button>

          {bugInjection !== 'none' && (
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px', color: '#f87171', fontSize: '0.82rem', marginLeft: 'auto' }}>
              <Flame size={16} />
              Fault Mode Active: Simulation is expected to detect and fail.
            </div>
          )}
        </div>
      </div>

      {/* Error Alert */}
      {errorMessage && (
        <div style={{
          background: 'rgba(239, 68, 68, 0.1)',
          border: '1px solid rgba(239, 68, 68, 0.4)',
          borderRadius: '8px',
          padding: '14px 18px',
          display: 'flex',
          alignItems: 'center',
          gap: '12px',
          color: '#f87171'
        }}>
          <AlertTriangle size={20} />
          <div>
            <div style={{ fontWeight: 600 }}>Simulation Launch Error</div>
            <div style={{ fontSize: '0.85rem' }}>{errorMessage}</div>
          </div>
        </div>
      )}

      {/* Execution Results Summary Banner */}
      {runResult && (
        <div className="glass-card" style={{
          borderColor: runResult.verdict === 'PASSED' ? 'rgba(16, 185, 129, 0.4)' : 'rgba(239, 68, 68, 0.4)',
          background: runResult.verdict === 'PASSED'
            ? 'linear-gradient(135deg, rgba(16, 185, 129, 0.08) 0%, rgba(13, 17, 23, 0.8) 100%)'
            : 'linear-gradient(135deg, rgba(239, 68, 68, 0.08) 0%, rgba(13, 17, 23, 0.8) 100%)'
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
              <div style={{
                width: '44px',
                height: '44px',
                borderRadius: '8px',
                background: runResult.verdict === 'PASSED' ? 'rgba(16, 185, 129, 0.2)' : 'rgba(239, 68, 68, 0.2)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center'
              }}>
                {runResult.verdict === 'PASSED' ? (
                  <CheckCircle2 size={26} color="var(--emerald-success)" />
                ) : (
                  <XCircle size={26} color="var(--ruby-error)" />
                )}
              </div>
              <div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <h2 style={{ fontSize: '1.25rem', fontWeight: 800, color: '#fff', fontFamily: 'var(--font-display)' }}>
                    {runResult.verdict === 'PASSED' ? 'SIMULATION PASSED' : 'SIMULATION FAILED'}
                  </h2>
                  <span className={`metric-pill ${runResult.verdict === 'PASSED' ? 'pill-green' : 'pill-red'}`}>
                    {runResult.failure_category === 'NONE' ? 'ALL CHECKS CLEAN' : runResult.failure_category}
                  </span>
                </div>
                <div style={{ fontSize: '0.8rem', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)', marginTop: '2px' }}>
                  Run ID: {runResult.run_id} | Seed: {runResult.seed} (0x{runResult.seed.toString(16).toUpperCase()}) | Suite: {runResult.suite}
                </div>
              </div>
            </div>

            <div style={{ display: 'flex', gap: '20px', alignItems: 'center' }}>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', textTransform: 'uppercase' }}>Tests Outcome</div>
                <div style={{ fontSize: '1.1rem', fontWeight: 700, fontFamily: 'var(--font-mono)', color: '#fff' }}>
                  {runResult.passed_tests} / {runResult.total_tests}
                </div>
              </div>

              <div style={{ textAlign: 'right' }}>
                <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', textTransform: 'uppercase' }}>Assertions</div>
                <div style={{ fontSize: '1.1rem', fontWeight: 700, fontFamily: 'var(--font-mono)', color: runResult.assertion_violation_count === 0 ? 'var(--emerald-success)' : 'var(--ruby-error)' }}>
                  {runResult.assertion_violation_count} Fails
                </div>
              </div>

              <div style={{ textAlign: 'right' }}>
                <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', textTransform: 'uppercase' }}>Sim Runtime</div>
                <div style={{ fontSize: '1.1rem', fontWeight: 700, fontFamily: 'var(--font-mono)', color: 'var(--cyan-accent)' }}>
                  {runResult.sim_time_sec}s
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Terminal and Testcases Grid */}
      <div className="grid-2">
        {/* Terminal Window */}
        <div className="terminal-window">
          <div className="terminal-header">
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Terminal size={14} color="var(--amd-red)" />
              <span>Simulation Standard Output Stream</span>
            </div>
            <span>{activeJobId ? activeJobId : 'Idle'}</span>
          </div>
          <div className="terminal-body">
            {rawLog ? (
              rawLog.split('\n').map((line, idx) => {
                let cls = '';
                if (line.includes('PASS') || line.includes('PASSED') || line.includes('[+]')) {
                  cls = 'terminal-line-pass';
                } else if (line.includes('FAIL') || line.includes('FAILED') || line.includes('[-]')) {
                  cls = 'terminal-line-fail';
                } else if (line.includes('>>> TEST_START:')) {
                  cls = 'terminal-line-info';
                } else if (line.includes('ASSERTION')) {
                  cls = 'terminal-line-warn';
                }
                return (
                  <div key={idx} className={cls}>
                    {line}
                  </div>
                );
              })
            ) : (
              <div style={{ color: 'var(--text-faint)', fontStyle: 'italic', padding: '20px 0' }}>
                Terminal waiting for simulation launch. Configure parameters above and click "Execute Simulation".
              </div>
            )}
          </div>
        </div>

        {/* Detailed Test Breakdown */}
        <div className="glass-card" style={{ display: 'flex', flexDirection: 'column' }}>
          <div className="card-header">
            <div className="card-title">
              <CheckCircle2 size={18} />
              Testcase Verification Matrix
            </div>
            {runResult && (
              <span className="metric-pill pill-cyan">
                {runResult.passed_tests} / {runResult.total_tests} Verified
              </span>
            )}
          </div>

          <div style={{ flex: 1, maxHeight: '340px', overflowY: 'auto' }}>
            {runResult?.tests && runResult.tests.length > 0 ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                {runResult.tests.map((tc, idx) => (
                  <div
                    key={idx}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      padding: '9px 12px',
                      background: 'rgba(255, 255, 255, 0.02)',
                      borderRadius: '6px',
                      border: '1px solid var(--border-subtle)',
                      fontSize: '0.82rem'
                    }}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                      {tc.status === 'PASSED' ? (
                        <CheckCircle2 size={16} color="var(--emerald-success)" />
                      ) : (
                        <XCircle size={16} color="var(--ruby-error)" />
                      )}
                      <span style={{ fontFamily: 'var(--font-mono)', fontWeight: 600 }}>{tc.name}</span>
                    </div>
                    <span className={`metric-pill ${tc.status === 'PASSED' ? 'pill-green' : 'pill-red'}`}>
                      {tc.status}
                    </span>
                  </div>
                ))}
              </div>
            ) : (
              <div style={{ color: 'var(--text-faint)', textAlign: 'center', padding: '60px 0', fontSize: '0.88rem' }}>
                No active test run results to display.
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
