# Hardware Failure Injection & Root-Cause Triage Report (Phase 5)

## 1. Executive Summary

This report documents the verification infrastructure's ability to detect, classify, and isolate real hardware RTL failure modes through controlled fault injection.
Four controlled experiments were executed using the automated Python simulation runner:
1. **Golden Baseline**: Verifies 100% test pass on verified RTL.
2. **Bug A (FIFO Overwrite)**: Unprotected FIFO write buffer corruption.
3. **Bug B (Arbiter Starvation)**: Priority inversion and watchdog timeout under contention.
4. **Bug C (Address Stride)**: Address generation error causing scoreboard data corruption.

**Key Result**: The verification testbench and protocol assertions achieved a **100.0% fault detection rate**, isolating failure cycles, affected addresses, and root causes without silent data corruption.

## 2. Fault Injection & Triage Matrix

| Exp ID | Injected Fault | Target RTL | Expected Verdict | Actual Verdict | Failure Category | Detection Status |
|:---:|:---|:---|:---:|:---:|:---:|:---:|
| EXP_GOLDEN | Golden Subsystem Verification | `None` | PASSED | PASSED | `NONE` | **PASS (100% Detected)** |
| EXP_BUG_FIFO | Bug A: FIFO Full Overwrite Under Backpressure | `rtl/dma_fifo.v` | FAILED | FAILED | `ASSERTION_VIOLATION` | **PASS (100% Detected)** |
| EXP_BUG_ARBITER | Bug B: Arbiter Priority Inversion & Master 0 Starvation | `rtl/dma_arbiter.v` | FAILED | FAILED | `TIMEOUT_WATCHDOG` | **PASS (100% Detected)** |
| EXP_BUG_ADDR | Bug C: Memory Address Stride & Alternate Word Dropping | `rtl/dma_controller.v` | FAILED | FAILED | `SCOREBOARD_DATA_MISMATCH` | **PASS (100% Detected)** |

---

## 3. Root-Cause Analysis by Fault Mode

### 3.1 EXP_GOLDEN: Golden Subsystem Verification
- **Target Module**: `None`
- **Fault Description**: Baseline regression verifying all 22 directed and randomized testcases pass.
- **Regression Outcome**: PASSED (22 passed, 0 failed)
- **Primary Failure Category**: `NONE`
- **Diagnostic Evidence**:
  - *Golden run cleanly passed with 0 mismatches and 0 assertion violations.*
- **Artifact Run Directory**: `C:\Users\aryan\Downloads\amd\P1\runs\run_20261018_224626_72b032`

### 3.2 EXP_BUG_FIFO: Bug A: FIFO Full Overwrite Under Backpressure
- **Target Module**: `rtl/dma_fifo.v`
- **Fault Description**: Removes !full protection from FIFO write gating, causing unread words to be overwritten.
- **Regression Outcome**: FAILED (7 passed, 3 failed)
- **Primary Failure Category**: `ASSERTION_VIOLATION`
- **Diagnostic Evidence**:
  - **Assertion Violations Triggered**:
    * `Cycle 25`: `ASSERT_FIFO_OVF` - Illegal write push while FIFO is FULL!
  - **Scoreboard Data Mismatches**:
    * `Offset 0` @ `Item_0`: Expected `0x00001000`, Received `0xdeadbeef` (Diff: `N/A`)
- **Artifact Run Directory**: `C:\Users\aryan\Downloads\amd\P1\runs\run_20261018_224626_b0e052`

### 3.3 EXP_BUG_ARBITER: Bug B: Arbiter Priority Inversion & Master 0 Starvation
- **Target Module**: `rtl/dma_arbiter.v`
- **Fault Description**: Inverts fixed priority order, starving Master 0 (DMA) during external requester contention.
- **Regression Outcome**: FAILED (21 passed, 1 failed)
- **Primary Failure Category**: `TIMEOUT_WATCHDOG`
- **Diagnostic Evidence**:
  - **Scoreboard Data Mismatches**:
    * `Offset 0` @ `0x00002000`: Expected `0xaaaa0001`, Received `0x00000000` (Diff: `0xaaaa0001`)
    * `Offset 1` @ `0x00002004`: Expected `0xaaab0102`, Received `0x00000000` (Diff: `0xaaab0102`)
    * `Offset 2` @ `0x00002008`: Expected `0xaaac0203`, Received `0x00000000` (Diff: `0xaaac0203`)
- **Artifact Run Directory**: `C:\Users\aryan\Downloads\amd\P1\runs\run_20261018_224626_d9751c`

### 3.4 EXP_BUG_ADDR: Bug C: Memory Address Stride & Alternate Word Dropping
- **Target Module**: `rtl/dma_controller.v`
- **Fault Description**: Increments source address by 8 bytes instead of 4, dropping alternate words.
- **Regression Outcome**: FAILED (10 passed, 12 failed)
- **Primary Failure Category**: `SCOREBOARD_DATA_MISMATCH`
- **Diagnostic Evidence**:
  - **Scoreboard Data Mismatches**:
    * `Offset 1` @ `0x00002004`: Expected `0x22230102`, Received `0x22240203` (Diff: `0x00070301`)
    * `Offset 2` @ `0x00002008`: Expected `0x22240203`, Received `0x00000000` (Diff: `0x22240203`)
    * `Offset 3` @ `0x0000200c`: Expected `0x22250304`, Received `0x00000000` (Diff: `0x22250304`)
- **Artifact Run Directory**: `C:\Users\aryan\Downloads\amd\P1\runs\run_20261018_224627_3502c9`
