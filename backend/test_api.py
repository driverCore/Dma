"""
Automated Pytest API Test Suite for DMA Verification & Performance Lab (Phase 6)
Validates all endpoints, input validation boundaries, error handling,
simulation execution, and telemetry retrieval.
"""

import os
import sys
import pytest
from fastapi.testclient import TestClient

# Ensure project root in sys.path
PROJ_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJ_DIR not in sys.path:
    sys.path.insert(0, PROJ_DIR)

from backend.main import app

client = TestClient(app)

# -----------------------------------------------------------------------------
# 1. System Status Tests
# -----------------------------------------------------------------------------
def test_get_system_status():
    response = client.get("/api/status")
    assert response.status_code == 200
    data = response.json()
    assert data["project_name"] == "DMA Verification & Performance Analysis Lab"
    assert data["phase"] == 6
    assert data["clock_frequency_mhz"] == 100.0
    assert "tools" in data
    assert "iverilog" in data["tools"]
    assert "vvp" in data["tools"]
    assert data["tools"]["iverilog"]["available"] is True
    assert data["tools"]["vvp"]["available"] is True
    assert data["ready"] is True

# -----------------------------------------------------------------------------
# 2. Input Validation Tests (Negative Testing)
# -----------------------------------------------------------------------------
def test_sim_run_invalid_suite():
    # Invalid suite should be rejected by Pydantic validation (422)
    response = client.post("/api/sim/run", json={"suite": "invalid_engine_name"})
    assert response.status_code == 422

def test_sim_run_invalid_bug_injection():
    response = client.post("/api/sim/run", json={"suite": "top", "bug_injection": "unsupported_bug"})
    assert response.status_code == 422

def test_sim_run_invalid_timeout():
    # Negative timeout
    response = client.post("/api/sim/run", json={"suite": "top", "timeout_sec": -5})
    assert response.status_code == 422

def test_sim_run_excessive_timeout():
    # Timeout exceeding max limit 300
    response = client.post("/api/sim/run", json={"suite": "top", "timeout_sec": 9999})
    assert response.status_code == 422

def test_batch_run_invalid_seed_count():
    response = client.post("/api/sim/batch", json={"suite": "top", "seed_count": 0})
    assert response.status_code == 422

def test_nonexistent_run_status():
    response = client.get("/api/sim/status/non_existent_run_id_12345")
    assert response.status_code == 404

def test_nonexistent_run_log():
    response = client.get("/api/sim/log/non_existent_run_id_12345")
    assert response.status_code == 404

def test_nonexistent_run_details():
    response = client.get("/api/sim/run/non_existent_run_id_12345")
    assert response.status_code == 404

def test_artifact_path_traversal_protection():
    response = client.get("/api/artifacts/../../etc/passwd")
    assert response.status_code in [404, 400]

