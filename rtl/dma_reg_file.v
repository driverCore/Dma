// =============================================================================
// File: dma_reg_file.v
// Module: dma_reg_file
// Description: Configuration and status register file for DMA Subsystem (Phase 2).
//              Supports 32-bit word-aligned read/write operations, burst configuration,
//              dynamic arbitration policy selection, and hardware telemetry readouts.
// Standard: IEEE 1364-2001 Verilog Synthesizable RTL
// =============================================================================

`timescale 1ns / 1ps

module dma_reg_file (
    input  wire        clk,
    input  wire        rst_n,

    // Host Configuration Bus
    input  wire        cfg_wr_en,
    input  wire        cfg_rd_en,
    input  wire [7:0]  cfg_addr,
    input  wire [31:0] cfg_wdata,
    output reg  [31:0] cfg_rdata,

    // Interface to DMA Engine
    output wire [31:0] reg_src_addr,
    output wire [31:0] reg_dst_addr,
    output wire [31:0] reg_xfer_len,
    output wire [7:0]  reg_burst_cfg,
    output wire        reg_arb_policy, // 0 = Fixed-Priority, 1 = Round-Robin
    output reg         start_pulse,
    output reg         abort_pulse,
    output reg         soft_reset_pulse,

    // Status from DMA Engine
    input  wire        engine_busy,
    input  wire        engine_done,
    input  wire        engine_err_invalid,
    input  wire        engine_err_timeout,
    input  wire        engine_err_align,
    input  wire        engine_err_bus,
    input  wire [31:0] engine_bytes_done,

    // Telemetry from Arbiter & FIFO
    input  wire [31:0] arb_telemetry,
    input  wire [31:0] fifo_telemetry,

    // Interrupt Request Output
    output wire        irq
);

    // Register Offsets
    localparam ADDR_CTRL        = 8'h00;
    localparam ADDR_STATUS      = 8'h04;
    localparam ADDR_SRC_ADDR    = 8'h08;
    localparam ADDR_DST_ADDR    = 8'h0C;
    localparam ADDR_XFER_LEN    = 8'h10;
    localparam ADDR_BURST_CFG   = 8'h14;
    localparam ADDR_BYTES_DONE  = 8'h18;
    localparam ADDR_ARB_CFG     = 8'h1C;
    localparam ADDR_FIFO_STATUS = 8'h20;

    // Internal Registers
    reg [31:0] reg_ctrl_q;
    reg [31:0] reg_status_q;
    reg [31:0] reg_src_addr_q;
    reg [31:0] reg_dst_addr_q;
    reg [31:0] reg_xfer_len_q;
    reg [31:0] reg_burst_cfg_q;
    reg [31:0] reg_arb_cfg_q;

    // Register Output Assignments
    assign reg_src_addr   = reg_src_addr_q;
    assign reg_dst_addr   = reg_dst_addr_q;
    assign reg_xfer_len   = reg_xfer_len_q;
    assign reg_burst_cfg  = reg_burst_cfg_q[7:0];
    assign reg_arb_policy = reg_arb_cfg_q[0];

    // Interrupt generation: asserted when IE bit is set and (DONE or any ERROR is active)
    wire interrupt_enable = reg_ctrl_q[2];
    wire status_any_error = reg_status_q[2] | reg_status_q[3] | reg_status_q[4] | reg_status_q[5];
    assign irq = interrupt_enable & (reg_status_q[1] | status_any_error);

    // Synchronous Write & Status Update Logic
    always @(posedge clk) begin
        if (!rst_n) begin
            reg_ctrl_q        <= 32'h0;
            reg_status_q      <= 32'h0;
            reg_src_addr_q    <= 32'h0;
            reg_dst_addr_q    <= 32'h0;
            reg_xfer_len_q    <= 32'h0;
            reg_burst_cfg_q   <= 32'h0000_0001; // Default 1 beat
            reg_arb_cfg_q     <= 32'h0000_0000; // Default Fixed-Priority
            start_pulse       <= 1'b0;
            abort_pulse       <= 1'b0;
            soft_reset_pulse  <= 1'b0;
        end else begin
            // Default pulse deassertion
            start_pulse      <= 1'b0;
            abort_pulse      <= 1'b0;
            soft_reset_pulse <= 1'b0;

            // Reflect Engine Live Status
            reg_status_q[0] <= engine_busy;

            // Latch Events from DMA Engine
            if (engine_done)
                reg_status_q[1] <= 1'b1;
            if (engine_err_invalid)
                reg_status_q[2] <= 1'b1;
            if (engine_err_timeout)
                reg_status_q[3] <= 1'b1;
            if (engine_err_align)
                reg_status_q[4] <= 1'b1;
            if (engine_err_bus)
                reg_status_q[5] <= 1'b1;

            // Update Latched IRQ flag
            reg_status_q[6] <= irq;

            // Host Write Handling
            if (cfg_wr_en) begin
                case (cfg_addr)
                    ADDR_CTRL: begin
                        if (cfg_wdata[0]) begin
                            start_pulse <= 1'b1;
                            reg_status_q[1] <= 1'b0;
                            reg_status_q[2] <= 1'b0;
                            reg_status_q[3] <= 1'b0;
                            reg_status_q[4] <= 1'b0;
                            reg_status_q[5] <= 1'b0;
                        end
                        if (cfg_wdata[1]) begin
                            abort_pulse <= 1'b1;
                        end
                        if (cfg_wdata[3]) begin
                            soft_reset_pulse <= 1'b1;
                            reg_status_q     <= 32'h0;
                        end
                        reg_ctrl_q[2] <= cfg_wdata[2]; // IE
                    end

                    ADDR_STATUS: begin
                        // Write-1-to-Clear (W1C) for status flags [5:1]
                        if (cfg_wdata[1]) reg_status_q[1] <= 1'b0;
                        if (cfg_wdata[2]) reg_status_q[2] <= 1'b0;
                        if (cfg_wdata[3]) reg_status_q[3] <= 1'b0;
                        if (cfg_wdata[4]) reg_status_q[4] <= 1'b0;
                        if (cfg_wdata[5]) reg_status_q[5] <= 1'b0;
                    end

                    ADDR_SRC_ADDR: begin
                        reg_src_addr_q <= cfg_wdata;
                    end

                    ADDR_DST_ADDR: begin
                        reg_dst_addr_q <= cfg_wdata;
                    end

                    ADDR_XFER_LEN: begin
                        reg_xfer_len_q <= cfg_wdata;
                    end

                    ADDR_BURST_CFG: begin
                        reg_burst_cfg_q <= cfg_wdata;
                    end

                    ADDR_ARB_CFG: begin
                        reg_arb_cfg_q[0] <= cfg_wdata[0]; // Bit 0: Policy
                    end

                    default: begin
                        // Ignore unmapped address writes
                    end
                endcase
            end
        end
    end

    // Combinational Read Multiplexer from Internal Flip-Flops & Telemetry
    always @(*) begin
        if (cfg_rd_en) begin
            case (cfg_addr)
                ADDR_CTRL:        cfg_rdata = reg_ctrl_q;
                ADDR_STATUS:      cfg_rdata = reg_status_q;
                ADDR_SRC_ADDR:    cfg_rdata = reg_src_addr_q;
                ADDR_DST_ADDR:    cfg_rdata = reg_dst_addr_q;
                ADDR_XFER_LEN:    cfg_rdata = reg_xfer_len_q;
                ADDR_BURST_CFG:   cfg_rdata = reg_burst_cfg_q;
                ADDR_BYTES_DONE:  cfg_rdata = engine_bytes_done;
                ADDR_ARB_CFG:     cfg_rdata = {arb_telemetry[31:1], reg_arb_cfg_q[0]};
                ADDR_FIFO_STATUS: cfg_rdata = fifo_telemetry;
                default:          cfg_rdata = 32'hDEAD_BEEF;
            endcase
        end else begin
            cfg_rdata = 32'h0;
        end
    end

endmodule
