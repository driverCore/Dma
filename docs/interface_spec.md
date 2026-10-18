# DMA Subsystem Interface Specification (Phase 1)
**Document Revision**: 1.0  
**Project**: DMA Verification & Performance Analysis Lab  
**Module**: `dma_top` / `dma_controller` / `dma_reg_file`  
**Standard**: IEEE 1364-2001 Verilog Synthesizable RTL  

---

## 1. Top-Level Signal Interface

The `dma_top` module interfaces to a host configuration bus (slave) and a system memory bus (master).

```
                      +-------------------+
                      |      dma_top      |
                      |                   |
  clk                 |--->               |
  rst_n               |--->               |
                      |                   |
  -- Host Config Bus -|                   |
  cfg_wr_en           |--->               |
  cfg_rd_en           |--->               |
  cfg_addr[7:0]       |--->               |
  cfg_wdata[31:0]     |--->               |
  cfg_rdata[31:0]     |<---               |
  irq                 |<---               |
                      |                   |
  -- Memory Bus Master|                   |
  mem_req_valid       |<---               |
  mem_req_ready       |--->               |
  mem_req_rw          |<---               |
  mem_req_addr[31:0]  |<---               |
  mem_req_wdata[31:0] |<---               |
  mem_rsp_valid       |--->               |
  mem_rsp_ready       |<---               |
  mem_rsp_rdata[31:0] |--->               |
  mem_rsp_err         |--->               |
                      |                   |
  -- Debug Probes ----|                   |
  debug_fsm_state[3:0]|<---               |
  debug_bytes_done[31:0]<--               |
                      +-------------------+
```

### 1.1 Pin Description Table

| Signal Name | Direction | Width | Reset Value | Description |
| :--- | :---: | :---: | :---: | :--- |
| `clk` | Input | 1 | - | Primary system clock (positive-edge triggered). |
| `rst_n` | Input | 1 | - | Active-LOW synchronous system reset. |
| **Host Config Bus** | | | | |
| `cfg_wr_en` | Input | 1 | - | Configuration write strobe (active-HIGH). |
| `cfg_rd_en` | Input | 1 | - | Configuration read strobe (active-HIGH). |
| `cfg_addr` | Input | 8 | - | Byte address offset of target register. |
| `cfg_wdata` | Input | 32 | - | Write data for configuration write cycles. |
| `cfg_rdata` | Output | 32 | 32'h0 | Read data returned from target register. |
| `irq` | Output | 1 | 1'b0 | Interrupt request output (asserted on transfer completion or error when IE is enabled). |
| **Memory Bus Master** | | | | |
| `mem_req_valid` | Output | 1 | 1'b0 | Request Valid: DMA initiates a memory access cycle. |
| `mem_req_ready` | Input | 1 | - | Request Ready: Memory system acknowledges acceptance of the request. Handshake occurs when `mem_req_valid && mem_req_ready`. |
| `mem_req_rw` | Output | 1 | 1'b0 | Request Read/Write: `0` = Read, `1` = Write. |
| `mem_req_addr` | Output | 32 | 32'h0 | Target 32-bit physical byte address (must be word-aligned, i.e., bits [1:0] = 00). |
| `mem_req_wdata`| Output | 32 | 32'h0 | Write data driven to memory on write requests. |
| `mem_rsp_valid` | Input | 1 | - | Response Valid: Memory asserts when read data is ready or write acknowledgment is presented. |
| `mem_rsp_ready` | Output | 1 | 1'b0 | Response Ready: DMA asserts when ready to receive memory response data. Handshake occurs when `mem_rsp_valid && mem_rsp_ready`. |
| `mem_rsp_rdata` | Input | 32 | - | Read data returned by memory. |
| `mem_rsp_err` | Input | 1 | - | Error flag from memory target (1 = uncorrectable fault / bus error). |
| **Debug Probes** | | | | |
| `debug_fsm_state`| Output | 4 | 4'b0 | Live FSM state index for waveform and cycle-level debugging. |
| `debug_bytes_done`| Output| 32 | 32'h0 | Real-time byte transfer progress counter. |

---

## 2. Register Map & Bit Definitions

All registers are 32-bit wide and mapped to 4-byte aligned boundaries.

| Offset | Name | Access | Reset Value | Description |
| :---: | :--- | :---: | :---: | :--- |
| `0x00` | `CTRL` | R/W | `32'h0000_0000` | Control Register |
| `0x04` | `STATUS` | R/W1C | `32'h0000_0000` | Status & Error Register |
| `0x08` | `SRC_ADDR` | R/W | `32'h0000_0000` | Source Memory Address (Word-aligned) |
| `0x0C` | `DST_ADDR` | R/W | `32'h0000_0000` | Destination Memory Address (Word-aligned) |
| `0x10` | `XFER_LEN` | R/W | `32'h0000_0000` | Transfer Length in Bytes (>0, multiple of 4) |
| `0x14` | `BURST_CFG`| R/W | `32'h0000_0001` | Burst Length in beats (Phase 1 supports single-beat 1; Phase 2 expands) |
| `0x18` | `BYTES_DONE`| RO | `32'h0000_0000` | Live counter of transferred bytes |

