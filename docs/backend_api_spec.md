# DMA Verification Lab - Backend REST API Specification (Phase 6)

## 1. Overview & Architectural Design

The backend service is built using **FastAPI** on Python 3.13, exposing RESTful endpoints that bridge the frontend dashboard directly to the physical hardware simulation environment (Icarus Verilog v12).

### Architectural Guardrails:
- **Zero Arbitrary Execution**: The API strictly invokes predefined, parameter-validated Python automation routines ([`sim/regression_runner.py`](file:///c:/Users/aryan/Downloads/amd/P1/sim/regression_runner.py)). It does **NOT** expose arbitrary shell commands.
- **Run Isolation**: Every simulation run generates a sandboxed run directory (`runs/run_<timestamp>_<uuid>/`) preserving logs, waveforms, and metadata without race conditions.
- **Path Traversal Protection**: File and artifact requests are strictly sanitized against path traversal (`../`) attacks, restricting reads exclusively to approved project subdirectories (`docs/`, `reports/`, `runs/`).
- **Asynchronous Execution Support**: Simulations can be launched synchronously (direct HTTP response) or asynchronously (background worker with `/api/sim/status/{run_id}` polling).
- **CORS Enabled**: Configured for local development (`*` origin support), allowing seamless integration with Vite / React on ports `5173`, `3000`, etc.

---

## 2. API Endpoint Catalog

### 2.1 System & Environment Status
#### `GET /api/status`
Returns the environment health, toolchain discovery status, system clock frequency, and verification readiness.
- **Response `200 OK`**:
```json
{
  "project_name": "DMA Verification & Performance Analysis Lab",
  "phase": 6,
  "clock_frequency_mhz": 100.0,
  "os": "win32",
  "python_version": "3.13.5",
  "tools": {
    "iverilog": {
      "tool": "Icarus Verilog",
      "path": "C:\\Users\\aryan\\iverilog\\app\\bin\\iverilog.exe",
      "version": "Icarus Verilog version 12.0",
      "available": true
    },
    "vvp": {
      "tool": "Icarus VVP Engine",
      "path": "C:\\Users\\aryan\\iverilog\\app\\bin\\vvp.exe",
      "version": "Icarus Verilog runtime version 12.0",
      "available": true
    },
    "python": {
      "tool": "Python",
      "path": "C:\\Program Files\\Python313\\python.exe",
      "version": "3.13.5",
      "available": true
    },
    "node": {
      "tool": "Node.js",
      "path": "C:\\Program Files\\nodejs\\node.exe",
      "version": "v22.12.0",
      "available": true
    },
    "quartus": {
      "tool": "Intel Quartus Prime",
      "path": "Not installed in PATH",
      "version": "Not Detected",
      "available": false
    }
  },
  "ready": true
}
```

---

### 2.2 Simulation Execution
#### `POST /api/sim/run`
Launches a cycle-accurate Verilog simulation.
- **Request Body**:
```json
{
  "suite": "top",
  "seed": 305419896,
  "bug_injection": "none",
  "timeout_sec": 60,
  "async_exec": false
}
```
- **Fields**:
  - `suite`: `"top"` | `"fifo"` | `"arbiter"` | `"benchmark"` (default: `"top"`)
  - `seed`: Integer 32-bit random seed (optional, defaults to auto-generated seed)
  - `bug_injection`: `"none"` | `"fifo_overflow"` | `"arbiter_starve"` | `"addr_stride"`
  - `timeout_sec`: Watchdog timeout in seconds (1 to 300)
  - `async_exec`: Boolean (if true, returns immediately with `run_id`)
- **Synchronous Response `200 OK`**:
```json
{
  "run_id": "run_20261018_224415_2eb977",
  "suite": "top",
  "seed": 305419896,
  "bug_injection": "none",
  "verdict": "PASSED",
  "failure_category": "NONE",
  "compile_time_sec": 0.072,
  "sim_time_sec": 0.207,
  "total_tests": 22,
  "passed_tests": 22,
  "failed_tests": 0,
  "assertion_violation_count": 0,
  "functional_coverage": {
    "total_bins": 24,
    "covered_bins": 24,
    "coverage_percentage": 100.0
  },
  "vcd_generated": true,
  "run_dir": "C:\\Users\\aryan\\Downloads\\amd\\P1\\runs\\run_...",
  "log_file": "C:\\Users\\aryan\\Downloads\\amd\\P1\\runs\\...\\sim.log"
}
```
- **Error Responses**:
  - `400 Bad Request`: Invalid parameter value.
  - `422 Unprocessable Entity`: Schema violation (e.g., negative timeout, invalid suite).

#### `POST /api/sim/batch`
Executes a multi-seed batch regression.
- **Request Body**:
```json
{
  "suite": "top",
  "seed_count": 5,
  "bug_injection": "none",
  "timeout_sec": 60
}
```
- **Response `200 OK`**:
```json
{
  "timestamp": "2026-10-18T17:14:17Z",
  "suite": "top",
  "total_runs": 5,
  "passed_runs": 5,
  "failed_runs": 0,
  "runs": [ ... ]
}
```

#### `GET /api/sim/status/{run_id}`
Polls the execution status of a simulation.
- **Response `200 OK`**:
```json
{
  "run_id": "job_20261018_225010_abc123",
  "suite": "top",
  "status": "COMPLETED",
  "start_time": "2026-10-18T17:20:10Z",
  "elapsed_sec": 0.23,
  "result": { ... },
  "error": null
}
```
- **Status Codes**: `QUEUED`, `RUNNING`, `COMPLETED`, `FAILED`, `TIMEOUT`.

#### `GET /api/sim/history?limit=50&suite=top`
Returns historical runs catalog.

#### `GET /api/sim/run/{run_id}`
Returns complete JSON summary for a run.

#### `GET /api/sim/log/{run_id}`
Returns raw simulation standard output log stream (`text/plain`).

---

### 2.3 Performance Benchmarking Endpoints
#### `GET /api/benchmark/summary`
Returns the structured benchmark dataset across all sweeps:
- Burst size scaling ($B \in \{1, 2, 4, 8\}$)
- Payload length amortization (16B to 512B)
- Memory slave latency sensitivity (0 to 4 cycles)
- Arbitration contention (Fixed-Priority vs Round-Robin)

#### `GET /api/benchmark/csv`
Streams the 40-trial flat CSV dataset (`text/csv`).

---

### 2.4 Verification Triage & Coverage
#### `GET /api/triage/report`
Returns the 4-experiment controlled bug injection dataset:
- `EXP_GOLDEN`: 100% test pass on baseline RTL.
- `EXP_BUG_FIFO`: `ASSERTION_VIOLATION` (`ASSERT_FIFO_OVF` at cycle 25).
- `EXP_BUG_ARBITER`: `TIMEOUT_WATCHDOG` (200-cycle watchdog trip on DMA starvation).
- `EXP_BUG_ADDR`: `SCOREBOARD_DATA_MISMATCH` (address stride byte error).

#### `GET /api/coverage/summary`
Returns functional coverage metrics:
- 24/24 coverage bins (100.0% coverage).
- Sub-categories: Burst sizes, transfer lengths, protocol errors, control resets, memory wait states, arbitration policies.

#### `GET /api/phase5/summary`
Returns consolidated Phase 5 simulation automation metadata.

---

### 2.5 Waveforms & Documentation
#### `GET /api/waveform/{run_id}`
Streams the raw `.vcd` Value Change Dump file (`application/octet-stream`).

#### `GET /api/waveform/info/{run_id}`
Returns waveform metadata (file existence, byte size, approximate signal count).

#### `GET /api/artifacts`
Lists all approved project markdown documentation and reports.

#### `GET /api/artifacts/{artifact_name}`
Returns the raw text content of an approved engineering artifact with path-traversal sanitization.

---

## 3. Automated Validation Evidence

The test suite [`backend/test_api.py`](file:///c:/Users/aryan/Downloads/amd/P1/backend/test_api.py) executes 23 automated end-to-end integration tests:
- **Toolchain Discovery**: 100% verified.
- **Negative & Boundary Validation**: Invalid suites, bugs, and timeouts correctly return `422/400`.
- **Synchronous Execution**: FIFO and Arbiter unit suites executed through API and verified against real simulator output.
- **Asynchronous Execution & Polling**: Background execution verified through polling loop.
- **Security**: Path traversal attempts (`../../etc/passwd`) blocked with 404/400.
- **Pytest Results**: **23 / 23 Tests Passed (100% Pass Rate in 1.46s)**.
