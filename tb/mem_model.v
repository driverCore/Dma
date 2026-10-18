// =============================================================================
// File: mem_model.v
// Module: mem_model
// Description: Behavioral dual-purpose memory model with parameterized access latency,
//              controllable stalls (backpressure injection), bus error injection,
//              and testbench backdoor read/write verification tasks.
// Standard: IEEE 1364-2001 Verilog
// =============================================================================

`timescale 1ns / 1ps

module mem_model #(
    parameter MEM_SIZE_WORDS = 16384, // 64 KB (16K words x 4 bytes)
    parameter DEFAULT_LATENCY = 1
) (
    input  wire        clk,
    input  wire        rst_n,

    // Memory Bus Slave Interface
    input  wire        mem_req_valid,
    output wire        mem_req_ready,
    input  wire        mem_req_rw,        // 0 = Read, 1 = Write
    input  wire [31:0] mem_req_addr,
    input  wire [31:0] mem_req_wdata,

    output reg         mem_rsp_valid,
    input  wire        mem_rsp_ready,
    output reg  [31:0] mem_rsp_rdata,
    output reg         mem_rsp_err
);

    // Internal Memory Array
    reg [31:0] ram [0:MEM_SIZE_WORDS-1];

    // Control parameters injectable by testbench
    reg [7:0]  cfg_latency_cycles;
    reg        cfg_force_stall;      // If 1, mem_req_ready is forced to 0
    reg        cfg_inject_err;        // If 1, mem_rsp_err asserts on response

    // Ready signal generation (allows backpressure simulation and transaction gating)
    assign mem_req_ready = rst_n && !cfg_force_stall && !pipe_valid[0] && !mem_rsp_valid;

    // Response pipeline tracking
    localparam MAX_PIPE_DEPTH = 16;
    reg [31:0] pipe_rdata   [0:MAX_PIPE_DEPTH-1];
    reg        pipe_err     [0:MAX_PIPE_DEPTH-1];
    reg [7:0]  pipe_delay   [0:MAX_PIPE_DEPTH-1];
    reg        pipe_valid   [0:MAX_PIPE_DEPTH-1];

    integer i;

    // Initialization and reset
    initial begin
        cfg_latency_cycles = DEFAULT_LATENCY;
        cfg_force_stall    = 1'b0;
        cfg_inject_err     = 1'b0;
        for (i = 0; i < MEM_SIZE_WORDS; i = i + 1) begin
            ram[i] = 32'h0;
        end
        for (i = 0; i < MAX_PIPE_DEPTH; i = i + 1) begin
            pipe_valid[i] = 1'b0;
            pipe_delay[i] = 8'd0;
            pipe_rdata[i] = 32'h0;
            pipe_err[i]   = 1'b0;
        end
    end

    wire [13:0] word_addr = mem_req_addr[15:2];

    // Synchronous memory access and response pipeline
    always @(posedge clk) begin
        if (!rst_n) begin
            mem_rsp_valid <= 1'b0;
            mem_rsp_rdata <= 32'h0;
            mem_rsp_err   <= 1'b0;
            for (i = 0; i < MAX_PIPE_DEPTH; i = i + 1) begin
                pipe_valid[i] <= 1'b0;
                pipe_delay[i] <= 8'd0;
            end
        end else begin
            // Clear response if consumed
            if (mem_rsp_valid && mem_rsp_ready) begin
                mem_rsp_valid <= 1'b0;
                mem_rsp_err   <= 1'b0;
            end

            // Process incoming request
            if (mem_req_valid && mem_req_ready) begin
                if (mem_req_rw) begin
                    // Write Operation
                    if (word_addr < MEM_SIZE_WORDS) begin
                        ram[word_addr] <= mem_req_wdata;
                    end
                    // Enqueue write response ACK into pipeline
                    pipe_valid[0] <= 1'b1;
                    pipe_delay[0] <= cfg_latency_cycles;
                    pipe_rdata[0] <= 32'h0;
                    pipe_err[0]   <= cfg_inject_err;
                end else begin
                    // Read Operation
                    pipe_valid[0] <= 1'b1;
                    pipe_delay[0] <= cfg_latency_cycles;
                    if (word_addr < MEM_SIZE_WORDS) begin
                        pipe_rdata[0] <= ram[word_addr];
                    end else begin
                        pipe_rdata[0] <= 32'hDEAD_BEEF;
                    end
                    pipe_err[0]   <= cfg_inject_err;
                end
            end

            // Progress latency countdown
            if (pipe_valid[0]) begin
                if (pipe_delay[0] == 8'd0) begin
                    mem_rsp_valid <= 1'b1;
                    mem_rsp_rdata <= pipe_rdata[0];
                    mem_rsp_err   <= pipe_err[0];
                    pipe_valid[0] <= 1'b0;
                end else begin
                    pipe_delay[0] <= pipe_delay[0] - 1'b1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Testbench Backdoor Tasks
    // -------------------------------------------------------------------------
    task backdoor_write_word;
        input [31:0] byte_addr;
        input [31:0] data;
        begin
            ram[byte_addr[15:2]] = data;
        end
    endtask

    task backdoor_read_word;
        input  [31:0] byte_addr;
        output [31:0] data;
        begin
            data = ram[byte_addr[15:2]];
        end
    endtask

    task backdoor_init_pattern;
        input [31:0] start_byte_addr;
        input integer word_count;
        input [31:0] seed_val;
        integer w;
        begin
            for (w = 0; w < word_count; w = w + 1) begin
                ram[(start_byte_addr[15:2]) + w] = seed_val + (w * 32'h0001_0001) ^ (w << 8);
            end
        end
    endtask

    task backdoor_clear_region;
        input [31:0] start_byte_addr;
        input integer word_count;
        integer w;
        begin
            for (w = 0; w < word_count; w = w + 1) begin
                ram[(start_byte_addr[15:2]) + w] = 32'h0;
            end
        end
    endtask

    task set_latency;
        input [7:0] lat;
        begin
            cfg_latency_cycles = lat;
        end
    endtask

    task set_force_stall;
        input stall;
        begin
            cfg_force_stall = stall;
        end
    endtask

    task set_inject_err;
        input err;
        begin
            cfg_inject_err = err;
        end
    endtask

endmodule
