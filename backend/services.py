"""
Business Logic & Simulation Management Services for DMA Lab FastAPI Backend
"""

import os
import sys
import subprocess
import json
import time
import shutil
import threading
from typing import Dict, Any, List, Optional

# Ensure project root is in sys.path so we can import sim.regression_runner
PROJ_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJ_DIR not in sys.path:
    sys.path.insert(0, PROJ_DIR)

from sim.regression_runner import SimulationRunner, find_tool

class ToolchainService:
    @staticmethod
    def get_status() -> Dict[str, Any]:
        tools = {}

        # 1. Icarus Verilog Compiler
        iverilog_path = find_tool("iverilog")
        iv_ver = None
        iv_ok = False
        if os.path.exists(iverilog_path) or shutil.which(iverilog_path):
            try:
                res = subprocess.run([iverilog_path, "-V"], capture_output=True, text=True, timeout=5)
                first_line = res.stdout.splitlines()[0] if res.stdout else ""
                iv_ver = first_line.strip()
                iv_ok = True
            except Exception:
                pass
        tools["iverilog"] = {
            "tool": "Icarus Verilog",
            "path": iverilog_path,
            "version": iv_ver or "Unknown",
            "available": iv_ok
        }

        # 2. VVP Simulator Engine
        vvp_path = find_tool("vvp")
        vvp_ver = None
        vvp_ok = False
        if os.path.exists(vvp_path) or shutil.which(vvp_path):
            try:
                res = subprocess.run([vvp_path, "-V"], capture_output=True, text=True, timeout=5)
                first_line = res.stdout.splitlines()[0] if res.stdout else ""
                vvp_ver = first_line.strip()
                vvp_ok = True
            except Exception:
                pass
        tools["vvp"] = {
            "tool": "Icarus VVP Engine",
            "path": vvp_path,
            "version": vvp_ver or "Unknown",
            "available": vvp_ok
        }

        # 3. Python Runtime
        py_ver = sys.version.split()[0]
        tools["python"] = {
            "tool": "Python",
            "path": sys.executable,
            "version": py_ver,
            "available": True
        }

        # 4. Node.js
        node_path = shutil.which("node")
        node_ver = None
        node_ok = False
        if node_path:
            try:
                res = subprocess.run([node_path, "-v"], capture_output=True, text=True, timeout=5)
                node_ver = res.stdout.strip()
                node_ok = True
            except Exception:
                pass
        tools["node"] = {
            "tool": "Node.js",
            "path": node_path or "Not Found",
            "version": node_ver or "None",
            "available": node_ok
        }

        # 5. Quartus (Optional FPGA synthesis tool)
        quartus_path = shutil.which("quartus_sh") or shutil.which("quartus_map")
        tools["quartus"] = {
            "tool": "Intel Quartus Prime",
            "path": quartus_path or "Not installed in PATH",
            "version": "Available via standalone script" if quartus_path else "Not Detected",
            "available": quartus_path is not None
        }

        ready = iv_ok and vvp_ok

        return {
            "project_name": "DMA Verification & Performance Analysis Lab",
            "phase": 6,
            "clock_frequency_mhz": 100.0,
            "os": sys.platform,
            "python_version": py_ver,
            "tools": tools,
            "ready": ready
        }

