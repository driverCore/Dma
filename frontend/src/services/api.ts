/**
 * API Service Client for DMA Verification Lab Dashboard
 */

import {
  SystemStatus,
  SimRunSummary,
  SimJobStatus,
  HistoryItem,
  BenchmarkSummary,
  TriageReport,
  FunctionalCoverageSummary,
  ArtifactItem,
  ParsedWaveform
} from '../types';

const API_BASE = '/api';

export const ApiService = {
  // System Status
  async getStatus(): Promise<SystemStatus> {
    const res = await fetch(`${API_BASE}/status`);
    if (!res.ok) throw new Error(`Failed to fetch system status: ${res.statusText}`);
    return res.json();
  },

  // Launch Simulation
  async runSimulation(payload: {
    suite: string;
    seed?: number;
    bug_injection: string;
    timeout_sec: number;
    async_exec: boolean;
  }): Promise<SimRunSummary | { message: string; run_id: string; status_url: string }> {
    const res = await fetch(`${API_BASE}/sim/run`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ detail: res.statusText }));
      throw new Error(err.detail || 'Simulation execution failed');
    }
    return res.json();
  },

  // Launch Batch Regression
  async runBatchRegression(payload: {
    suite: string;
    seed_count: number;
    bug_injection: string;
    timeout_sec: number;
  }): Promise<any> {
    const res = await fetch(`${API_BASE}/sim/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ detail: res.statusText }));
      throw new Error(err.detail || 'Batch regression failed');
    }
    return res.json();
  },

  // Poll Job Status
  async getJobStatus(runId: string): Promise<SimJobStatus> {
    const res = await fetch(`${API_BASE}/sim/status/${runId}`);
    if (!res.ok) throw new Error(`Run '${runId}' not found`);
    return res.json();
  },

  // Get Historical Runs
  async getHistory(limit: number = 50, suite?: string): Promise<HistoryItem[]> {
    const query = new URLSearchParams({ limit: limit.toString() });
    if (suite) query.append('suite', suite);
    const res = await fetch(`${API_BASE}/sim/history?${query.toString()}`);
    if (!res.ok) throw new Error(`Failed to fetch history: ${res.statusText}`);
    return res.json();
  },

  // Get Run Log
  async getRunLog(runId: string): Promise<string> {
    const res = await fetch(`${API_BASE}/sim/log/${runId}`);
    if (!res.ok) throw new Error(`Failed to fetch log for '${runId}'`);
    return res.text();
  },

  // Performance Benchmarks
  async getBenchmarkSummary(): Promise<BenchmarkSummary> {
    const res = await fetch(`${API_BASE}/benchmark/summary`);
    if (!res.ok) throw new Error(`Failed to load benchmark summary: ${res.statusText}`);
    return res.json();
  },

  // Failure Triage Report
  async getTriageReport(): Promise<TriageReport> {
    const res = await fetch(`${API_BASE}/triage/report`);
    if (!res.ok) throw new Error(`Failed to load triage report: ${res.statusText}`);
    return res.json();
  },

  // Functional Coverage
  async getCoverageSummary(): Promise<FunctionalCoverageSummary> {
    const res = await fetch(`${API_BASE}/coverage/summary`);
    if (!res.ok) throw new Error(`Failed to load coverage metrics: ${res.statusText}`);
    return res.json();
  },

  // Artifacts
  async listArtifacts(): Promise<ArtifactItem[]> {
    const res = await fetch(`${API_BASE}/artifacts`);
    if (!res.ok) throw new Error(`Failed to list artifacts: ${res.statusText}`);
    return res.json();
  },

  async getArtifact(name: string): Promise<string> {
    const res = await fetch(`${API_BASE}/artifacts/${name}`);
    if (!res.ok) throw new Error(`Failed to read artifact '${name}'`);
    return res.text();
  },

  // Waveform Parsed Timeline
  async getParsedWaveform(runId: string = 'latest', startCycle: number = 0, count: number = 80): Promise<ParsedWaveform> {
    const res = await fetch(`${API_BASE}/waveform/parsed/${runId}?start_cycle=${startCycle}&count=${count}`);
    if (!res.ok) {
      const err = await res.json().catch(() => ({ detail: res.statusText }));
      throw new Error(err.detail || `Failed to fetch parsed waveform for '${runId}'`);
    }
    return res.json();
  }
};
