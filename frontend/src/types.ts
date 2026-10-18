/**
 * Type Definitions for DMA Verification & Performance Lab Dashboard
 */

export interface ToolInfo {
  tool: string;
  path: string;
  version?: string;
  available: boolean;
}

export interface SystemStatus {
  project_name: string;
  phase: number;
  clock_frequency_mhz: number;
  os: string;
  python_version: string;
  tools: Record<string, ToolInfo>;
  ready: boolean;
}

export interface TestCaseResult {
  name: string;
  status: 'PASSED' | 'FAILED' | 'UNKNOWN';
  details: string[];
  result_raw?: string;
}

export interface AssertionViolation {
  cycle: number;
  assertion: string;
  message: string;
}

export interface ScoreboardMismatch {
  word_offset: number;
  address: string;
  expected: string;
  actual: string;
  diff: string;
}

export interface FunctionalCoverageSummary {
  total_bins: number;
  covered_bins: number;
  coverage_percentage: number;
  categories?: Record<string, number>;
}

export interface SimRunSummary {
  run_id: string;
  suite: string;
  seed: number;
  bug_injection: string;
  verdict: 'PASSED' | 'FAILED' | 'TIMEOUT' | 'UNKNOWN';
  failure_category: string;
  compile_time_sec: number;
  sim_time_sec: number;
  total_tests: number;
  passed_tests: number;
  failed_tests: number;
  assertion_violation_count: number;
  assertion_violations: AssertionViolation[];
  scoreboard_mismatch_count: number;
  scoreboard_mismatches: ScoreboardMismatch[];
  functional_coverage: FunctionalCoverageSummary;
  vcd_generated: boolean;
  run_dir: string;
  log_file: string;
  tests: TestCaseResult[];
}

export interface SimJobStatus {
  run_id: string;
  suite: string;
  status: 'QUEUED' | 'RUNNING' | 'COMPLETED' | 'FAILED' | 'TIMEOUT';
  start_time: string;
  elapsed_sec: number;
  result?: SimRunSummary;
  error?: string;
}

export interface HistoryItem {
  run_id: string;
  suite: string;
  seed: number;
  bug_injection: string;
  verdict: string;
  failure_category: string;
  sim_time_sec: number;
  total_tests: number;
  passed_tests: number;
  failed_tests: number;
  assertion_violation_count: number;
  scoreboard_mismatch_count: number;
}

export interface BenchmarkTrial {
  exp_id: number;
  sweep: string;
  xfer_bytes: number;
  burst_beats: number;
  mem_latency: number;
  policy: string;
  contention: string;
  cycles: number;
  throughput_bytes_per_cycle: number;
  throughput_mb_s: number;
  bus_utilization_pct: number;
  max_fifo_occupancy: number;
  wait_cycles_req0: number;
  wait_cycles_req1: number;
  grants_req0: number;
  grants_req1: number;
}

export interface BenchmarkSummary {
  metadata: {
    title: string;
    phase: number;
    timestamp: string;
    simulator: string;
    clock_frequency_mhz: number;
    clock_period_ns: number;
    total_trials: number;
  };
  metric_definitions: Record<string, string>;
  sweeps: {
    burst_size_scaling: BenchmarkTrial[];
    transfer_length_scaling: {
      burst_1: BenchmarkTrial[];
      burst_4: BenchmarkTrial[];
      burst_8: BenchmarkTrial[];
    };
    memory_latency_sensitivity: {
      burst_1: BenchmarkTrial[];
      burst_4: BenchmarkTrial[];
      burst_8: BenchmarkTrial[];
    };
    arbitration_and_contention: BenchmarkTrial[];
  };
}

export interface TriageExperiment {
  experiment_id: string;
  name: string;
  target_module: string;
  bug_injected: string;
  suite_used: string;
  description: string;
  expected_verdict: string;
  actual_verdict: string;
  failure_category: string;
  detected_properly: boolean;
  passed_tests: number;
  failed_tests: number;
  assertion_violations: AssertionViolation[];
  scoreboard_mismatches: ScoreboardMismatch[];
  run_dir: string;
  log_file: string;
}

export interface TriageReport {
  metadata: {
    title: string;
    phase: number;
    timestamp: string;
    total_experiments: number;
    detection_rate_pct: number;
  };
  experiments: TriageExperiment[];
}

export interface ArtifactItem {
  name: string;
  path: string;
  size_bytes: number;
  last_modified: string;
}

export interface WaveformLandmark {
  cycle: number;
  label: string;
  type: 'info' | 'active' | 'success' | 'error';
}

export interface WaveformSample {
  cycle: number;
  time_ns: number;
  signals: Record<string, string | number>;
}

export interface ParsedWaveform {
  vcd_file: string;
  clock_frequency_mhz: number;
  clock_period_ns: number;
  total_cycles_in_vcd: number;
  window: {
    start_cycle: number;
    end_cycle: number;
    count: number;
  };
  landmarks: WaveformLandmark[];
  timeline: WaveformSample[];
}
