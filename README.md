# DMA Verification & Performance Analysis Lab

[![Hardware Simulation](https://img.shields.io/badge/Verilog-IEEE%201364--2001-red.svg)](file:///c:/Users/aryan/Downloads/amd/P1/rtl)
[![Verification Coverage](https://img.shields.io/badge/Functional%20Coverage-100.0%25%20(24%2F24%20bins)-emerald.svg)](file:///c:/Users/aryan/Downloads/amd/P1/reports/phase3_coverage.json)
[![Assertion Checks](https://img.shields.io/badge/Protocol%20Assertions-6%20Active%20%7C%200%20Failures-brightgreen.svg)](file:///c:/Users/aryan/Downloads/amd/P1/tb/tb_dma_top.v)
[![Performance Benchmark](https://img.shields.io/badge/Max%20Throughput-343.35%20MB%2Fs%20(Burst%208)-cyan.svg)](file:///c:/Users/aryan/Downloads/amd/P1/reports/benchmark_summary.json)
[![Fault Triage](https://img.shields.io/badge/Fault%20Triage-100%25%20Detection%20Rate-purple.svg)](file:///c:/Users/aryan/Downloads/amd/P1/reports/failure_triage_report.json)
[![Backend API](https://img.shields.io/badge/FastAPI%20Tests-25%2F25%20Passing-blue.svg)](file:///c:/Users/aryan/Downloads/amd/P1/backend/test_api.py)
[![Frontend Dashboard](https://img.shields.io/badge/Frontend-React%2019%20%2B%20TypeScript-orange.svg)](file:///c:/Users/aryan/Downloads/amd/P1/frontend)

An end-to-end, industrial-grade **Direct Memory Access (DMA) Verification and Performance Analysis Lab** built to demonstrate core competencies required for **AMD's Design & Performance Verification Hardware Engineering Internship**.

The project encompasses synthesizable Verilog-2001 RTL, self-checking verification testbenches, concurrent protocol assertions, comprehensive functional coverage, empirical cycle-accurate benchmarking, automated fault injection triage, FPGA static timing analysis, and an interactive dark aerospace web dashboard with a cycle-accurate digital waveform debugger.

---

## Table of Contents

1. [Architectural Overview](#1-architectural-overview)
2. [RTL Subsystem Implementation](#2-rtl-subsystem-implementation)
3. [Self-Checking Verification Infrastructure](#3-self-checking-verification-infrastructure)
4. [Empirical Performance Benchmarking](#4-empirical-performance-benchmarking)
5. [Automated Failure Triage & Fault Injection](#5-automated-failure-triage--fault-injection)
6. [Interactive Web Dashboard & Waveform Debugger](#6-interactive-web-dashboard--waveform-debugger)
7. [FPGA Synthesis & Timing Analysis](#7-fpga-synthesis--timing-analysis)
8. [Quickstart & Reproducibility Guide](#8-quickstart--reproducibility-guide)
9. [Project Deliverable Matrix](#9-project-deliverable-matrix)

---

## 1. Architectural Overview

```
                                  +---------------------------------------------------+
                                  |                   DMA Subsystem                   |
                                  |                                                   |
      Host Config Bus             |   +-------------+           +-----------------+   |
  ==============================> |   | CSR Config  | --------> | Burst Execution |   |
  (cfg_wr_en, addr, wdata)        |   | Regs (32b)  |           | FSM Engine      |   |
                                  |   +-------------+           +-----------------+   |
                                  |                                 |          ^      |
                                  |                                 v          |      |
                                  |                     +-----------------+    |      |
                                  |                     | Synchronous     |    |      |
                                  |                     | FWFT FIFO (16x32|    |      |
                                  |                     +-----------------+    |      |
                                  |                               |            |      |
                                  |                               v            |      |
      External Master Req         |   +-----------------------------------------------+
  ==============================> |   |       Multi-Master Shared Bus Arbiter         |
  (ext_req, ext_burst_lock)       |   | (Fixed-Priority / Round-Robin + Burst Locking)|
                                  |   +-----------------------------------------------+
                                  +---------------------------|-----------------------+
                                                              |
                                                              v Shared Memory Bus
                                              (mem_req_valid, addr, wdata, rsp_valid)
```

The subsystem is clocked at **100.0 MHz** ($T_{clk} = 10.0\text{ ns}$) with an active-low synchronous reset. It interfaces to host software via a memory-mapped CSR configuration bus and transfers multi-word bursts between primary memory locations without CPU intervention.

---

## 2. RTL Subsystem Implementation

All RTL modules are written in standard synthesizable **IEEE 1364-2001 Verilog**:

### 1. First-Word Fall-Through (FWFT) Synchronous FIFO ([`rtl/dma_fifo.v`](file:///c:/Users/aryan/Downloads/amd/P1/rtl/dma_fifo.v))
- **Lookahead Architecture**: Data at `rd_ptr` is available at `rd_data` without requiring a read-enable pulse beforehand.
- **Write-Forwarding Bypass**: Zero-latency bypass (`rd_data = wr_data` when writing to an empty FIFO).
- **Watermark Comparators**: Hardware flags for `almost_full` ($\ge 14$ words) and `almost_empty` ($\le 2$ words).
- **Corner-Case Protection**: Deterministic resolution of simultaneous read and write on empty and full boundaries with overflow/underflow detection.

### 2. Multi-Master Shared Resource Arbiter ([`rtl/dma_arbiter.v`](file:///c:/Users/aryan/Downloads/amd/P1/rtl/dma_arbiter.v))
- **Dual Policy Support**: Dynamically switchable between **Fixed-Priority** (DMA Master 0 > External Master 1) and **Round-Robin** fairness.
- **Burst Locking Mechanism**: Handshake locking (`burst_lock`) guarantees uninterrupted multi-beat memory bursts, preventing bus thrashing and interleaving corruption.
- **Telemetry Counters**: Dedicated 32-bit registers tracking `wait_cycles_req0`, `wait_cycles_req1`, `grants_req0`, and `grants_req1` for hardware contention analysis.

### 3. Top-Level Integration & FSM Engine ([`rtl/dma_top.v`](file:///c:/Users/aryan/Downloads/amd/P1/rtl/dma_top.v))
- **9-State Robust FSM**: `IDLE` $\rightarrow$ `VALIDATE` $\rightarrow$ `READ_REQ` $\rightarrow$ `READ_WAIT` $\rightarrow$ `WRITE_REQ` $\rightarrow$ `WRITE_WAIT` $\rightarrow$ `CHECK_DONE` $\rightarrow$ `DONE` / `ERROR`.
- **Hardware Error Trapping**: Traps unaligned transfers (non-4-byte multiples), zero-length transfers, bus error responses (`mem_rsp_err`), and watchdog timeouts ($> 500$ cycles).
- **CSR Interface**: Software-accessible 32-bit registers for Source Address (`0x00`), Destination Address (`0x04`), Transfer Length (`0x08`), Burst Configuration (`0x0C`), Control (`0x10`), Status (`0x14`), and Arbiter Telemetry (`0x20`-`0x2C`).

---

## 3. Self-Checking Verification Infrastructure

The testbench infrastructure ([`tb/tb_dma_top.v`](file:///c:/Users/aryan/Downloads/amd/P1/tb/tb_dma_top.v)) provides exhaustive, automated, self-checking functional verification:

### 1. Self-Checking Golden Scoreboard
- Dynamic memory model mirrors source and destination regions in real time.
- Verifies every transferred 32-bit word, detecting data corruption, byte-swapping, offset shifts, or payload truncation.

### 2. Protocol Assertions (Concurrent Hardware Checks)
1. **`A1_NO_UNDERFLOW`**: Asserts `fifo_underflow == 0` across all read cycles.
2. **`A2_NO_OVERFLOW`**: Asserts `fifo_overflow == 0` during high-throughput bursts.
3. **`A3_REQ_STABILITY`**: Enforces that once `mem_req_valid` is asserted, address and control lines remain stable until `mem_req_ready` handshakes.
4. **`A4_BURST_CONTINUITY`**: Confirms that when `burst_lock` is active, the arbiter never revokes `grant`.
5. **`A5_FSM_LEGAL_STATES`**: Traps any entry into unmapped or illegal FSM state vectors.
6. **`A6_NO_TRANSFER_DROPS`**: Validates total transferred bytes exactly matches configured `transfer_length`.

### 3. Functional Coverage (100.0% / 24 Bins Covered)
- **Transfer Length Coverage**: 4B, 16B, 64B, 256B, 1024B ($5/5$ bins).
- **Burst Size Coverage**: Single-beat (1), 4-beat, 8-beat ($3/3$ bins).
- **Memory Latency Backpressure**: 0 cycles, 1 cycle, 2 cycles, 4 cycles ($4/4$ bins).
- **Arbitration Modes**: Fixed-Priority, Round-Robin ($2/2$ bins).
- **Contention Scenarios**: Idle, Non-Contended, Contended Master 1 ($3/3$ bins).
- **Error Conditions**: Zero length, unaligned address, bus error, timeout ($4/4$ bins).
- **FIFO Boundaries**: Empty, Almost Empty, Almost Full, Full ($4/4$ bins).

---

## 4. Empirical Performance Benchmarking

Extensive cycle-accurate benchmarking ([`sim/run_benchmark.py`](file:///c:/Users/aryan/Downloads/amd/P1/sim/run_benchmark.py)) evaluated **40 hardware trials** across 4 sweeps, exporting raw CSV telemetry ([`reports/benchmark_results.csv`](file:///c:/Users/aryan/Downloads/amd/P1/reports/benchmark_results.csv)):

| Experiment Dimension | Baseline Condition | Optimized Condition | Metric Evaluated | Empirical Hardware Finding |
| :--- | :---: | :---: | :---: | :--- |
| **Burst Size Scaling** | Burst 1 (1 beat) | Burst 8 (8 beats) | Throughput (MB/s) | **3.48x Improvement**: 98.46 MB/s $\rightarrow$ **343.35 MB/s** (Bus utilization rises from 24.6% to 85.8%). |
| **Payload Amortization** | 16 Bytes (Short) | 1024 Bytes (Long) | Efficiency (%) | **2.62x Gain**: Amortizes CSR configuration and FSM validation overheads over bulk data. |
| **Memory Latency** | Latency = 0 cycles | Latency = 4 cycles | Degradation Factor | **61.5% Loss**: Throughput drops to 132.23 MB/s due to memory bus stall waits. |
| **Arbitration Contention**| Uncontended | Contended (Round-Robin)| Contention Wait Cycles| Telemetry measures **128 wait cycles** for Master 0 with **perfect 50.0% bandwidth fairness**. |

---

## 5. Automated Failure Triage & Fault Injection

A standalone regression and triage engine ([`sim/regression_runner.py`](file:///c:/Users/aryan/Downloads/amd/P1/sim/regression_runner.py)) operates with isolated execution sandboxes (`runs/run_<timestamp>_<uuid>/`), timeout watchdogs, and automatic failure categorization.

A controlled fault injection campaign tested three critical hardware failure modes:

| Bug Injection Define | Injected RTL Mutation | Testbench Detection Mechanism | Resulting Verdict | Triage Categorization |
| :--- | :--- | :--- | :---: | :--- |
| **`BUG_FIFO_OVERWRITE`** | FIFO write logic ignores `full` flag | Assertion `A2_NO_OVERFLOW` trips at Cycle 32 | **FAILED** | `ASSERTION_VIOLATION` (100% caught) |
| **`BUG_ARBITER_STARVE`** | Strict priority inverted to starve Master 0 | Watchdog counter exceeds 500-cycle threshold | **FAILED** | `SIMULATION_TIMEOUT` (100% caught) |
| **`BUG_ADDR_STRIDE`** | Address counter strides by 8 bytes instead of 4 | Scoreboard flags memory mismatch at address `0x00000004` | **FAILED** | `SCOREBOARD_MISMATCH` (100% caught) |

*Triage Result: **100% detection rate** across all failure categories.*

---

## 6. Interactive Web Dashboard & Waveform Debugger

The web platform provides a hardware telemetry interface running on **FastAPI** (port `8000`) and **React 19 + TypeScript** (port `5173`):

### 1. Web Views & Capabilities
- **Overview**: System toolchain health, live simulator status, and quick-action launcher.
- **Simulation Runner**: Synchronous and asynchronous simulation runs with seed control, suite selection, bug injection toggles, and live log streaming.
- **Waveform Debugger**: Cycle-accurate digital timing diagram viewer directly parsing IEEE 1364 `.vcd` files with landmark quick-jump navigation (`Reset Deasserted`, `Read Burst Start`, `Write Burst Start`, `Transfer Complete IRQ`).
- **Performance Analysis**: Interactive telemetry charts comparing burst scaling, latency sensitivity, and arbitration contention.
- **Verification & Triage**: Failure triage matrix, functional coverage breakdown, and assertion violation inspector.
- **Regression History**: Chronological run archive with pass/fail badges, cycle times, and log downloads.
- **Architecture & Specs**: Integrated markdown reader for approved engineering specifications.

---

## 7. FPGA Synthesis & Timing Analysis

The subsystem was audited for synthesizability and configured with Synopsys Design Constraints targeting the **Intel Cyclone V SoC (`5CSXFC6D6F31C6`)**:

### Timing Constraints ([`syn/dma_constraints.sdc`](file:///c:/Users/aryan/Downloads/amd/P1/syn/dma_constraints.sdc))
- **Clock Port**: `clk` at 100.0 MHz ($T_{clk} = 10.000\text{ ns}$, 50% duty cycle).
- **Clock Uncertainty**: Setup uncertainty 0.200 ns, hold uncertainty 0.100 ns.
- **I/O Delay Budget**: Max 2.500 ns input delay, max 2.500 ns output delay.
- **False Paths**: Asynchronous reset assertion (`rst_n`) and debug telemetry observability pins.

### Estimated Resource Footprint
- **Total Estimated Registers**: ~531 Flip-Flops ($< 0.4\%$ of Cyclone V capacity).
- **Estimated Logic Elements**: ~380 ALMs ($< 1.0\%$ of Cyclone V capacity).
- **Memory Footprint**: 512 bits (infers 1 embedded M10K block or distributed LUT RAM).
- **Critical Path Slack**: Positive setup margin ($\approx +6.5\text{ ns}$ slack over 10.0 ns target period).

---

## 8. Quickstart & Reproducibility Guide

### Prerequisites
- **Icarus Verilog**: `iverilog` and `vvp` v12.0+ in system PATH.
- **Python**: Python 3.11+ with `fastapi`, `uvicorn`, `pytest`.
- **Node.js**: Node v18+ with `npm`.

### 1. Run Baseline Hardware Simulation
```bash
# Execute self-checking verification suite directly
iverilog -g2001 -I rtl -o sim/dma_tb.vvp rtl/dma_fifo.v rtl/dma_arbiter.v rtl/dma_top.v tb/tb_dma_top.v
vvp sim/dma_tb.vvp
```

### 2. Run Automated Regression Runner
```bash
# Execute 10-seed randomized regression
python sim/regression_runner.py --suite top --count 10

# Execute fault injection triage campaign
python sim/regression_runner.py --suite fifo --bug fifo_overflow
```

### 3. Run Performance Benchmark Sweeps
```bash
# Execute 40 hardware trials across all 4 sweeps
python sim/run_benchmark.py
```

### 4. Run Master End-to-End Integration Demonstration
```bash
python sim/final_integration_demo.py
```

### 5. Launch Full-Stack Web Dashboard
```bash
# Terminal 1: Launch FastAPI Backend
python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000

# Terminal 2: Launch React Frontend
cd frontend
npm install
npm run dev -- --host 127.0.0.1 --port 5173
```
Open `http://127.0.0.1:5173` in any modern web browser.

### 6. Run Automated Backend Test Suite
```bash
pytest backend/test_api.py -v
```

---

## 9. Project Deliverable Matrix

| Phase | Milestone Title | Primary Deliverable Files | Status |
| :---: | :--- | :--- | :---: |
| **0** | Repository & Toolchain Audit | `phase0_environment_and_architecture_audit.md` | **PASSED** |
| **1** | Specification & Minimal RTL | `docs/interface_spec.md`, `rtl/dma_top.v` | **PASSED** |
| **2** | FWFT FIFO & Arbiter RTL | `rtl/dma_fifo.v`, `rtl/dma_arbiter.v` | **PASSED** |
| **3** | Self-Checking Verification Suite | `tb/tb_dma_top.v`, `reports/phase3_coverage.json` | **PASSED (100% Coverage)** |
| **4** | Performance Benchmarking | `sim/run_benchmark.py`, `reports/benchmark_results.csv` | **PASSED (40 Trials)** |
| **5** | Simulation Automation & Triage | `sim/regression_runner.py`, `reports/failure_triage_report.json` | **PASSED (100% Caught)** |
| **6** | FastAPI Telemetry Backend | `backend/main.py`, `backend/test_api.py` | **PASSED (25/25 Tests)** |
| **7** | React 19 Hardware Dashboard | `frontend/src/App.tsx`, `frontend/src/index.css` | **PASSED** |
| **8** | Waveform Debugger Interface | `backend/vcd_parser.py`, `frontend/src/components/WaveformView.tsx` | **PASSED** |
| **9** | Synthesis & Timing Analysis | `syn/dma_constraints.sdc`, `syn/quartus_synth.tcl` | **PASSED** |
| **10**| Master Integration & Demo | `sim/final_integration_demo.py`, `README.md` | **PASSED** |

---

*AMD Design & Performance Verification Hardware Engineering Lab | All 11 Phases Completed & Verified.*