### 2.1 CTRL Register (`0x00`)
- **Bit 0 (`START`)**: Write `1` to trigger DMA execution. Automatically clears to `0` once the transfer initiates.
- **Bit 1 (`ABORT`)**: Write `1` to abort the active transfer and force return to `IDLE`.
- **Bit 2 (`IE`)**: Interrupt Enable. If `1`, `irq` pin asserts when `DONE` or any `ERR_*` bit becomes high.
- **Bit 3 (`SOFT_RESET`)**: Write `1` to perform a software reset of all internal state machines and pointers.

### 2.2 STATUS Register (`0x04`)
- **Bit 0 (`BUSY`)**: `1` when DMA transfer is active. `0` when idle or halted.
- **Bit 1 (`DONE`)**: `1` when DMA transfer completes successfully. Cleared by writing `1` to this bit or on next `START`.
- **Bit 2 (`ERR_INVALID_CFG`)**: `1` if transfer was rejected due to `XFER_LEN == 0` or length not a multiple of 4 bytes.
- **Bit 3 (`ERR_MEM_TIMEOUT`)**: `1` if memory failed to respond within watchdog threshold (`TIMEOUT_CYCLES`).
- **Bit 4 (`ERR_ALIGN`)**: `1` if `SRC_ADDR[1:0] != 2'b00` or `DST_ADDR[1:0] != 2'b00`.
- **Bit 5 (`ERR_BUS`)**: `1` if memory response returned `mem_rsp_err == 1`.
- **Bit 6 (`IRQ`)**: Latched interrupt status (`(DONE || ERR_*) && IE`).

---

## 3. Protocol Timing & Handshaking Rules

### 3.1 Request Phase
1. DMA asserts `mem_req_valid`, `mem_req_rw`, `mem_req_addr`, and (if write) `mem_req_wdata`.
2. Signals remain stable until the memory target asserts `mem_req_ready`.
3. The transfer request is accepted precisely on the rising clock edge where `mem_req_valid && mem_req_ready == 1`.
4. DMA deasserts `mem_req_valid` on the following cycle unless initiating back-to-back requests.

### 3.2 Response Phase
1. Memory target asserts `mem_rsp_valid`, returning `mem_rsp_rdata` (for reads) or completion status (for writes).
2. DMA asserts `mem_rsp_ready` when ready to receive.
3. The response is captured on the rising clock edge where `mem_rsp_valid && mem_rsp_ready == 1`.

---

## 4. Finite State Machine (FSM) Specification

```
State Encoding (4 bits):
  STATE_IDLE       = 4'd0
  STATE_VALIDATE   = 4'd1
  STATE_READ_REQ   = 4'd2
  STATE_READ_WAIT  = 4'd3
  STATE_WRITE_REQ  = 4'd4
  STATE_WRITE_WAIT = 4'd5
  STATE_CHECK_DONE = 4'd6
  STATE_DONE       = 4'd7
  STATE_ERROR      = 4'd8
```

- **Transitions**:
  - `IDLE` -> `VALIDATE`: Triggered by `start_pulse`.
  - `VALIDATE` -> `READ_REQ`: If `xfer_len > 0` AND all addresses are 4-byte aligned.
  - `VALIDATE` -> `ERROR`: If `xfer_len == 0` or address alignment error.
  - `READ_REQ` -> `READ_WAIT`: On `mem_req_valid && mem_req_ready`.
  - `READ_WAIT` -> `WRITE_REQ`: On `mem_rsp_valid && mem_rsp_ready && !mem_rsp_err`. Data word captured in holding buffer.
  - `READ_WAIT` -> `ERROR`: On watchdog timeout or `mem_rsp_err == 1`.
  - `WRITE_REQ` -> `WRITE_WAIT`: On `mem_req_valid && mem_req_ready`.
  - `WRITE_WAIT` -> `CHECK_DONE`: On `mem_rsp_valid && mem_rsp_ready && !mem_rsp_err`. Internal address and byte counters updated.
  - `WRITE_WAIT` -> `ERROR`: On watchdog timeout or `mem_rsp_err == 1`.
  - `CHECK_DONE` -> `DONE`: If `bytes_remaining == 0`.
  - `CHECK_DONE` -> `READ_REQ`: If `bytes_remaining > 0`.
  - `DONE` -> `IDLE`: On status clear or new start.
  - Any State -> `IDLE`: On `rst_n == 0`, `SOFT_RESET`, or `ABORT`.