# -----------------------------------------------------------------------------
# 3. Simulation Execution Tests (Positive & Async)
# -----------------------------------------------------------------------------
def test_sim_run_synchronous_fifo():
    # Execute fast FIFO unit verification through API
    payload = {
        "suite": "fifo",
        "seed": 12345,
        "bug_injection": "none",
        "timeout_sec": 30,
        "async_exec": False
    }
    response = client.post("/api/sim/run", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["suite"] == "fifo"
    assert data["verdict"] == "PASSED"
    assert data["total_tests"] == 10
    assert data["passed_tests"] == 10
    assert data["failed_tests"] == 0
    assert data["vcd_generated"] is True

def test_sim_run_synchronous_arbiter():
    payload = {
        "suite": "arbiter",
        "seed": 54321,
        "bug_injection": "none",
        "timeout_sec": 30,
        "async_exec": False
    }
    response = client.post("/api/sim/run", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["suite"] == "arbiter"
    assert data["verdict"] == "PASSED"
    assert data["total_tests"] == 7
    assert data["passed_tests"] == 7

def test_sim_run_asynchronous_polling():
    payload = {
        "suite": "fifo",
        "seed": 99999,
        "bug_injection": "none",
        "timeout_sec": 30,
        "async_exec": True
    }
    response = client.post("/api/sim/run", json=payload)
    assert response.status_code == 200
    init_data = response.json()
    assert "run_id" in init_data
    run_id = init_data["run_id"]

    import time
    # Poll for completion
    completed = False
    for _ in range(30):
        st_resp = client.get(f"/api/sim/status/{run_id}")
        assert st_resp.status_code == 200
        st_data = st_resp.json()
        if st_data["status"] in ["COMPLETED", "FAILED"]:
            completed = True
            assert st_data["status"] == "COMPLETED"
            assert st_data["result"] is not None
            assert st_data["result"]["verdict"] == "PASSED"
            break
        time.sleep(0.2)
    assert completed is True

# -----------------------------------------------------------------------------
# 4. Telemetry, Benchmarks, and Verification Reports Tests
# -----------------------------------------------------------------------------
def test_get_simulation_history():
    response = client.get("/api/sim/history?limit=10")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) > 0

def test_get_benchmark_summary():
    response = client.get("/api/benchmark/summary")
    assert response.status_code == 200
    data = response.json()
    assert "metadata" in data
    assert "metric_definitions" in data
    assert "sweeps" in data
    assert "burst_size_scaling" in data["sweeps"]
    assert len(data["sweeps"]["burst_size_scaling"]) == 4

def test_download_benchmark_csv():
    response = client.get("/api/benchmark/csv")
    assert response.status_code == 200
    assert "text/csv" in response.headers["content-type"]
    content = response.text
    assert "exp_id,sweep,xfer_bytes,burst_beats" in content

def test_get_failure_triage_report():
    response = client.get("/api/triage/report")
    assert response.status_code == 200
    data = response.json()
    assert "metadata" in data
    assert data["metadata"]["detection_rate_pct"] == 100.0
    assert len(data["experiments"]) == 4

def test_get_coverage_summary():
    response = client.get("/api/coverage/summary")
    assert response.status_code == 200
    data = response.json()
    assert data["total_bins"] == 24
    assert data["covered_bins"] == 24
    assert data["coverage_percentage"] == 100.0

def test_get_phase5_summary():
    response = client.get("/api/phase5/summary")
    assert response.status_code == 200
    data = response.json()
    assert data["phase"] == 5
    assert data["batch_regression"]["verdict"] == "PASSED"

# -----------------------------------------------------------------------------
# 5. Waveform & Artifact Endpoints Tests
# -----------------------------------------------------------------------------
def test_list_artifacts():
    response = client.get("/api/artifacts")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    names = [a["name"] for a in data]
    assert "interface_spec.md" in names
    assert "verification_plan.md" in names
    assert "performance_analysis.md" in names
    assert "failure_triage_report.md" in names

def test_get_artifact_content():
    response = client.get("/api/artifacts/interface_spec.md")
    assert response.status_code == 200
    content = response.text
    assert "# DMA Subsystem Interface Specification" in content

def test_batch_run_execution():
    # Batch run with 2 seeds on fast arbiter suite
    payload = {
        "suite": "arbiter",
        "seed_count": 2,
        "bug_injection": "none",
        "timeout_sec": 30
    }
    response = client.post("/api/sim/batch", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["suite"] == "arbiter"
    assert data["total_runs"] == 2
    assert data["passed_runs"] == 2
    assert data["failed_runs"] == 0

def test_waveform_info_existing():
    # List history to find a real run
    h_resp = client.get("/api/sim/history?limit=1")
    assert h_resp.status_code == 200
    h_data = h_resp.json()
    if len(h_data) > 0:
        run_id = h_data[0]["run_id"]
        response = client.get(f"/api/waveform/info/{run_id}")
        assert response.status_code == 200
        w_data = response.json()
        assert w_data["run_id"] == run_id
        assert "exists" in w_data

def test_waveform_parsed():
    # Test parsed waveform on 'latest' run
    response = client.get("/api/waveform/parsed/latest?start_cycle=0&count=40")
    assert response.status_code == 200
    data = response.json()
    assert "timeline" in data
    assert "landmarks" in data
    assert "clock_frequency_mhz" in data
    assert len(data["timeline"]) == 41
    sample = data["timeline"][0]
    assert "cycle" in sample
    assert "time_ns" in sample
    assert "signals" in sample
    assert "fsm_state" in sample["signals"]
    assert "arb_grant" in sample["signals"]

def test_get_synthesis_summary():
    response = client.get("/api/synthesis/summary")
    assert response.status_code == 200
    data = response.json()
    assert data["metadata"]["phase"] == 9
    assert data["synthesizability_lint_audit"]["verdict"] == "PASSED"
    assert data["timing_constraints"]["target_frequency_mhz"] == 100.0
    assert "target_device" in data
    assert "structural_resource_estimation" in data



