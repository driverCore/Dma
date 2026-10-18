import React, { useEffect, useState } from 'react';
import {
  Clock,
  CheckCircle2,
  XCircle,
  FileText,
  Download,
  Filter,
  RefreshCw,
  Eye,
  Terminal
} from 'lucide-react';
import { ApiService } from '../services/api';
import { HistoryItem } from '../types';

export const HistoryView: React.FC = () => {
  const [history, setHistory] = useState<HistoryItem[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [selectedSuite, setSelectedSuite] = useState<string>('all');
  const [activeLogRunId, setActiveLogRunId] = useState<string | null>(null);
  const [logContent, setLogContent] = useState<string>('');
  const [loadingLog, setLoadingLog] = useState<boolean>(false);

  const fetchHistory = async () => {
    try {
      setLoading(true);
      const data = await ApiService.getHistory(50, selectedSuite === 'all' ? undefined : selectedSuite);
      setHistory(data);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchHistory();
  }, [selectedSuite]);

  const handleViewLog = async (runId: string) => {
    setActiveLogRunId(runId);
    setLoadingLog(true);
    try {
      const text = await ApiService.getRunLog(runId);
      setLogContent(text);
    } catch (err: any) {
      setLogContent(`Failed to load log for '${runId}': ${err.message}`);
    } finally {
      setLoadingLog(false);
    }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
      <div className="glass-card" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '6px' }}>
            <span className="metric-pill pill-cyan">REGRESSION CATALOG</span>
            <span className="metric-pill pill-purple">PERSISTENT RUNS DATABASE</span>
          </div>
          <h2 style={{ fontSize: '1.4rem', fontWeight: 800, color: '#fff', fontFamily: 'var(--font-display)' }}>
            Historical Simulation & Regression Runs
          </h2>
          <div style={{ color: 'var(--text-muted)', fontSize: '0.85rem' }}>
            Audit trail of all executed simulation trials, seeds, execution times, and artifacts.
          </div>
        </div>

        <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
          <select
            className="form-select"
            value={selectedSuite}
            onChange={(e) => setSelectedSuite(e.target.value)}
          >
            <option value="all">All Suites</option>
            <option value="top">Top Subsystem</option>
            <option value="fifo">FIFO Unit</option>
            <option value="arbiter">Arbiter Unit</option>
          </select>

          <button className="btn-secondary" onClick={fetchHistory} disabled={loading}>
            <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
            Refresh
          </button>
        </div>
      </div>

      {/* History Table */}
      <div className="glass-card" style={{ padding: '0', overflow: 'hidden' }}>
        <div className="data-table-container" style={{ border: 'none' }}>
          <table className="data-table">
            <thead>
              <tr>
                <th>Run Identifier</th>
                <th>Suite</th>
                <th>Seed (Hex)</th>
                <th>Bug Mode</th>
                <th>Verdict</th>
                <th>Tests</th>
                <th>Assertions</th>
                <th>Runtime</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {history.length > 0 ? (
                history.map((h, idx) => (
                  <tr key={idx}>
                    <td style={{ fontFamily: 'var(--font-mono)', fontWeight: 600, color: '#fff' }}>
                      {h.run_id}
                    </td>
                    <td>
                      <span className="metric-pill pill-cyan">{h.suite}</span>
                    </td>
                    <td style={{ color: 'var(--text-muted)' }}>
                      0x{h.seed.toString(16).toUpperCase()}
                    </td>
                    <td>
                      <span className={`metric-pill ${h.bug_injection === 'none' ? 'pill-green' : 'pill-red'}`}>
                        {h.bug_injection}
                      </span>
                    </td>
                    <td>
                      <span className={`metric-pill ${h.verdict === 'PASSED' ? 'pill-green' : 'pill-red'}`}>
                        {h.verdict}
                      </span>
                    </td>
                    <td>{h.passed_tests} / {h.total_tests}</td>
                    <td style={{ color: h.assertion_violation_count === 0 ? 'var(--emerald-success)' : 'var(--ruby-error)' }}>
                      {h.assertion_violation_count}
                    </td>
                    <td>{h.sim_time_sec}s</td>
                    <td>
                      <div style={{ display: 'flex', gap: '8px' }}>
                        <button
                          className="btn-secondary"
                          style={{ padding: '4px 8px', fontSize: '0.74rem' }}
                          onClick={() => handleViewLog(h.run_id)}
                        >
                          <Eye size={12} /> Log
                        </button>
                        <a
                          href={`/api/waveform/${h.run_id}`}
                          download={`${h.run_id}_waveform.vcd`}
                          className="btn-secondary"
                          style={{ padding: '4px 8px', fontSize: '0.74rem', textDecoration: 'none' }}
                        >
                          <Download size={12} /> VCD
                        </a>
                      </div>
                    </td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={9} style={{ textAlign: 'center', padding: '40px', color: 'var(--text-faint)' }}>
                    {loading ? 'Loading historical simulation records...' : 'No historical simulation runs found.'}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Log Modal / Drawer */}
      {activeLogRunId && (
        <div className="glass-card" style={{ borderColor: 'var(--border-active)' }}>
          <div className="card-header">
            <div className="card-title">
              <Terminal size={18} />
              Simulation Log Inspector: <span style={{ fontFamily: 'var(--font-mono)', color: 'var(--cyan-accent)' }}>{activeLogRunId}</span>
            </div>
            <button
              className="btn-secondary"
              onClick={() => setActiveLogRunId(null)}
              style={{ padding: '4px 10px', fontSize: '0.75rem' }}
            >
              Close
            </button>
          </div>

          <div className="terminal-window">
            <div className="terminal-body" style={{ maxHeight: '350px' }}>
              {loadingLog ? 'Loading log content...' : logContent}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
