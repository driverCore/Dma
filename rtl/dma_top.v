// =============================================================================
// File: dma_top.v
// Module: dma_top
// Description: Top-level integration module for DMA Subsystem (Phase 2).
//              Integrates configuration register file, burst FSM execution engine,
//              synchronous FIFO data buffer, and multi-master shared memory arbiter.
// Standard: IEEE 1364-2001 Verilog Synthesizable RTL
// =============================================================================

`timescale 1ns / 1ps

module dma_top #(
    parameter TIMEOUT_CYCLES = 500,
    parameter FIFO_DEPTH     = 16
) (
    input  wire        clk,
    input  wire        rst_n,

    // Host Configuration Bus
    input  wire        cfg_wr_en,
    input  wire        cfg_rd_en,
    input  wire [7:0]  cfg_addr,
    input  wire [31:0] cfg_wdata,
    output wire [31:0] cfg_rdata,
    output wire        irq,

    // Auxiliary External Requester Interface (e.g. CPU/Coprocessor Master)
    input  wire        ext_req,
    input  wire        ext_burst_lock,
    input  wire        ext_req_rw,
    input  wire [31:0] ext_req_addr,
    input  wire [31:0] ext_req_wdata,
    output wire        ext_grant,

    // Primary Shared Memory Bus Master Interface
    output wire        mem_req_valid,
    input  wire        mem_req_ready,
    output wire        mem_req_rw,
    output wire [31:0] mem_req_addr,
    output wire [31:0] mem_req_wdata,

    input  wire        mem_rsp_valid,
    output wire        mem_rsp_ready,
    input  wire [31:0] mem_rsp_rdata,
    input  wire        mem_rsp_err,

    // Live Debug Probes & Telemetry
    output wire [3:0]  debug_fsm_state,
    output wire [31:0] debug_bytes_done,
    output wire [4:0]  debug_fifo_occupancy,
    output wire [1:0]  debug_arb_grant
);

    // -------------------------------------------------------------------------
    // Internal Wires
    // -------------------------------------------------------------------------
    wire [31:0] reg_src_addr;
    wire [31:0] reg_dst_addr;
    wire [31:0] reg_xfer_len;
    wire [7:0]  reg_burst_cfg;
    wire        reg_arb_policy;
    wire        start_pulse;
    wire        abort_pulse;
    wire        soft_reset_pulse;

    wire        engine_busy;
    wire        engine_done;
    wire        engine_err_invalid;
    wire        engine_err_timeout;
    wire        engine_err_align;
    wire        engine_err_bus;
    wire [31:0] engine_bytes_done;

    // FIFO Interface Wires
    wire        fifo_wr_en;
    wire [31:0] fifo_wr_data;
    wire        fifo_full;
    wire        fifo_almost_full;
    wire        fifo_overflow;

    wire        fifo_rd_en;
    wire [31:0] fifo_rd_data;
    wire        fifo_empty;
    wire        fifo_almost_empty;
    wire        fifo_underflow;
    wire [4:0]  fifo_occupancy;

    // Arbiter Wires
    wire        dma_arb_req;
    wire        dma_arb_grant;
    wire        dma_arb_burst_lock;

    wire [1:0]  arb_req_vec        = {ext_req, dma_arb_req};
    wire [1:0]  arb_burst_lock_vec = {ext_burst_lock, dma_arb_burst_lock};
    wire [1:0]  arb_grant_vec;
    wire        arb_grant_valid;
    wire        arb_grant_id;

    wire [31:0] wait_cycles_req0;
    wire [31:0] wait_cycles_req1;
    wire [31:0] grants_req0;
    wire [31:0] grants_req1;

    assign dma_arb_grant = arb_grant_vec[0];
    assign ext_grant     = arb_grant_vec[1];

    // DMA Internal Memory Request Lines
    wire        dma_mem_req_valid;
    wire        dma_mem_req_rw;
    wire [31:0] dma_mem_req_addr;
    wire [31:0] dma_mem_req_wdata;
    wire        dma_mem_rsp_ready;

    // Multiplex Shared Memory Bus based on Arbiter Grant
    assign mem_req_valid = (arb_grant_vec[0]) ? dma_mem_req_valid :
                           (arb_grant_vec[1]) ? ext_req : 1'b0;

    assign mem_req_rw    = (arb_grant_vec[0]) ? dma_mem_req_rw :
                           (arb_grant_vec[1]) ? ext_req_rw : 1'b0;

    assign mem_req_addr  = (arb_grant_vec[0]) ? dma_mem_req_addr :
                           (arb_grant_vec[1]) ? ext_req_addr : 32'h0;

    assign mem_req_wdata = (arb_grant_vec[0]) ? dma_mem_req_wdata :
                           (arb_grant_vec[1]) ? ext_req_wdata : 32'h0;

    // Response Tag FIFO for routing pipelined memory responses to correct requester
    reg [7:0] tag_fifo;
    reg [2:0] tag_wr_ptr;
    reg [2:0] tag_rd_ptr;
    reg [3:0] tag_count;

    wire tx_issued  = mem_req_valid && mem_req_ready;
    wire tx_retired = mem_rsp_valid && mem_rsp_ready;

    always @(posedge clk) begin
        if (!rst_n || soft_reset_pulse) begin
            tag_fifo   <= 8'h0;
            tag_wr_ptr <= 3'd0;
            tag_rd_ptr <= 3'd0;
            tag_count  <= 4'd0;
        end else begin
            if (tx_issued) begin
                tag_fifo[tag_wr_ptr] <= arb_grant_vec[1]; // 0 = DMA, 1 = EXT
                tag_wr_ptr           <= tag_wr_ptr + 1'b1;
            end
            if (tx_retired) begin
                tag_rd_ptr           <= tag_rd_ptr + 1'b1;
            end
            case ({tx_issued, tx_retired})
                2'b10: tag_count <= tag_count + 1'b1;
                2'b01: tag_count <= tag_count - 1'b1;
                default: tag_count <= tag_count;
            endcase
        end
    end

    wire current_rsp_is_ext = (tag_count > 4'd0) ? tag_fifo[tag_rd_ptr] : 1'b0;
    wire dma_mem_rsp_valid  = mem_rsp_valid && !current_rsp_is_ext;

    assign mem_rsp_ready    = (current_rsp_is_ext) ? 1'b1 : dma_mem_rsp_ready;

    // Debug Probes
    assign debug_fifo_occupancy = fifo_occupancy;
    assign debug_arb_grant      = arb_grant_vec;

    // Telemetry vectors
    wire [31:0] arb_telemetry  = {wait_cycles_req1[15:0], wait_cycles_req0[15:1], reg_arb_policy};
    wire [31:0] fifo_telemetry = {20'h0, fifo_underflow, fifo_overflow, fifo_almost_empty, fifo_almost_full, fifo_empty, fifo_full, 1'b0, fifo_occupancy};

    // -------------------------------------------------------------------------
    // Configuration Register File
    // -------------------------------------------------------------------------
    dma_reg_file u_dma_reg_file (
        .clk                (clk),
        .rst_n              (rst_n),

        .cfg_wr_en          (cfg_wr_en),
        .cfg_rd_en          (cfg_rd_en),
        .cfg_addr           (cfg_addr),
        .cfg_wdata          (cfg_wdata),
        .cfg_rdata          (cfg_rdata),

        .reg_src_addr       (reg_src_addr),
        .reg_dst_addr       (reg_dst_addr),
        .reg_xfer_len       (reg_xfer_len),
        .reg_burst_cfg      (reg_burst_cfg),
        .reg_arb_policy     (reg_arb_policy),
        .start_pulse        (start_pulse),
        .abort_pulse        (abort_pulse),
        .soft_reset_pulse   (soft_reset_pulse),

        .engine_busy        (engine_busy),
        .engine_done        (engine_done),
        .engine_err_invalid (engine_err_invalid),
        .engine_err_timeout (engine_err_timeout),
        .engine_err_align   (engine_err_align),
        .engine_err_bus     (engine_err_bus),
        .engine_bytes_done  (engine_bytes_done),

        .arb_telemetry      (arb_telemetry),
        .fifo_telemetry     (fifo_telemetry),

        .irq                (irq)
    );

    // -------------------------------------------------------------------------
    // Synchronous Data Buffer FIFO
    // -------------------------------------------------------------------------
    dma_fifo #(
        .DATA_WIDTH         (32),
        .FIFO_DEPTH         (FIFO_DEPTH),
        .ALMOST_FULL_THRESH (14),
        .ALMOST_EMPTY_THRESH(2)
    ) u_dma_fifo (
        .clk                (clk),
        .rst_n              (rst_n && !soft_reset_pulse),

        .wr_en              (fifo_wr_en),
        .wr_data            (fifo_wr_data),
        .full               (fifo_full),
        .almost_full        (fifo_almost_full),
        .overflow           (fifo_overflow),

        .rd_en              (fifo_rd_en),
        .rd_data            (fifo_rd_data),
        .empty              (fifo_empty),
        .almost_empty       (fifo_almost_empty),
        .underflow          (fifo_underflow),

        .occupancy          (fifo_occupancy)
    );

    // -------------------------------------------------------------------------
    // Multi-Master Memory Arbiter
    // -------------------------------------------------------------------------
    dma_arbiter #(
        .NUM_REQUESTERS     (2)
    ) u_dma_arbiter (
        .clk                (clk),
        .rst_n              (rst_n && !soft_reset_pulse),

        .cfg_policy         (reg_arb_policy),
        .req                (arb_req_vec),
        .burst_lock         (arb_burst_lock_vec),

        .grant              (arb_grant_vec),
        .grant_valid        (arb_grant_valid),
        .grant_id           (arb_grant_id),

        .wait_cycles_req0   (wait_cycles_req0),
        .wait_cycles_req1   (wait_cycles_req1),
        .grants_req0        (grants_req0),
        .grants_req1        (grants_req1)
    );

    // -------------------------------------------------------------------------
    // DMA Controller Core Engine
    // -------------------------------------------------------------------------
    dma_controller #(
        .TIMEOUT_CYCLES     (TIMEOUT_CYCLES),
        .FIFO_DEPTH         (FIFO_DEPTH)
    ) u_dma_controller (
        .clk                (clk),
        .rst_n              (rst_n),

        .reg_src_addr       (reg_src_addr),
        .reg_dst_addr       (reg_dst_addr),
        .reg_xfer_len       (reg_xfer_len),
        .reg_burst_cfg      (reg_burst_cfg),
        .start_pulse        (start_pulse),
        .abort_pulse        (abort_pulse),
        .soft_reset_pulse   (soft_reset_pulse),

        .engine_busy        (engine_busy),
        .engine_done        (engine_done),
        .engine_err_invalid (engine_err_invalid),
        .engine_err_timeout (engine_err_timeout),
        .engine_err_align   (engine_err_align),
        .engine_err_bus     (engine_err_bus),
        .engine_bytes_done  (engine_bytes_done),

        .fifo_wr_en         (fifo_wr_en),
        .fifo_wr_data       (fifo_wr_data),
        .fifo_full          (fifo_full),
        .fifo_almost_full   (fifo_almost_full),
        .fifo_rd_en         (fifo_rd_en),
        .fifo_rd_data       (fifo_rd_data),
        .fifo_empty         (fifo_empty),
        .fifo_occupancy     (fifo_occupancy),

        .arb_req            (dma_arb_req),
        .arb_grant          (dma_arb_grant),
        .arb_burst_lock     (dma_arb_burst_lock),

        .mem_req_valid      (dma_mem_req_valid),
        .mem_req_ready      (mem_req_ready),
        .mem_req_rw         (dma_mem_req_rw),
        .mem_req_addr       (dma_mem_req_addr),
        .mem_req_wdata      (dma_mem_req_wdata),

        .mem_rsp_valid      (dma_mem_rsp_valid),
        .mem_rsp_ready      (dma_mem_rsp_ready),
        .mem_rsp_rdata      (mem_rsp_rdata),
        .mem_rsp_err        (mem_rsp_err),

        .debug_fsm_state    (debug_fsm_state),
        .debug_bytes_done   (debug_bytes_done)
    );

endmodule
