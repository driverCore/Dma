#!/usr/bin/env python3
"""
Simulation Automation Runner for DMA Verification & Performance Analysis Lab (Phase 3)
Compiles synthesizable RTL (dma_top, dma_controller, dma_reg_file, dma_fifo, dma_arbiter)
and testbenches with Icarus Verilog, executes simulations with VVP, generates VCD waveforms,
parses test outputs, captures functional coverage metrics, and produces structured JSON reports.
"""

import os
import sys
import subprocess
import json
import time
import re
import argparse

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

def parse_coverage_from_log(log_text):
    cov_data = {
        "total_bins": 24,
        "covered_bins": 0,
        "coverage_percentage": 0.0,
        "categories": {}
    }
    m_tot = re.search(r"Total Coverage Bins Defined\s*:\s*(\d+)", log_text)
    m_hit = re.search(r"Total Coverage Bins Hit\s*:\s*(\d+)", log_text)
    m_pct = re.search(r"Overall Coverage Percentage\s*:\s*([\d\.]+)%", log_text)

    if m_tot: cov_data["total_bins"] = int(m_tot.group(1))
    if m_hit: cov_data["covered_bins"] = int(m_hit.group(1))
    if m_pct: cov_data["coverage_percentage"] = float(m_pct.group(1))

    # Parse individual bin counts
    bin_patterns = [
        ("1-Beat", r"1-Beat:\s*(\d+)"),
        ("2-Beat", r"2-Beat:\s*(\d+)"),
        ("4-Beat", r"4-Beat:\s*(\d+)"),
        ("8-Beat", r"8-Beat:\s*(\d+)"),
        ("SingleWord", r"Single:\s*(\d+)"),
        ("Short", r"Short:\s*(\d+)"),
        ("Medium", r"Med:\s*(\d+)"),
        ("Long", r"Long:\s*(\d+)"),
        ("Remainder", r"Rem:\s*(\d+)"),
        ("ZeroLen", r"ZeroLen:\s*(\d+)"),
        ("UnalignLen", r"UnalignLen:\s*(\d+)"),
        ("UnalignSrc", r"UnalignSrc:\s*(\d+)"),
        ("UnalignDst", r"UnalignDst:\s*(\d+)"),
        ("BusRdErr", r"BusRdErr:\s*(\d+)"),
        ("BusWrErr", r"BusWrErr:\s*(\d+)"),
        ("Timeout", r"Timeout:\s*(\d+)"),
        ("SWAbort", r"SWAbort:\s*(\d+)"),
        ("SoftReset", r"SoftReset:\s*(\d+)"),
        ("Latency0", r"0-Cycle:\s*(\d+)"),
        ("Latency1", r"1-Cycle:\s*(\d+)"),
        ("LatencyMulti", r"Multi-Cycle:\s*(\d+)"),
        ("FixedPriority", r"FixedPri:\s*(\d+)"),
        ("RoundRobin", r"RoundRobin:\s*(\d+)"),
        ("BurstLock", r"BurstLock:\s*(\d+)")
    ]

    for name, pat in bin_patterns:
        m = re.search(pat, log_text)
        cov_data["categories"][name] = int(m.group(1)) if m else 0

    return cov_data

