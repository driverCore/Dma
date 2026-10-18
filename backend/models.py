"""
Pydantic Data Schemas for DMA Lab FastAPI Backend (Phase 6)
"""

from typing import List, Optional, Dict, Any, Literal
from pydantic import BaseModel, Field

# Request Models
class SimRunRequest(BaseModel):
    suite: Literal["top", "fifo", "arbiter", "benchmark"] = Field(
        default="top",
        description="Verification suite or benchmark harness to execute"
    )
    seed: Optional[int] = Field(
        default=None,
        description="Optional 32-bit integer seed for pseudo-random test generation"
    )
    bug_injection: Literal["none", "fifo_overflow", "arbiter_starve", "addr_stride"] = Field(
        default="none",
        description="Controlled RTL bug injection mode for verification triage"
    )
    timeout_sec: int = Field(
        default=60,
        ge=1,
        le=300,
        description="Execution watchdog timeout in seconds (1 to 300)"
    )
    async_exec: bool = Field(
        default=False,
        description="If True, runs in background and returns run_id immediately"
    )

class BatchRunRequest(BaseModel):
    suite: Literal["top", "fifo", "arbiter"] = Field(
        default="top",
        description="Suite to execute across batch seeds"
    )
    seed_count: int = Field(
        default=5,
        ge=1,
        le=20,
        description="Number of randomized seeds to evaluate (1 to 20)"
    )
    bug_injection: Literal["none", "fifo_overflow", "arbiter_starve", "addr_stride"] = Field(
        default="none",
        description="Controlled RTL bug injection mode"
    )
    timeout_sec: int = Field(
        default=60,
        ge=1,
        le=300,
        description="Watchdog timeout per simulation trial in seconds"
    )

# Response Models
class ToolchainInfo(BaseModel):
    tool: str
    path: str
    version: Optional[str] = None
    available: bool

class SystemStatusResponse(BaseModel):
    project_name: str
    phase: int
    clock_frequency_mhz: float
    os: str
    python_version: str
    tools: Dict[str, ToolchainInfo]
    ready: bool

class TestCaseResult(BaseModel):
    name: str
    status: str
    details: List[str] = []
    result_raw: Optional[str] = None

class AssertionViolation(BaseModel):
    cycle: int
    assertion: str
    message: str

class ScoreboardMismatch(BaseModel):
    word_offset: int
    address: str
    expected: str
    actual: str
    diff: str

class FunctionalCoverageSummary(BaseModel):
    total_bins: int
    covered_bins: int
    coverage_percentage: float

class SimRunSummary(BaseModel):
    run_id: str
    suite: str
    seed: int
    bug_injection: str
    verdict: str
    failure_category: str
    compile_time_sec: float
    sim_time_sec: float
    total_tests: int
    passed_tests: int
    failed_tests: int
    assertion_violation_count: int
    assertion_violations: List[AssertionViolation] = []
    scoreboard_mismatch_count: int
    scoreboard_mismatches: List[ScoreboardMismatch] = []
    functional_coverage: FunctionalCoverageSummary
    vcd_generated: bool
    run_dir: str
    log_file: str
    tests: List[TestCaseResult] = []

class SimJobStatus(BaseModel):
    run_id: str
    suite: str
    status: Literal["QUEUED", "RUNNING", "COMPLETED", "FAILED", "TIMEOUT"]
    start_time: str
    elapsed_sec: float
    result: Optional[SimRunSummary] = None
    error: Optional[str] = None

class HistoryItem(BaseModel):
    run_id: str
    suite: str
    seed: int
    bug_injection: str
    verdict: str
    failure_category: str
    sim_time_sec: float
    total_tests: int
    passed_tests: int
    failed_tests: int
    assertion_violation_count: int
    scoreboard_mismatch_count: int

class WaveformInfo(BaseModel):
    run_id: str
    vcd_file: str
    exists: bool
    size_bytes: int
    signal_count_approx: int

class ArtifactMeta(BaseModel):
    name: str
    path: str
    size_bytes: int
    last_modified: str
