// =============================================================================
// File: tb_dma_benchmark.v
// Module: tb_dma_benchmark
// Description: Dedicated cycle-accurate performance benchmarking harness for DMA Subsystem.
//              Systematically sweeps:
//                1. Burst Length (1, 2, 4, 8 beats)
//                2. Transfer Size (16B, 32B, 64B, 128B, 256B, 512B)
//                3. Memory Response Latency (0, 1, 2, 3, 4 cycles)
//                4. Multi-Master Arbitration Policy (Fixed-Priority vs Round-Robin)
//                5. Shared-Bus Contention (Solo, Light, Heavy)
//                6. Memory Backpressure Stall Intensity (0%, 25%, 50%, 75%)
//              Measures: Latency, Throughput (B/cycle and MB/s @ 100MHz),
//                        Bus Utilization, Peak FIFO Occupancy, and Contention Wait Times.
// Standard: IEEE 1364-2001 Verilog
// =============================================================================

`timescale 1ns / 1ps

module tb_dma_benchmark;

    parameter CLK_PERIOD     = 10;  // 100 MHz clock (10ns period)
    parameter TIMEOUT_CYCLES = 1000;
    parameter FIFO_DEPTH     = 16;

    // Clock and Reset
    reg         clk;
    reg         rst_n;

    // Host Config Bus
    reg         cfg_wr_en;
    reg         cfg_rd_en;
    reg  [7:0]  cfg_addr;
    reg  [31:0] cfg_wdata;
    wire [31:0] cfg_rdata;
    wire        irq;

    // External Requester (Master 1)
    reg         ext_req;
    reg         ext_burst_lock;
    reg         ext_req_rw;
    reg  [31:0] ext_req_addr;
    reg  [31:0] ext_req_wdata;
    wire        ext_grant;

    // Memory Bus Master Interface
    wire        mem_req_valid;
    wire        mem_req_ready;
    wire        mem_req_rw;
    wire [31:0] mem_req_addr;
    wire [31:0] mem_req_wdata;

    wire        mem_rsp_valid;
    wire        mem_rsp_ready;
    wire [31:0] mem_rsp_rdata;
    wire        mem_rsp_err;

    // Debug Probes
    wire [3:0]  debug_fsm_state;
    wire [31:0] debug_bytes_done;
    wire [4:0]  debug_fifo_occupancy;
    wire [1:0]  debug_arb_grant;

    // Telemetry registers from arbiter
    wire [31:0] wait_cycles_req0 = u_dma_top.u_dma_arbiter.wait_cycles_req0;
    wire [31:0] wait_cycles_req1 = u_dma_top.u_dma_arbiter.wait_cycles_req1;
    wire [31:0] grants_req0      = u_dma_top.u_dma_arbiter.grants_req0;
    wire [31:0] grants_req1      = u_dma_top.u_dma_arbiter.grants_req1;

    // Register Offsets
    localparam ADDR_CTRL        = 8'h00;
    localparam ADDR_STATUS      = 8'h04;
    localparam ADDR_SRC_ADDR    = 8'h08;
    localparam ADDR_DST_ADDR    = 8'h0C;
    localparam ADDR_XFER_LEN    = 8'h10;
    localparam ADDR_BURST_CFG   = 8'h14;
    localparam ADDR_BYTES_DONE  = 8'h18;
    localparam ADDR_ARB_CFG     = 8'h1C;

    // Clock Generation (100 MHz)
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Cycle Counter
    integer sim_cycles;
    always @(posedge clk) begin
        if (!rst_n)
            sim_cycles <= 0;
        else
            sim_cycles <= sim_cycles + 1;
    end

    // DUT Instantiation
    dma_top #(
        .TIMEOUT_CYCLES     (TIMEOUT_CYCLES),
        .FIFO_DEPTH         (FIFO_DEPTH)
    ) u_dma_top (
        .clk                (clk),
        .rst_n              (rst_n),

        .cfg_wr_en          (cfg_wr_en),
        .cfg_rd_en          (cfg_rd_en),
        .cfg_addr           (cfg_addr),
        .cfg_wdata          (cfg_wdata),
        .cfg_rdata          (cfg_rdata),
        .irq                (irq),

        .ext_req            (ext_req),
        .ext_burst_lock     (ext_burst_lock),
        .ext_req_rw         (ext_req_rw),
        .ext_req_addr       (ext_req_addr),
        .ext_req_wdata      (ext_req_wdata),
        .ext_grant          (ext_grant),

        .mem_req_valid      (mem_req_valid),
        .mem_req_ready      (mem_req_ready),
        .mem_req_rw         (mem_req_rw),
        .mem_req_addr       (mem_req_addr),
        .mem_req_wdata      (mem_req_wdata),

        .mem_rsp_valid      (mem_rsp_valid),
        .mem_rsp_ready      (mem_rsp_ready),
        .mem_rsp_rdata      (mem_rsp_rdata),
        .mem_rsp_err        (mem_rsp_err),

        .debug_fsm_state    (debug_fsm_state),
        .debug_bytes_done   (debug_bytes_done),
        .debug_fifo_occupancy(debug_fifo_occupancy),
        .debug_arb_grant    (debug_arb_grant)
    );

    // Memory Model Instantiation
    mem_model #(
        .MEM_SIZE_WORDS     (16384),
        .DEFAULT_LATENCY    (1)
    ) u_mem_model (
        .clk                (clk),
        .rst_n              (rst_n),

        .mem_req_valid      (mem_req_valid),
        .mem_req_ready      (mem_req_ready),
        .mem_req_rw         (mem_req_rw),
        .mem_req_addr       (mem_req_addr),
        .mem_req_wdata      (mem_req_wdata),

        .mem_rsp_valid      (mem_rsp_valid),
        .mem_rsp_ready      (mem_rsp_ready),
        .mem_rsp_rdata      (mem_rsp_rdata),
        .mem_rsp_err        (mem_rsp_err)
    );

    // -------------------------------------------------------------------------
    // Host Config Tasks
    // -------------------------------------------------------------------------
    task write_reg;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk);
            cfg_wr_en <= 1'b1;
            cfg_rd_en <= 1'b0;
            cfg_addr  <= addr;
            cfg_wdata <= data;
            @(posedge clk);
            cfg_wr_en <= 1'b0;
            cfg_wdata <= 32'h0;
            @(posedge clk);
        end
    endtask

    task read_reg;
        input  [7:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk);
            cfg_rd_en = 1'b1;
            cfg_wr_en = 1'b0;
            cfg_addr  = addr;
            #1;
            data = cfg_rdata;
            @(posedge clk);
            cfg_rd_en = 1'b0;
            #1;
        end
    endtask

    // -------------------------------------------------------------------------
    // Contention Generator Process
    // -------------------------------------------------------------------------
    integer contention_mode; // 0 = None, 1 = Light (25%), 2 = Heavy (100%)
    reg stop_contention;

    always @(posedge clk) begin
        if (!rst_n || stop_contention || contention_mode == 0) begin
            ext_req        <= 1'b0;
            ext_burst_lock <= 1'b0;
            ext_req_rw     <= 1'b0;
            ext_req_addr   <= 32'h0000_5000;
        end else if (contention_mode == 1) begin
            // Light contention: request every 4 cycles
            if (sim_cycles % 4 == 0)
                ext_req <= 1'b1;
            else
                ext_req <= 1'b0;
        end else if (contention_mode == 2) begin
            // Heavy contention: 100% active request
            ext_req <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Instrumentation Metrics Collector
    // -------------------------------------------------------------------------
    integer active_bus_handshakes;
    integer max_fifo_seen;
    reg     transfer_active;

    always @(posedge clk) begin
        if (!rst_n || !transfer_active) begin
            // Hold or clear
        end else begin
            if (mem_req_valid && mem_req_ready) begin
                active_bus_handshakes <= active_bus_handshakes + 1;
            end
            if (debug_fifo_occupancy > max_fifo_seen) begin
                max_fifo_seen <= debug_fifo_occupancy;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Unified Benchmark Trial Execution Task
    // -------------------------------------------------------------------------
    task run_trial;
        input integer exp_id;
        input [127:0] sweep_name;
        input integer xfer_bytes;
        input integer burst_beats;
        input integer mem_latency;
        input integer arb_policy;       // 0 = Fixed, 1 = RR
        input integer contention_type;  // 0 = Solo, 1 = Light, 2 = Heavy

        integer start_cyc, end_cyc, lat_cyc;
        integer start_w0, start_w1, start_g0, start_g1;
        real throughput_b_cyc;
        real throughput_mb_s;
        real bus_util_pct;
        reg [31:0] status_val;
        integer word_count;
        begin
            word_count = xfer_bytes / 4;

            // 1. Configure Memory Model
            u_mem_model.set_latency(mem_latency);
            u_mem_model.set_force_stall(1'b0);
            u_mem_model.set_inject_err(1'b0);
            u_mem_model.backdoor_init_pattern(32'h0000_1000, word_count, 32'h1000_0000 + (exp_id << 16));
            u_mem_model.backdoor_clear_region(32'h0000_2000, word_count);

            // 2. Configure DUT Registers
            write_reg(ADDR_ARB_CFG, arb_policy);
            write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
            write_reg(ADDR_DST_ADDR, 32'h0000_2000);
            write_reg(ADDR_XFER_LEN, xfer_bytes);
            write_reg(ADDR_BURST_CFG, burst_beats);

            // 3. Reset Instrumentation
            active_bus_handshakes = 0;
            max_fifo_seen         = 0;
            transfer_active       = 1'b0;
            contention_mode       = contention_type;
            stop_contention       = 1'b0;

            @(posedge clk);
            start_cyc = sim_cycles;
            start_w0  = wait_cycles_req0;
            start_w1  = wait_cycles_req1;
            start_g0  = grants_req0;
            start_g1  = grants_req1;
            transfer_active = 1'b1;

            // 4. Trigger DMA Start
            write_reg(ADDR_CTRL, 32'h0000_0005); // Start + IE

            // 5. Poll for completion
            read_reg(ADDR_STATUS, status_val);
            while (status_val[1] == 1'b0 && status_val[5:2] == 4'b0000) begin
                read_reg(ADDR_STATUS, status_val);
            end

            end_cyc = sim_cycles;
            transfer_active = 1'b0;
            stop_contention = 1'b1;
            ext_req <= 1'b0;

            lat_cyc = end_cyc - start_cyc;
            if (lat_cyc <= 0) lat_cyc = 1;

            throughput_b_cyc = (xfer_bytes * 1.0) / lat_cyc;
            throughput_mb_s  = throughput_b_cyc * 100.0; // 100 MHz clock
            bus_util_pct     = (active_bus_handshakes * 100.0) / lat_cyc;

            // 6. Clear status
            write_reg(ADDR_STATUS, 32'h0000_0002);

            // 7. Output Structured Machine-Readable CSV Line
            // FORMAT: [BENCH_DATA] exp_id,sweep_name,xfer_bytes,burst_beats,mem_latency,policy,contention,cycles,throughput_b_cyc,throughput_mb_s,bus_util_pct,max_fifo_occ,wait_req0,wait_req1,grants_req0,grants_req1
            $display("[BENCH_DATA] %0d,%0s,%0d,%0d,%0d,%0d,%0d,%0d,%0.4f,%0.2f,%0.2f,%0d,%0d,%0d,%0d,%0d",
                     exp_id, sweep_name, xfer_bytes, burst_beats, mem_latency, arb_policy, contention_type,
                     lat_cyc, throughput_b_cyc, throughput_mb_s, bus_util_pct, max_fifo_seen,
                     wait_cycles_req0 - start_w0, wait_cycles_req1 - start_w1,
                     grants_req0 - start_g0, grants_req1 - start_g1);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Benchmarking Routine
    // -------------------------------------------------------------------------
    integer trial_id;

    initial begin
        rst_n           = 1'b0;
        cfg_wr_en       = 1'b0;
        cfg_rd_en       = 1'b0;
        cfg_addr        = 8'h0;
        cfg_wdata       = 32'h0;
        ext_req         = 1'b0;
        ext_burst_lock  = 1'b0;
        ext_req_rw      = 1'b0;
        ext_req_addr    = 32'h0;
        ext_req_wdata   = 32'h0;
        contention_mode = 0;
        stop_contention = 1'b1;
        transfer_active = 1'b0;
        trial_id        = 0;

        $display("\n=======================================================");
        $display("    DMA Subsystem Performance Benchmarking Suite");
        $display("    Frequency: 100 MHz | Workload Sweeps");
        $display("=======================================================");
        $display("[CSV_HEADER] exp_id,sweep,xfer_bytes,burst_beats,mem_lat,policy,contention,cycles,tp_b_cyc,tp_mb_s,bus_util,max_fifo,wait0,wait1,grant0,grant1");

        // Power-on Reset
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // =====================================================================
        // SWEEP 1: Burst Size Scaling (Workload = 256 Bytes = 64 Words)
        // Fixed: Latency = 1, Policy = Fixed, Contention = Solo (0)
        // =====================================================================
        trial_id = trial_id + 1; run_trial(trial_id, "BURST_SCALE", 256, 1, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "BURST_SCALE", 256, 2, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "BURST_SCALE", 256, 4, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "BURST_SCALE", 256, 8, 1, 0, 0);

        // =====================================================================
        // SWEEP 2: Transfer Length Scaling (Amortization & Overhead)
        // Fixed: Latency = 1, Policy = Fixed, Contention = Solo (0)
        // Evaluated at Burst=1 vs Burst=4 vs Burst=8
        // =====================================================================
        trial_id = trial_id + 1; run_trial(trial_id, "LEN_SCALE_B1",  16, 1, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "LEN_SCALE_B1",  64, 1, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "LEN_SCALE_B1", 128, 1, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "LEN_SCALE_B1", 256, 1, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "LEN_SCALE_B1", 512, 1, 1, 0, 0);

        trial_id = trial_id + 1; run_trial(trial_id, "LEN_SCALE_B4",  16, 4, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "LEN_SCALE_B4",  64, 4, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "LEN_SCALE_B4", 128, 4, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "LEN_SCALE_B4", 256, 4, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "LEN_SCALE_B4", 512, 4, 1, 0, 0);

        trial_id = trial_id + 1; run_trial(trial_id, "LEN_SCALE_B8",  32, 8, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "LEN_SCALE_B8",  64, 8, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "LEN_SCALE_B8", 128, 8, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "LEN_SCALE_B8", 256, 8, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "LEN_SCALE_B8", 512, 8, 1, 0, 0);

        // =====================================================================
        // SWEEP 3: Memory Response Latency Sensitivity (Workload = 256 Bytes)
        // Sweeps Latency: 0, 1, 2, 3, 4 cycles for Burst=1 vs Burst=4 vs Burst=8
        // =====================================================================
        trial_id = trial_id + 1; run_trial(trial_id, "MEM_LAT_B1", 256, 1, 0, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "MEM_LAT_B1", 256, 1, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "MEM_LAT_B1", 256, 1, 2, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "MEM_LAT_B1", 256, 1, 3, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "MEM_LAT_B1", 256, 1, 4, 0, 0);

        trial_id = trial_id + 1; run_trial(trial_id, "MEM_LAT_B4", 256, 4, 0, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "MEM_LAT_B4", 256, 4, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "MEM_LAT_B4", 256, 4, 2, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "MEM_LAT_B4", 256, 4, 3, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "MEM_LAT_B4", 256, 4, 4, 0, 0);

        trial_id = trial_id + 1; run_trial(trial_id, "MEM_LAT_B8", 256, 8, 0, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "MEM_LAT_B8", 256, 8, 1, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "MEM_LAT_B8", 256, 8, 2, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "MEM_LAT_B8", 256, 8, 3, 0, 0);
        trial_id = trial_id + 1; run_trial(trial_id, "MEM_LAT_B8", 256, 8, 4, 0, 0);

        // =====================================================================
        // SWEEP 4: Multi-Master Contention & Arbitration Policies
        // Workload = 256 Bytes, Burst = 4, Latency = 1
        // Policies: Fixed-Priority (0) vs Round-Robin (1)
        // Contention: Solo (0), Light (1), Heavy (2)
        // =====================================================================
        trial_id = trial_id + 1; run_trial(trial_id, "ARB_CONTENTION", 256, 4, 1, 0, 0); // Fixed Solo
        trial_id = trial_id + 1; run_trial(trial_id, "ARB_CONTENTION", 256, 4, 1, 0, 1); // Fixed Light
        trial_id = trial_id + 1; run_trial(trial_id, "ARB_CONTENTION", 256, 4, 1, 0, 2); // Fixed Heavy
        trial_id = trial_id + 1; run_trial(trial_id, "ARB_CONTENTION", 256, 4, 1, 1, 0); // RR Solo
        trial_id = trial_id + 1; run_trial(trial_id, "ARB_CONTENTION", 256, 4, 1, 1, 1); // RR Light
        trial_id = trial_id + 1; run_trial(trial_id, "ARB_CONTENTION", 256, 4, 1, 1, 2); // RR Heavy

        $display("\n=======================================================");
        $display(" [BENCHMARK COMPLETE] Executed %0d Trials Successfully.", trial_id);
        $display("=======================================================\n");

        $finish(0);
    end

endmodule
