// =============================================================================
// File: dma_controller.v
// Module: dma_controller
// Description: Core execution engine for DMA Subsystem (Phase 2).
//              Features parameterized burst engine (1, 2, 4, 8 beats),
//              First-Word Fall-Through (FWFT) synchronous FIFO data buffering,
//              backpressure flow control, memory arbitration interface with burst locking,
//              and watchdog timeout protection.
// Standard: IEEE 1364-2001 Verilog Synthesizable RTL
// =============================================================================

`timescale 1ns / 1ps

module dma_controller #(
    parameter TIMEOUT_CYCLES = 500,
    parameter FIFO_DEPTH     = 16
) (
    input  wire        clk,
    input  wire        rst_n,

    // Interface with Configuration Register File
    input  wire [31:0] reg_src_addr,
    input  wire [31:0] reg_dst_addr,
    input  wire [31:0] reg_xfer_len,
    input  wire [7:0]  reg_burst_cfg,
    input  wire        start_pulse,
    input  wire        abort_pulse,
    input  wire        soft_reset_pulse,

    output reg         engine_busy,
    output reg         engine_done,
    output reg         engine_err_invalid,
    output reg         engine_err_timeout,
    output reg         engine_err_align,
    output reg         engine_err_bus,
    output reg  [31:0] engine_bytes_done,

    // FIFO Interface (FWFT Mode)
    output reg         fifo_wr_en,
    output reg  [31:0] fifo_wr_data,
    input  wire        fifo_full,
    input  wire        fifo_almost_full,
    output reg         fifo_rd_en,
    input  wire [31:0] fifo_rd_data,
    input  wire        fifo_empty,
    input  wire [4:0]  fifo_occupancy,

    // Arbiter Requester Interface
    output reg         arb_req,
    input  wire        arb_grant,
    output reg         arb_burst_lock,

    // Master Memory Request / Response Interface
    output reg         mem_req_valid,
    input  wire        mem_req_ready,
    output reg         mem_req_rw,        // 0 = Read, 1 = Write
    output reg  [31:0] mem_req_addr,
    output wire [31:0] mem_req_wdata,

    input  wire        mem_rsp_valid,
    output reg         mem_rsp_ready,
    input  wire [31:0] mem_rsp_rdata,
    input  wire        mem_rsp_err,

    // Live Debug Probes
    output wire [3:0]  debug_fsm_state,
    output wire [31:0] debug_bytes_done
);

    // FSM State Encoding
    localparam STATE_IDLE        = 4'd0;
    localparam STATE_VALIDATE    = 4'd1;
    localparam STATE_READ_REQ    = 4'd2;
    localparam STATE_READ_WAIT   = 4'd3;
    localparam STATE_WRITE_REQ   = 4'd4;
    localparam STATE_WRITE_WAIT  = 4'd5;
    localparam STATE_CHECK_DONE  = 4'd6;
    localparam STATE_DONE        = 4'd7;
    localparam STATE_ERROR       = 4'd8;

    reg [3:0]  state_q;
    reg [31:0] cur_src_addr_q;
    reg [31:0] cur_dst_addr_q;
    reg [31:0] bytes_remaining_q;
    reg [31:0] bytes_done_q;
    reg [31:0] timeout_counter_q;

    // Burst tracking
    reg [7:0]  configured_burst_beats;
    reg [7:0]  cur_burst_beats;
    reg [7:0]  burst_beat_index;

    // Combinational assignments
    assign debug_fsm_state  = state_q;
    assign debug_bytes_done = bytes_done_q;
    assign mem_req_wdata    = fifo_rd_data; // Continuous FWFT zero-latency lookahead

    // Words remaining calculation
    wire [29:0] words_remaining = bytes_remaining_q[31:2];

    // Combinational burst size calculation (clamps to remaining words)
    wire [7:0] target_burst_size = (configured_burst_beats > 8'd0 && configured_burst_beats <= 8'd8) ?
                                   configured_burst_beats : 8'd1;
    wire [7:0] next_burst_beats = (words_remaining < target_burst_size) ?
                                  words_remaining[7:0] : target_burst_size;

    always @(posedge clk) begin
        if (!rst_n || soft_reset_pulse) begin
            state_q                <= STATE_IDLE;
            cur_src_addr_q         <= 32'h0;
            cur_dst_addr_q         <= 32'h0;
            bytes_remaining_q      <= 32'h0;
            bytes_done_q           <= 32'h0;
            timeout_counter_q      <= 32'h0;
            configured_burst_beats <= 8'd1;
            cur_burst_beats        <= 8'd1;
            burst_beat_index       <= 8'd0;

            engine_busy            <= 1'b0;
            engine_done            <= 1'b0;
            engine_err_invalid     <= 1'b0;
            engine_err_timeout     <= 1'b0;
            engine_err_align       <= 1'b0;
            engine_err_bus         <= 1'b0;
            engine_bytes_done      <= 32'h0;

            fifo_wr_en             <= 1'b0;
            fifo_wr_data           <= 32'h0;
            fifo_rd_en             <= 1'b0;

            arb_req                <= 1'b0;
            arb_burst_lock         <= 1'b0;

            mem_req_valid          <= 1'b0;
            mem_req_rw             <= 1'b0;
            mem_req_addr           <= 32'h0;
            mem_rsp_ready          <= 1'b0;
        end else if (abort_pulse) begin
            state_q                <= STATE_IDLE;
            engine_busy            <= 1'b0;
            arb_req                <= 1'b0;
            arb_burst_lock         <= 1'b0;
            mem_req_valid          <= 1'b0;
            mem_rsp_ready          <= 1'b0;
            fifo_wr_en             <= 1'b0;
            fifo_rd_en             <= 1'b0;
        end else begin
            // Default pulse deassertion
            engine_done        <= 1'b0;
            engine_err_invalid <= 1'b0;
            engine_err_timeout <= 1'b0;
            engine_err_align   <= 1'b0;
            engine_err_bus     <= 1'b0;
            engine_bytes_done  <= bytes_done_q;

            fifo_wr_en         <= 1'b0;
            fifo_rd_en         <= 1'b0;

            case (state_q)
                STATE_IDLE: begin
                    engine_busy    <= 1'b0;
                    arb_req        <= 1'b0;
                    arb_burst_lock <= 1'b0;
                    mem_req_valid  <= 1'b0;
                    mem_rsp_ready  <= 1'b0;
                    if (start_pulse) begin
                        engine_busy       <= 1'b1;
                        bytes_done_q      <= 32'h0;
                        engine_bytes_done <= 32'h0;
                        state_q           <= STATE_VALIDATE;
                    end
                end

                STATE_VALIDATE: begin
                    if (reg_xfer_len == 32'd0 || reg_xfer_len[1:0] != 2'b00) begin
                        engine_err_invalid <= 1'b1;
                        engine_busy        <= 1'b0;
                        state_q            <= STATE_ERROR;
                    end else if (reg_src_addr[1:0] != 2'b00 || reg_dst_addr[1:0] != 2'b00) begin
                        engine_err_align   <= 1'b1;
                        engine_busy        <= 1'b0;
                        state_q            <= STATE_ERROR;
                    end else begin
                        cur_src_addr_q         <= reg_src_addr;
                        cur_dst_addr_q         <= reg_dst_addr;
                        bytes_remaining_q      <= reg_xfer_len;
                        configured_burst_beats <= (reg_burst_cfg > 8'd0 && reg_burst_cfg <= 8'd8) ?
                                                   reg_burst_cfg : 8'd1;
                        burst_beat_index       <= 8'd0;
                        timeout_counter_q      <= 32'd0;
                        state_q                <= STATE_READ_REQ;
                    end
                end

                STATE_READ_REQ: begin
                    if (burst_beat_index == 8'd0) begin
                        cur_burst_beats <= next_burst_beats;
                    end

                    // Check FIFO capacity headroom before issuing read request (backpressure protection)
                    if ((fifo_occupancy + next_burst_beats) <= FIFO_DEPTH) begin
                        arb_req <= 1'b1;

                        if (arb_grant) begin
                            arb_burst_lock <= 1'b1;
                            mem_req_valid  <= 1'b1;
                            mem_req_rw     <= 1'b0; // Read
                            mem_req_addr   <= cur_src_addr_q;

                            if (mem_req_valid && mem_req_ready) begin
                                mem_req_valid     <= 1'b0;
                                timeout_counter_q <= 32'd0;
                                mem_rsp_ready     <= 1'b1;
                                state_q           <= STATE_READ_WAIT;
                            end else begin
                                timeout_counter_q <= timeout_counter_q + 1'b1;
                                if (timeout_counter_q >= TIMEOUT_CYCLES) begin
                                    mem_req_valid      <= 1'b0;
                                    arb_req            <= 1'b0;
                                    arb_burst_lock     <= 1'b0;
                                    engine_err_timeout <= 1'b1;
                                    engine_busy        <= 1'b0;
                                    state_q            <= STATE_ERROR;
                                end
                            end
                        end else begin
                            timeout_counter_q <= timeout_counter_q + 1'b1;
                            if (timeout_counter_q >= TIMEOUT_CYCLES) begin
                                arb_req            <= 1'b0;
                                engine_err_timeout <= 1'b1;
                                engine_busy        <= 1'b0;
                                state_q            <= STATE_ERROR;
                            end
                        end
                    end else begin
                        // FIFO almost full: wait for write drain (backpressure)
                        timeout_counter_q <= timeout_counter_q + 1'b1;
                        if (timeout_counter_q >= TIMEOUT_CYCLES) begin
                            engine_err_timeout <= 1'b1;
                            engine_busy        <= 1'b0;
                            state_q            <= STATE_ERROR;
                        end
                    end
                end

                STATE_READ_WAIT: begin
                    mem_rsp_ready <= 1'b1;

                    if (mem_rsp_valid) begin
                        mem_rsp_ready <= 1'b0;
                        if (mem_rsp_err) begin
                            engine_err_bus <= 1'b1;
                            engine_busy    <= 1'b0;
                            arb_req        <= 1'b0;
                            arb_burst_lock <= 1'b0;
                            state_q        <= STATE_ERROR;
                        end else begin
                            // Push word into FIFO
                            fifo_wr_en     <= 1'b1;
                            fifo_wr_data   <= mem_rsp_rdata;
`ifdef BUG_ADDR_STRIDE
                            // Injected Bug: Skips alternate 32-bit words (stride 8 instead of 4)
                            cur_src_addr_q <= cur_src_addr_q + 32'd8;
