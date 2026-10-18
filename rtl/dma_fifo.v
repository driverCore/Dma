// =============================================================================
// File: dma_fifo.v
// Module: dma_fifo
// Description: Parameterized First-Word Fall-Through (FWFT) synchronous FIFO
//              with write-forwarding bypass, zero-latency lookahead on rd_data,
//              occupancy tracking, configurable watermarks (almost_full, almost_empty),
//              and deterministic simultaneous read/write corner-case resolution.
// Standard: IEEE 1364-2001 Verilog Synthesizable RTL
// =============================================================================

`timescale 1ns / 1ps

module dma_fifo #(
    parameter DATA_WIDTH          = 32,
    parameter FIFO_DEPTH          = 16, // Must be power of 2
    parameter ALMOST_FULL_THRESH  = 14,
    parameter ALMOST_EMPTY_THRESH = 2
) (
    input  wire                   clk,
    input  wire                   rst_n,

    // Write Interface
    input  wire                   wr_en,
    input  wire [DATA_WIDTH-1:0]  wr_data,
    output wire                   full,
    output wire                   almost_full,
    output reg                    overflow,

    // Read Interface
    input  wire                   rd_en,
    output wire [DATA_WIDTH-1:0]  rd_data,
    output wire                   empty,
    output wire                   almost_empty,
    output reg                    underflow,

    // Status and Observability
    output reg  [4:0]             occupancy
);

    localparam PTR_WIDTH = 4; // for depth 16

    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    reg [PTR_WIDTH-1:0] wr_ptr;
    reg [PTR_WIDTH-1:0] rd_ptr;

    assign empty        = (occupancy == 0);
    assign full         = (occupancy == FIFO_DEPTH);
    assign almost_empty = (occupancy <= ALMOST_EMPTY_THRESH);
    assign almost_full  = (occupancy >= ALMOST_FULL_THRESH);

    // FWFT Lookahead with Write-Forwarding Bypass on empty write
    assign rd_data      = (empty && wr_en) ? wr_data : mem[rd_ptr];

`ifdef BUG_FIFO_OVERWRITE
    // Injected Bug: Writes proceed unconditionally even when FIFO is full
    wire do_write = wr_en;
`else
    wire do_write = wr_en && (!full || rd_en);
`endif
    wire do_read  = rd_en && !empty;

    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr    <= {PTR_WIDTH{1'b0}};
            rd_ptr    <= {PTR_WIDTH{1'b0}};
            occupancy <= 5'd0;
            overflow  <= 1'b0;
            underflow <= 1'b0;
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                mem[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            overflow  <= 1'b0;
            underflow <= 1'b0;

            // Overflow detection
            if (wr_en && full && !rd_en) begin
                overflow <= 1'b1;
            end

            // Underflow detection
            if (rd_en && empty) begin
                underflow <= 1'b1;
            end

            // Write operation
            if (do_write) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr      <= wr_ptr + 1'b1;
            end

            // Read operation
            if (do_read) begin
                rd_ptr <= rd_ptr + 1'b1;
            end

            // Occupancy update
            case ({do_write, do_read})
                2'b10: occupancy <= occupancy + 1'b1;
                2'b01: occupancy <= occupancy - 1'b1;
                default: occupancy <= occupancy;
            endcase
        end
    end

endmodule
