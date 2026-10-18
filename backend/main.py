"""
FastAPI Backend Application for DMA Verification & Performance Analysis Lab (Phase 6)
AMD Design/Performance Verification Hardware Lab
"""

import os
import sys
from typing import List, Optional
from fastapi import FastAPI, HTTPException, Query, Path, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, PlainTextResponse, JSONResponse

# Ensure project root in sys.path
PROJ_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJ_DIR not in sys.path:
    sys.path.insert(0, PROJ_DIR)

from backend.models import (
    SimRunRequest,
    BatchRunRequest,
    SystemStatusResponse,
    SimRunSummary,
    SimJobStatus,
    HistoryItem,
    WaveformInfo,
    ArtifactMeta
)
from backend.services import (
    ToolchainService,
    SimulationService,
    ReportService,
    ArtifactService
)
from backend.vcd_parser import VCDParser

# Initialize App
app = FastAPI(
    title="DMA Verification & Performance Analysis Lab API",
    description="Cycle-Accurate Hardware Simulation, Benchmarking, and Verification Triage API",
    version="1.0.0"
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Instantiate Service
sim_service = SimulationService()

# -----------------------------------------------------------------------------
# 1. System and Toolchain Status
# -----------------------------------------------------------------------------
@app.get("/api/status", response_model=SystemStatusResponse, tags=["System"])
def get_system_status():
    """
    Returns the project environment, toolchain status (Icarus, VVP, Python, Node, Quartus),
    clock frequency, and operational readiness.
    """
    return ToolchainService.get_status()

# -----------------------------------------------------------------------------
# 2. Simulation Execution & Orchestration
# -----------------------------------------------------------------------------
@app.post("/api/sim/run", tags=["Simulation"])
def run_simulation(req: SimRunRequest):
    """
    Launches a cycle-accurate hardware simulation.
    If `async_exec=True`, returns a job tracking `run_id` immediately.
    If `async_exec=False`, executes synchronously and returns the complete simulation summary.
    """
    try:
        if req.async_exec:
            job_id = sim_service.start_asynchronous(
                suite=req.suite,
                seed=req.seed,
                bug_injection=req.bug_injection,
                timeout_sec=req.timeout_sec
            )
            return {
                "message": f"Simulation job '{job_id}' started in background.",
                "run_id": job_id,
                "status_url": f"/api/sim/status/{job_id}"
            }
        else:
            res = sim_service.run_synchronous(
                suite=req.suite,
                seed=req.seed,
                bug_injection=req.bug_injection,
                timeout_sec=req.timeout_sec
            )
            return res
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Simulation error: {str(e)}")

@app.post("/api/sim/batch", tags=["Simulation"])
def run_batch_regression(req: BatchRunRequest):
    """
    Executes a batch regression across multiple randomized seeds,
    aggregating pass/fail metrics, assertion checks, and functional coverage.
    """
    try:
        res = sim_service.run_batch(
            suite=req.suite,
            seed_count=req.seed_count,
            bug_injection=req.bug_injection,
            timeout_sec=req.timeout_sec
        )
        return res
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Batch regression failed: {str(e)}")

@app.get("/api/sim/status/{run_id}", response_model=SimJobStatus, tags=["Simulation"])
def get_simulation_status(run_id: str = Path(..., description="Unique simulation run or job ID")):
    """
    Retrieves the execution status, elapsed runtime, and completed test summary for a given run ID.
    """
    status = sim_service.get_job_status(run_id)
    if not status:
        raise HTTPException(status_code=404, detail=f"Simulation job or run '{run_id}' not found.")
    return status

@app.get("/api/sim/history", response_model=List[HistoryItem], tags=["Simulation"])
def get_simulation_history(
    limit: int = Query(default=50, ge=1, le=500, description="Max history records to return"),
    suite: Optional[str] = Query(default=None, description="Optional filter by test suite")
):
    """
    Returns chronological history of all previous simulation runs.
    """
    history = sim_service.list_history()
    if suite:
        history = [h for h in history if h.get("suite") == suite]
    return history[:limit]

@app.get("/api/sim/run/{run_id}", tags=["Simulation"])
def get_run_details(run_id: str = Path(..., description="Simulation Run ID")):
    """
    Retrieves complete JSON details of a historical simulation run.
    """
    summary = sim_service.get_run_summary(run_id)
    if not summary:
        raise HTTPException(status_code=404, detail=f"Run '{run_id}' summary not found.")
    return summary

@app.get("/api/sim/log/{run_id}", response_class=PlainTextResponse, tags=["Simulation"])
def get_run_log(run_id: str = Path(..., description="Simulation Run ID")):
    """
    Retrieves the raw standard output simulation log for a given run.
    """
    log_content = sim_service.get_run_log(run_id)
    if log_content is None:
        raise HTTPException(status_code=404, detail=f"Log file for run '{run_id}' not found.")
    return log_content

# -----------------------------------------------------------------------------
# 3. Performance Benchmarks
# -----------------------------------------------------------------------------
@app.get("/api/benchmark/summary", tags=["Performance"])
def get_benchmark_summary():
    """
    Retrieves structured performance benchmarking results across all sweeps:
    Burst scaling, payload amortization, memory latency sensitivity, and arbitration contention.
    """
    try:
        return ReportService.get_benchmark_summary()
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Benchmark dataset not found. Run benchmark runner first.")

@app.get("/api/benchmark/csv", tags=["Performance"])
def download_benchmark_csv():
    """
    Streams the raw CSV telemetry dataset with 40 trials and 16 hardware measurement attributes.
    """
    try:
        csv_path = ReportService.get_benchmark_csv_path()
        return FileResponse(
            csv_path,
            media_type="text/csv",
            filename="dma_benchmark_results.csv"
        )
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Benchmark CSV file not found.")

# -----------------------------------------------------------------------------
# 4. Failure Triage & Functional Coverage
# -----------------------------------------------------------------------------
@app.get("/api/triage/report", tags=["Verification"])
def get_failure_triage_report():
    """
    Returns the failure triage campaign dataset, documenting 100% detection rate
    across controlled fault injections (FIFO overwrite, arbiter starvation, address stride).
    """
    try:
        return ReportService.get_failure_triage_report()
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Failure triage report not found.")

@app.get("/api/coverage/summary", tags=["Verification"])
def get_coverage_summary():
    """
    Returns functional coverage bins, hits, and overall coverage percentage (100.0% / 24 bins).
    """
    try:
        return ReportService.get_coverage_summary()
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Coverage report not found.")

@app.get("/api/phase5/summary", tags=["Verification"])
def get_phase5_master_summary():
    """
    Returns consolidated Phase 5 simulation automation and triage summary report.
    """
    try:
        return ReportService.get_phase5_summary()
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Phase 5 summary report not found.")

@app.get("/api/synthesis/summary", tags=["Synthesis"])
def get_synthesis_summary():
    """
    Returns synthesis audit, timing constraints, synthesizability lint metrics,
    and target FPGA resource estimation for Cyclone V / MAX 10.
    """
    try:
        return ReportService.get_synthesis_report()
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Synthesis report not found.")

# -----------------------------------------------------------------------------
# 5. Waveform Inspection & Downloads
# -----------------------------------------------------------------------------
@app.get("/api/waveform/{run_id}", tags=["Waveforms"])
def download_waveform_vcd(run_id: str = Path(..., description="Simulation Run ID")):
    """
    Streams the actual Value Change Dump (.vcd) waveform file for signal-level inspection.
    """
    vcd_path = sim_service.get_vcd_path(run_id)
    if not vcd_path or not os.path.exists(vcd_path):
        raise HTTPException(status_code=404, detail=f"Waveform VCD for run '{run_id}' not found.")
    return FileResponse(
        vcd_path,
        media_type="application/octet-stream",
        filename=f"{run_id}_waveform.vcd"
    )

@app.get("/api/waveform/info/{run_id}", response_model=WaveformInfo, tags=["Waveforms"])
def get_waveform_info(run_id: str = Path(..., description="Simulation Run ID")):
    """
    Returns metadata for a run's waveform file (file size, existence, path).
    """
    vcd_path = sim_service.get_vcd_path(run_id)
    exists = vcd_path is not None and os.path.exists(vcd_path)
    size = os.path.getsize(vcd_path) if exists else 0
    return {
        "run_id": run_id,
        "vcd_file": os.path.basename(vcd_path) if vcd_path else "none",
        "exists": exists,
        "size_bytes": size,
        "signal_count_approx": 45 if exists else 0
    }

@app.get("/api/waveform/parsed/{run_id}", tags=["Waveforms"])
def get_parsed_waveform(
    run_id: str = Path(..., description="Simulation Run ID or 'latest'"),
    start_cycle: int = Query(default=0, ge=0, description="Starting clock cycle index"),
    count: int = Query(default=80, ge=1, le=1000, description="Number of clock cycles to sample")
):
    """
    Parses the actual IEEE 1364 VCD waveform dump from simulation,
    extracts top-level hardware signals, decodes FSM states, and returns cycle-by-cycle timeline.
    """
    vcd_path = sim_service.get_vcd_path(run_id)
    if not vcd_path or not os.path.exists(vcd_path):
        raise HTTPException(status_code=404, detail=f"Waveform VCD for run '{run_id}' not found.")

    try:
        data = VCDParser.parse_waveform(vcd_path, start_cycle=start_cycle, cycle_count=count)
        return data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to parse VCD: {str(e)}")

# -----------------------------------------------------------------------------
# 6. Approved Documentation & Artifacts
# -----------------------------------------------------------------------------
@app.get("/api/artifacts", response_model=List[ArtifactMeta], tags=["Artifacts"])
def list_artifacts():
    """
    Lists all approved engineering documents, verification plans, and performance reports.
    """
    return ArtifactService.list_artifacts()

@app.get("/api/artifacts/{artifact_name}", response_class=PlainTextResponse, tags=["Artifacts"])
def get_artifact(artifact_name: str = Path(..., description="Name of markdown or report file")):
    """
    Retrieves the raw text content of an approved engineering artifact.
    Guarded against path traversal.
    """
    try:
        return ArtifactService.get_artifact_content(artifact_name)
    except FileNotFoundError as fe:
        raise HTTPException(status_code=404, detail=str(fe))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend.main:app", host="127.0.0.1", port=8000, reload=False)