class SimulationService:
    def __init__(self):
        self.runner = SimulationRunner(proj_dir=PROJ_DIR)
        self.jobs: Dict[str, Dict[str, Any]] = {}
        self._lock = threading.Lock()

    def run_synchronous(self, suite="top", seed=None, bug_injection="none", timeout_sec=60) -> Dict[str, Any]:
        """
        Executes a simulation synchronously and returns parsed results.
        """
        res = self.runner.execute_single_run(
            suite=suite,
            seed=seed,
            bug_injection=bug_injection,
            timeout_sec=timeout_sec
        )
        return res

    def start_asynchronous(self, suite="top", seed=None, bug_injection="none", timeout_sec=60) -> str:
        """
        Spawns a background thread to execute the simulation, returning a tracking run_id.
        """
        if seed is None:
            seed = int(time.time() * 1000) & 0x7FFFFFFF

        # Validate config first before launching thread
        self.runner.validate_config(suite, seed, bug_injection, timeout_sec)

        import uuid
        run_id = f"job_{time.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"

        with self._lock:
            self.jobs[run_id] = {
                "run_id": run_id,
                "suite": suite,
                "status": "RUNNING",
                "start_time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "start_epoch": time.time(),
                "elapsed_sec": 0.0,
                "result": None,
                "error": None
            }

        def worker():
            try:
                res = self.runner.execute_single_run(
                    suite=suite,
                    seed=seed,
                    bug_injection=bug_injection,
                    timeout_sec=timeout_sec
                )
                with self._lock:
                    if run_id in self.jobs:
                        self.jobs[run_id]["status"] = "COMPLETED" if res["verdict"] == "PASSED" else "FAILED"
                        self.jobs[run_id]["elapsed_sec"] = time.time() - self.jobs[run_id]["start_epoch"]
                        self.jobs[run_id]["result"] = res
            except Exception as e:
                with self._lock:
                    if run_id in self.jobs:
                        self.jobs[run_id]["status"] = "FAILED"
                        self.jobs[run_id]["elapsed_sec"] = time.time() - self.jobs[run_id]["start_epoch"]
                        self.jobs[run_id]["error"] = str(e)

        thread = threading.Thread(target=worker, daemon=True)
        thread.start()

        return run_id

    def get_job_status(self, run_id: str) -> Optional[Dict[str, Any]]:
        with self._lock:
            if run_id in self.jobs:
                job = self.jobs[run_id].copy()
                if job["status"] == "RUNNING":
                    job["elapsed_sec"] = time.time() - job["start_epoch"]
                return job

        # If not in active memory, check if exists in runs/
        runs_dir = self.runner.runs_dir
        for folder in os.listdir(runs_dir):
            if folder == run_id or folder.endswith(run_id):
                sum_path = os.path.join(runs_dir, folder, "summary.json")
                if os.path.exists(sum_path):
                    with open(sum_path, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    return {
                        "run_id": folder,
                        "suite": data.get("suite", "unknown"),
                        "status": "COMPLETED" if data.get("verdict") == "PASSED" else "FAILED",
                        "start_time": "Persisted Run",
                        "elapsed_sec": data.get("sim_time_sec", 0.0),
                        "result": data,
                        "error": None
                    }
        return None

    def get_run_summary(self, run_id: str) -> Optional[Dict[str, Any]]:
        runs_dir = self.runner.runs_dir
        for folder in os.listdir(runs_dir):
            if folder == run_id:
                sum_path = os.path.join(runs_dir, folder, "summary.json")
                if os.path.exists(sum_path):
                    with open(sum_path, "r", encoding="utf-8") as f:
                        return json.load(f)
        return None

    def get_run_log(self, run_id: str) -> Optional[str]:
        runs_dir = self.runner.runs_dir
        for folder in os.listdir(runs_dir):
            if folder == run_id:
                log_path = os.path.join(runs_dir, folder, "sim.log")
                if os.path.exists(log_path):
                    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
                        return f.read()
        return None

    def get_vcd_path(self, run_id: str) -> Optional[str]:
        runs_dir = self.runner.runs_dir
        if not os.path.exists(runs_dir):
            return None

        # Check for latest keyword
        if run_id == "latest":
            folders = sorted(os.listdir(runs_dir), reverse=True)
            # Prioritize top-level DMA runs
            for folder in folders:
                vcd_path = os.path.join(runs_dir, folder, "dma_tb.vcd")
                if os.path.exists(vcd_path):
                    return vcd_path
            # Fallback to any sub-block run VCD
            for folder in folders:
                for vname in ["fifo_tb.vcd", "arbiter_tb.vcd"]:
                    vcd_path = os.path.join(runs_dir, folder, vname)
                    if os.path.exists(vcd_path):
                        return vcd_path

        # Check direct or suffix match
        for folder in os.listdir(runs_dir):
            if folder == run_id or folder.endswith(run_id):
                for vname in ["dma_tb.vcd", "fifo_tb.vcd", "arbiter_tb.vcd"]:
                    vcd_path = os.path.join(runs_dir, folder, vname)
                    if os.path.exists(vcd_path):
                        return vcd_path

        # Also check sim/ directory
        sim_vcd = os.path.join(self.runner.sim_dir, f"{run_id}.vcd")
        if os.path.exists(sim_vcd):
            return sim_vcd
        default_tb = os.path.join(self.runner.sim_dir, "dma_tb.vcd")
        if run_id == "latest" and os.path.exists(default_tb):
            return default_tb
        return None

    def list_history(self) -> List[Dict[str, Any]]:
        history_path = os.path.join(self.runner.reports_dir, "regression_history.json")
        if os.path.exists(history_path):
            try:
                with open(history_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    return data
            except Exception:
                pass

        # Fallback to inspecting runs/ directory
        items = []
        runs_dir = self.runner.runs_dir
        if os.path.exists(runs_dir):
            for folder in sorted(os.listdir(runs_dir), reverse=True):
                sum_path = os.path.join(runs_dir, folder, "summary.json")
                if os.path.exists(sum_path):
                    try:
                        with open(sum_path, "r", encoding="utf-8") as f:
                            d = json.load(f)
                            items.append({
                                "run_id": d.get("run_id", folder),
                                "suite": d.get("suite", "unknown"),
                                "seed": d.get("seed", 0),
                                "bug_injection": d.get("bug_injection", "none"),
                                "verdict": d.get("verdict", "UNKNOWN"),
                                "failure_category": d.get("failure_category", "NONE"),
                                "sim_time_sec": d.get("sim_time_sec", 0.0),
                                "total_tests": d.get("total_tests", 0),
                                "passed_tests": d.get("passed_tests", 0),
                                "failed_tests": d.get("failed_tests", 0),
                                "assertion_violation_count": d.get("assertion_violation_count", 0),
                                "scoreboard_mismatch_count": d.get("scoreboard_mismatch_count", 0)
                            })
                    except Exception:
                        pass
        return items

    def run_batch(self, suite="top", seed_count=5, bug_injection="none", timeout_sec=60) -> Dict[str, Any]:
        return self.runner.run_regression(
            suite=suite,
            count=seed_count,
            bug_injection=bug_injection,
            timeout_sec=timeout_sec
        )

class ReportService:
    @staticmethod
    def get_benchmark_summary() -> Dict[str, Any]:
        p = os.path.join(PROJ_DIR, "reports", "benchmark_summary.json")
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                return json.load(f)
        raise FileNotFoundError("benchmark_summary.json not found")

    @staticmethod
    def get_benchmark_csv_path() -> str:
        p = os.path.join(PROJ_DIR, "reports", "benchmark_results.csv")
        if os.path.exists(p):
            return p
        raise FileNotFoundError("benchmark_results.csv not found")

    @staticmethod
    def get_failure_triage_report() -> Dict[str, Any]:
        p = os.path.join(PROJ_DIR, "reports", "failure_triage_report.json")
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                return json.load(f)
        raise FileNotFoundError("failure_triage_report.json not found")

    @staticmethod
    def get_coverage_summary() -> Dict[str, Any]:
        p = os.path.join(PROJ_DIR, "reports", "phase3_coverage.json")
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                return json.load(f)
        raise FileNotFoundError("phase3_coverage.json not found")

    @staticmethod
    def get_phase5_summary() -> Dict[str, Any]:
        p = os.path.join(PROJ_DIR, "reports", "phase5_summary.json")
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                return json.load(f)
        raise FileNotFoundError("phase5_summary.json not found")

    @staticmethod
    def get_synthesis_report() -> Dict[str, Any]:
        p = os.path.join(PROJ_DIR, "reports", "synthesis_report.json")
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                return json.load(f)
        raise FileNotFoundError("synthesis_report.json not found")

class ArtifactService:
    SAFE_DIRS = [
        os.path.join(PROJ_DIR, "docs"),
        os.path.join(PROJ_DIR, "reports")
    ]

    @classmethod
    def list_artifacts(cls) -> List[Dict[str, Any]]:
        artifacts = []
        for d in cls.SAFE_DIRS:
            if os.path.exists(d):
                for f in os.listdir(d):
                    if f.endswith(".md") or f.endswith(".json") or f.endswith(".csv"):
                        fp = os.path.join(d, f)
                        st = os.stat(fp)
                        artifacts.append({
                            "name": f,
                            "path": os.path.relpath(fp, PROJ_DIR).replace("\\", "/"),
                            "size_bytes": st.st_size,
                            "last_modified": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(st.st_mtime))
                        })
        return artifacts

    @classmethod
    def get_artifact_content(cls, artifact_name: str) -> str:
        # Sanitize against path traversal attacks (e.g. ../../)
        clean_name = os.path.basename(artifact_name)
        for d in cls.SAFE_DIRS:
            candidate = os.path.join(d, clean_name)
            if os.path.exists(candidate) and os.path.isfile(candidate):
                with open(candidate, "r", encoding="utf-8", errors="replace") as f:
                    return f.read()
        raise FileNotFoundError(f"Artifact '{artifact_name}' not found in approved project directories.")
