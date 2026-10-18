#!/usr/bin/env python3
"""
Performance Benchmarking Automation Engine for DMA Verification Lab (Phase 4)
Compiles and runs tb_dma_benchmark.v, parses cycle-accurate hardware measurements,
calculates throughput, bus utilization, latency degradation, and arbitration fairness,
and exports standardized CSV and JSON benchmark datasets.
"""

import os
import sys
import subprocess
import json
import time
import csv

def find_tool(tool_name):
    candidates = [
        tool_name,
        os.path.expanduser(f"~\\iverilog\\app\\bin\\{tool_name}.exe"),
        f"C:\\iverilog\\bin\\{tool_name}.exe"
    ]
    for c in candidates:
        if os.path.isabs(c) and os.path.exists(c):
            return c
        import shutil
        found = shutil.which(c)
        if found:
            return found
    return tool_name

def run_benchmark():
    proj_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    rtl_dir = os.path.join(proj_dir, "rtl")
    tb_dir = os.path.join(proj_dir, "tb")
    sim_dir = os.path.join(proj_dir, "sim")
    reports_dir = os.path.join(proj_dir, "reports")

    os.makedirs(sim_dir, exist_ok=True)
    os.makedirs(reports_dir, exist_ok=True)

    iverilog_bin = find_tool("iverilog")
    vvp_bin = find_tool("vvp")

    sources = [
        os.path.join(rtl_dir, "dma_fifo.v"),
        os.path.join(rtl_dir, "dma_arbiter.v"),
        os.path.join(rtl_dir, "dma_reg_file.v"),
        os.path.join(rtl_dir, "dma_controller.v"),
        os.path.join(rtl_dir, "dma_top.v"),
        os.path.join(tb_dir, "mem_model.v"),
        os.path.join(tb_dir, "tb_dma_benchmark.v")
    ]
    vvp_out = os.path.join(sim_dir, "dma_benchmark.vvp")
    log_out = os.path.join(sim_dir, "dma_benchmark.log")
    csv_out = os.path.join(reports_dir, "benchmark_results.csv")
    json_out = os.path.join(reports_dir, "benchmark_summary.json")

    print("=======================================================")
    print("      DMA Performance Benchmarking Automation (Phase 4)")
    print("=======================================================")
    print(f"[*] Compiler : {iverilog_bin}")
    print(f"[*] Simulator: {vvp_bin}")

    # 1. Compile
    compile_cmd = [iverilog_bin, "-g2001", "-Wall", "-o", vvp_out] + sources
    print("\n[1/3] Compiling Benchmarking Harness...")
    t0 = time.time()
    res_comp = subprocess.run(compile_cmd, capture_output=True, text=True, cwd=sim_dir)
    if res_comp.returncode != 0:
        print("[-] Compilation FAILED:\n", res_comp.stderr)
        sys.exit(1)
    print(f"[+] Compilation SUCCESS in {time.time()-t0:.2f}s")

    # 2. Simulate
    sim_cmd = [vvp_bin, vvp_out]
    print("\n[2/3] Executing Parameterized Sweeps with VVP...")
    t1 = time.time()
    res_sim = subprocess.run(sim_cmd, capture_output=True, text=True, cwd=sim_dir)
    full_output = res_sim.stdout + ("\n" + res_sim.stderr if res_sim.stderr else "")
    with open(log_out, "w", encoding="utf-8") as f:
        f.write(full_output)
    print(f"[+] Simulation completed in {time.time()-t1:.2f}s. Raw log saved to: {log_out}")

    # 3. Parse Data Lines
    # Format: [BENCH_DATA] exp_id,sweep,xfer_bytes,burst_beats,mem_lat,policy,contention,cycles,tp_b_cyc,tp_mb_s,bus_util,max_fifo,wait0,wait1,grant0,grant1
    csv_rows = []
    records = []

    for line in full_output.splitlines():
        if "[BENCH_DATA]" in line:
            raw_data = line.split("[BENCH_DATA]")[1].strip()
            parts = [p.strip() for p in raw_data.split(",")]
            if len(parts) == 16:
                rec = {
                    "exp_id": int(parts[0]),
                    "sweep": parts[1],
                    "xfer_bytes": int(parts[2]),
                    "burst_beats": int(parts[3]),
                    "mem_latency": int(parts[4]),
                    "policy": "RoundRobin" if parts[5] == "1" else "FixedPriority",
                    "contention": "Heavy" if parts[6] == "2" else ("Light" if parts[6] == "1" else "None"),
                    "cycles": int(parts[7]),
                    "throughput_bytes_per_cycle": float(parts[8]),
                    "throughput_mb_s": float(parts[9]),
                    "bus_utilization_pct": float(parts[10]),
                    "max_fifo_occupancy": int(parts[11]),
                    "wait_cycles_req0": int(parts[12]),
                    "wait_cycles_req1": int(parts[13]),
                    "grants_req0": int(parts[14]),
                    "grants_req1": int(parts[15])
                }
                records.append(rec)
                csv_rows.append(rec)

    # Export CSV
    fieldnames = [
        "exp_id", "sweep", "xfer_bytes", "burst_beats", "mem_latency", "policy",
        "contention", "cycles", "throughput_bytes_per_cycle", "throughput_mb_s",
        "bus_utilization_pct", "max_fifo_occupancy", "wait_cycles_req0", "wait_cycles_req1",
        "grants_req0", "grants_req1"
    ]
    with open(csv_out, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(csv_rows)
    print(f"\n[3/3] Exporting Datasets...")
    print(f"[+] Flat CSV dataset written to: {csv_out} ({len(records)} trials)")

    # Structure JSON by Sweep Categories
    burst_scale = [r for r in records if r["sweep"] == "BURST_SCALE"]
    len_scale_b1 = [r for r in records if r["sweep"] == "LEN_SCALE_B1"]
    len_scale_b4 = [r for r in records if r["sweep"] == "LEN_SCALE_B4"]
    len_scale_b8 = [r for r in records if r["sweep"] == "LEN_SCALE_B8"]
    mem_lat_b1 = [r for r in records if r["sweep"] == "MEM_LAT_B1"]
    mem_lat_b4 = [r for r in records if r["sweep"] == "MEM_LAT_B4"]
    mem_lat_b8 = [r for r in records if r["sweep"] == "MEM_LAT_B8"]
    arb_contention = [r for r in records if r["sweep"] == "ARB_CONTENTION"]

    summary_json = {
        "metadata": {
            "title": "DMA Subsystem Cycle-Accurate Performance Benchmark Suite",
            "phase": 4,
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "simulator": "Icarus Verilog v12",
            "clock_frequency_mhz": 100.0,
            "clock_period_ns": 10.0,
            "total_trials": len(records)
        },
        "metric_definitions": {
            "cycles": "Clock cycles elapsed from START pulse assertion to DONE status flag latch.",
            "throughput_bytes_per_cycle": "xfer_bytes / cycles",
            "throughput_mb_s": "throughput_bytes_per_cycle * 100.0 (at 100 MHz clock)",
            "bus_utilization_pct": "Active memory request-ready handshake cycles divided by total cycles * 100%",
            "contention_penalty_factor": "Latency under contention divided by solo latency"
        },
        "sweeps": {
            "burst_size_scaling": burst_scale,
            "transfer_length_scaling": {
                "burst_1": len_scale_b1,
                "burst_4": len_scale_b4,
                "burst_8": len_scale_b8
            },
            "memory_latency_sensitivity": {
                "burst_1": mem_lat_b1,
                "burst_4": mem_lat_b4,
                "burst_8": mem_lat_b8
            },
            "arbitration_and_contention": arb_contention
        }
    }

    with open(json_out, "w", encoding="utf-8") as f:
        json.dump(summary_json, f, indent=2)
    print(f"[+] Structured JSON dataset written to: {json_out}")

    # Print Formatted Executive Summary Table
    print("\n" + "="*80)
    print("                    EXECUTIVE BENCHMARK SUMMARY")
    print("="*80)
    print(f"{'Sweep':<16} | {'Burst':<5} | {'Bytes':<5} | {'Lat':<3} | {'Policy':<8} | {'Cycles':<6} | {'MB/s':<6} | {'BusUtil':<7}")
    print("-" * 80)
    for r in burst_scale:
        print(f"{r['sweep']:<16} | {r['burst_beats']:<5} | {r['xfer_bytes']:<5} | {r['mem_latency']:<3} | {r['policy'][:8]:<8} | {r['cycles']:<6} | {r['throughput_mb_s']:<6.1f} | {r['bus_utilization_pct']:<7.1f}%")
    print("-" * 80)
    for r in arb_contention:
        print(f"{'ARB_' + r['contention']:<16} | {r['burst_beats']:<5} | {r['xfer_bytes']:<5} | {r['mem_latency']:<3} | {r['policy'][:8]:<8} | {r['cycles']:<6} | {r['throughput_mb_s']:<6.1f} | {r['bus_utilization_pct']:<7.1f}%")
    print("="*80 + "\n")

    return True

if __name__ == "__main__":
    success = run_benchmark()
    if not success:
        sys.exit(1)