`else
                            cur_src_addr_q <= cur_src_addr_q + 32'd4;
`endif
                            timeout_counter_q <= 32'd0;

                            if (burst_beat_index + 1'b1 == cur_burst_beats) begin
                                // Read burst completed: proceed to write burst
                                burst_beat_index <= 8'd0;
                                state_q          <= STATE_WRITE_REQ;
                            end else begin
                                // Fetch next beat of this read burst
                                burst_beat_index <= burst_beat_index + 1'b1;
                                state_q          <= STATE_READ_REQ;
                            end
                        end
                    end else begin
                        timeout_counter_q <= timeout_counter_q + 1'b1;
                        if (timeout_counter_q >= TIMEOUT_CYCLES) begin
                            mem_rsp_ready      <= 1'b0;
                            arb_req            <= 1'b0;
                            arb_burst_lock     <= 1'b0;
                            engine_err_timeout <= 1'b1;
                            engine_busy        <= 1'b0;
                            state_q            <= STATE_ERROR;
                        end
                    end
                end

                STATE_WRITE_REQ: begin
                    if (!fifo_empty) begin
                        arb_req <= 1'b1;

                        if (arb_grant) begin
                            arb_burst_lock <= 1'b1;
                            mem_req_valid  <= 1'b1;
                            mem_req_rw     <= 1'b1; // Write
                            mem_req_addr   <= cur_dst_addr_q;

                            if (mem_req_valid && mem_req_ready) begin
                                mem_req_valid     <= 1'b0;
                                fifo_rd_en        <= 1'b1; // Pop consumed word on handshake!
                                timeout_counter_q <= 32'd0;
                                mem_rsp_ready     <= 1'b1;
                                state_q           <= STATE_WRITE_WAIT;
                            end else begin
                                timeout_counter_q <= timeout_counter_q + 1'b1;
                                if (timeout_counter_q >= TIMEOUT_CYCLES) begin
                                    mem_req_valid      <= 1'b0;
                                    arb_req            <= 1'b0;
                                    arb_burst_lock     <= 1'b0;
                                    engine_err_timeout <= 1'b1;
                                    engine_busy        <= 1'b0;
                                    state_q            <= STATE_ERROR;
                                end
                            end
                        end else begin
                            timeout_counter_q <= timeout_counter_q + 1'b1;
                            if (timeout_counter_q >= TIMEOUT_CYCLES) begin
                                arb_req            <= 1'b0;
                                engine_err_timeout <= 1'b1;
                                engine_busy        <= 1'b0;
                                state_q            <= STATE_ERROR;
                            end
                        end
                    end else begin
                        // Wait for FIFO to have data available
                        timeout_counter_q <= timeout_counter_q + 1'b1;
                        if (timeout_counter_q >= TIMEOUT_CYCLES) begin
                            engine_err_timeout <= 1'b1;
                            engine_busy        <= 1'b0;
                            state_q            <= STATE_ERROR;
                        end
                    end
                end

                STATE_WRITE_WAIT: begin
                    mem_rsp_ready <= 1'b1;

                    if (mem_rsp_valid) begin
                        mem_rsp_ready <= 1'b0;
                        if (mem_rsp_err) begin
                            engine_err_bus <= 1'b1;
                            engine_busy    <= 1'b0;
                            arb_req        <= 1'b0;
                            arb_burst_lock <= 1'b0;
                            state_q        <= STATE_ERROR;
                        end else begin
                            // Successfully committed write beat
                            cur_dst_addr_q    <= cur_dst_addr_q + 32'd4;
                            bytes_remaining_q <= bytes_remaining_q - 32'd4;
                            bytes_done_q      <= bytes_done_q + 32'd4;
                            timeout_counter_q <= 32'd0;

                            if (burst_beat_index + 1'b1 == cur_burst_beats) begin
                                // Completed entire write burst: release lock
                                arb_burst_lock   <= 1'b0;
                                arb_req          <= 1'b0;
                                burst_beat_index <= 8'd0;
                                state_q          <= STATE_CHECK_DONE;
                            end else begin
                                // Continue next beat of write burst
                                burst_beat_index <= burst_beat_index + 1'b1;
                                state_q          <= STATE_WRITE_REQ;
                            end
                        end
                    end else begin
                        timeout_counter_q <= timeout_counter_q + 1'b1;
                        if (timeout_counter_q >= TIMEOUT_CYCLES) begin
                            mem_rsp_ready      <= 1'b0;
                            arb_req            <= 1'b0;
                            arb_burst_lock     <= 1'b0;
                            engine_err_timeout <= 1'b1;
                            engine_busy        <= 1'b0;
                            state_q            <= STATE_ERROR;
                        end
                    end
                end

                STATE_CHECK_DONE: begin
                    engine_bytes_done <= bytes_done_q;
                    if (bytes_remaining_q == 32'd0) begin
                        state_q <= STATE_DONE;
                    end else begin
                        burst_beat_index  <= 8'd0;
                        timeout_counter_q <= 32'd0;
                        state_q           <= STATE_READ_REQ;
                    end
                end

                STATE_DONE: begin
                    engine_busy       <= 1'b0;
                    engine_done       <= 1'b1;
                    engine_bytes_done <= bytes_done_q;
                    arb_req           <= 1'b0;
                    arb_burst_lock    <= 1'b0;
                    state_q           <= STATE_IDLE;
                end

                STATE_ERROR: begin
                    engine_busy    <= 1'b0;
                    arb_req        <= 1'b0;
                    arb_burst_lock <= 1'b0;
                    mem_req_valid  <= 1'b0;
                    mem_rsp_ready  <= 1'b0;
                    if (start_pulse) begin
                        engine_busy       <= 1'b1;
                        bytes_done_q      <= 32'h0;
                        engine_bytes_done <= 32'h0;
                        state_q           <= STATE_VALIDATE;
                    end
                end

                default: begin
                    state_q <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