def run_test_suite(suite_name="top", seed=None, verbose=False):
    proj_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    rtl_dir = os.path.join(proj_dir, "rtl")
    tb_dir = os.path.join(proj_dir, "tb")
    sim_dir = os.path.join(proj_dir, "sim")
    reports_dir = os.path.join(proj_dir, "reports")

    os.makedirs(sim_dir, exist_ok=True)
    os.makedirs(reports_dir, exist_ok=True)

    iverilog_bin = find_tool("iverilog")
    vvp_bin = find_tool("vvp")

    print(f"[*] Project root: {proj_dir}")
    print(f"[*] Icarus Verilog compiler: {iverilog_bin}")
    print(f"[*] VVP simulator engine:   {vvp_bin}")

    if suite_name == "fifo":
        sources = [
            os.path.join(rtl_dir, "dma_fifo.v"),
            os.path.join(tb_dir, "tb_dma_fifo.v")
        ]
        vvp_out = os.path.join(sim_dir, "fifo_tb.vvp")
        log_out = os.path.join(sim_dir, "fifo_sim.log")
        json_report_path = os.path.join(reports_dir, "phase2_fifo_summary.json")
        desc = "FIFO Unit Verification"
        phase = 2

    elif suite_name == "arbiter":
        sources = [
            os.path.join(rtl_dir, "dma_arbiter.v"),
            os.path.join(tb_dir, "tb_dma_arbiter.v")
        ]
        vvp_out = os.path.join(sim_dir, "arbiter_tb.vvp")
        log_out = os.path.join(sim_dir, "arbiter_sim.log")
        json_report_path = os.path.join(reports_dir, "phase2_arbiter_summary.json")
        desc = "Arbiter Unit Verification"
        phase = 2

    else: # "top"
        sources = [
            os.path.join(rtl_dir, "dma_fifo.v"),
            os.path.join(rtl_dir, "dma_arbiter.v"),
            os.path.join(rtl_dir, "dma_reg_file.v"),
            os.path.join(rtl_dir, "dma_controller.v"),
            os.path.join(rtl_dir, "dma_top.v"),
            os.path.join(tb_dir, "mem_model.v"),
            os.path.join(tb_dir, "tb_dma_top.v")
        ]
        vvp_out = os.path.join(sim_dir, "dma_tb.vvp")
        log_out = os.path.join(sim_dir, "dma_sim.log")
        json_report_path = os.path.join(reports_dir, "phase3_summary.json")
        desc = "DMA Subsystem Phase 3 Verification Infrastructure"
        phase = 3

    for src in sources:
        if not os.path.exists(src):
            print(f"[!] Error: Source file not found: {src}")
            sys.exit(1)

    # 1. Compile
    compile_cmd = [iverilog_bin, "-g2001", "-Wall", "-o", vvp_out] + sources
    print(f"\n[1/3] Compiling {desc}...")
    print(f"      Command: {' '.join(compile_cmd)}")

    t0 = time.time()
    res_compile = subprocess.run(compile_cmd, capture_output=True, text=True, cwd=sim_dir)
    compile_time = time.time() - t0

    if res_compile.returncode != 0:
        print(f"[-] Compilation FAILED with code {res_compile.returncode}")
        print("Compile stderr:\n", res_compile.stderr)
        sys.exit(res_compile.returncode)
    else:
        print(f"[+] Compilation SUCCESS in {compile_time:.2f}s")
        if res_compile.stderr.strip():
            print("Compile warnings:\n", res_compile.stderr.strip())

    # 2. Simulate
    sim_cmd = [vvp_bin, vvp_out]
    if seed is not None:
        sim_cmd.append(f"+seed={seed}")

    print(f"\n[2/3] Executing simulation with VVP...")
    print(f"      Command: {' '.join(sim_cmd)}")

    t1 = time.time()
    res_sim = subprocess.run(sim_cmd, capture_output=True, text=True, cwd=sim_dir)
    sim_time = time.time() - t1

    full_output = res_sim.stdout + ("\n" + res_sim.stderr if res_sim.stderr else "")

    with open(log_out, "w", encoding="utf-8") as f:
        f.write(full_output)

    print(f"[+] Simulation finished in {sim_time:.2f}s. Log written to: {log_out}")
    print("\n--- Simulation Output Highlights ---")
    if verbose:
        print(full_output.strip())
    else:
        lines = full_output.splitlines()
        # Print relevant highlights (results, summary, coverage)
        highlight_lines = [l for l in lines if any(k in l for k in [
            ">>> TEST_START", ">>> TEST_RESULT", "SCOREBOARD", "ASSERTION",
            "FUNCTIONAL COVERAGE", "Total Coverage", "Overall Coverage",
            "VERIFICATION SUMMARY REPORT", "Total Tests", "REGRESSION STATUS"
        ])]
        print("\n".join(highlight_lines))
    print("------------------------------------\n")

    # 3. Parse and Report
    tests = []
    current_test = None

    for line in full_output.splitlines():
        if ">>> TEST_START:" in line:
            name = line.split(">>> TEST_START:")[1].strip()
            current_test = {"name": name, "status": "UNKNOWN", "details": []}
            tests.append(current_test)
        elif ">>> TEST_RESULT:" in line:
            res_str = line.split(">>> TEST_RESULT:")[1].strip()
            if current_test:
                if "PASS" in res_str:
                    current_test["status"] = "PASSED"
                elif "FAIL" in res_str:
                    current_test["status"] = "FAILED"
                current_test["result_raw"] = res_str
        elif current_test:
            if line.startswith("[+]") or line.startswith("[-]"):
                current_test["details"].append(line.strip())

    total_tests = len(tests)
    passed_tests = sum(1 for t in tests if t["status"] == "PASSED")
    failed_tests = sum(1 for t in tests if t["status"] == "FAILED")

    # Check assertion failures in log
    assertion_fails = len(re.findall(r"ASSERTION VIOLATION", full_output))

    regression_pass = (failed_tests == 0 and total_tests > 0 and res_sim.returncode == 0 and assertion_fails == 0)

    report_data = {
        "suite": suite_name,
        "description": desc,
        "phase": phase,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "simulator": "Icarus Verilog v12",
        "seed_used": seed,
        "compile_status": "SUCCESS",
        "simulation_status": "SUCCESS" if res_sim.returncode == 0 else "FAILED",
        "regression_verdict": "PASSED" if regression_pass else "FAILED",
        "total_tests": total_tests,
        "passed_tests": passed_tests,
        "failed_tests": failed_tests,
        "assertion_violations": assertion_fails,
        "tests": tests,
        "log_file": log_out
    }

    if suite_name == "top":
        cov_info = parse_coverage_from_log(full_output)
        report_data["functional_coverage"] = cov_info

        cov_file_path = os.path.join(reports_dir, "phase3_coverage.json")
        with open(cov_file_path, "w", encoding="utf-8") as f:
            json.dump(cov_info, f, indent=2)
        print(f"[+] Coverage metrics written to: {cov_file_path}")

    with open(json_report_path, "w", encoding="utf-8") as f:
        json.dump(report_data, f, indent=2)

    print(f"[+] Structured summary report written to: {json_report_path}")
    print(f" Summary: {passed_tests}/{total_tests} Tests Passed | Assertions: {assertion_fails} Fails | Regression: {'PASSED' if regression_pass else 'FAILED'}\n")

    return regression_pass

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="DMA Verification Regression Runner")
    parser.add_argument("--top", action="store_true", help="Run Top Subsystem Verification (Default)")
    parser.add_argument("--fifo", action="store_true", help="Run FIFO Unit Verification")
    parser.add_argument("--arbiter", action="store_true", help="Run Arbiter Unit Verification")
    parser.add_argument("--all", action="store_true", help="Run All Test Suites (FIFO, Arbiter, Top)")
    parser.add_argument("--seed", type=int, default=None, help="Random Seed for Constrained-Random Tests")
    parser.add_argument("--verbose", action="store_true", help="Print Complete Raw Simulation Output")

    args = parser.parse_args()

    overall_pass = True

    if args.all:
        print("=== RUNNING FULL REGRESSION (ALL SUITES) ===")
        p_fifo = run_test_suite("fifo", verbose=args.verbose)
        p_arb  = run_test_suite("arbiter", verbose=args.verbose)
        p_top  = run_test_suite("top", seed=args.seed, verbose=args.verbose)
        overall_pass = p_fifo and p_arb and p_top
    elif args.fifo:
        overall_pass = run_test_suite("fifo", verbose=args.verbose)
    elif args.arbiter:
        overall_pass = run_test_suite("arbiter", verbose=args.verbose)
    else:
        overall_pass = run_test_suite("top", seed=args.seed, verbose=args.verbose)

    if not overall_pass:
        sys.exit(1)
