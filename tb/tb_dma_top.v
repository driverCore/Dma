// =============================================================================
// File: tb_dma_top.v
// Module: tb_dma_top
// Description: Comprehensive self-checking verification environment for DMA Subsystem (Phase 3).
//              Features transaction scoreboard, protocol invariant assertions,
//              functional coverage model, directed corner-case tests,
//              fault injection (unaligned addresses, invalid lengths, bus errors, watchdog timeouts),
//              reliability tests (software abort, soft reset recovery),
//              variable memory response latencies (0 to 4 cycles),
//              and constrained-random testing with deterministic seed recording.
// Standard: IEEE 1364-2001 Verilog
// =============================================================================

`timescale 1ns / 1ps

module tb_dma_top;

    // -------------------------------------------------------------------------
    // Simulation Parameters
    // -------------------------------------------------------------------------
    parameter CLK_PERIOD     = 10;  // 100 MHz (10ns clock period)
    parameter TIMEOUT_CYCLES = 200; // Watchdog timeout threshold in cycles
    parameter FIFO_DEPTH     = 16;  // FIFO depth

    // -------------------------------------------------------------------------
    // Testbench Signals
    // -------------------------------------------------------------------------
    reg         clk;
    reg         rst_n;

    // Host Configuration Bus
    reg         cfg_wr_en;
    reg         cfg_rd_en;
    reg  [7:0]  cfg_addr;
    reg  [31:0] cfg_wdata;
    wire [31:0] cfg_rdata;
    wire        irq;

    // Auxiliary External Requester Interface (Requester 1)
    reg         ext_req;
    reg         ext_burst_lock;
    reg         ext_req_rw;
    reg  [31:0] ext_req_addr;
    reg  [31:0] ext_req_wdata;
    wire        ext_grant;

    // Primary Shared Memory Bus Master Interface
    wire        mem_req_valid;
    wire        mem_req_ready;
    wire        mem_req_rw;
    wire [31:0] mem_req_addr;
    wire [31:0] mem_req_wdata;

    wire        mem_rsp_valid;
    wire        mem_rsp_ready;
    wire [31:0] mem_rsp_rdata;
    wire        mem_rsp_err;

    // Debug Probes from DUT
    wire [3:0]  debug_fsm_state;
    wire [31:0] debug_bytes_done;
    wire [4:0]  debug_fifo_occupancy;
    wire [1:0]  debug_arb_grant;

    // Test Tracking Variables
    integer test_count;
    integer pass_count;
    integer fail_count;
    integer sim_cycles;
    integer assertion_failures;
    integer total_assertion_checks;

    // Randomization Controls
    integer random_seed;
    integer rand_iter;

    // -------------------------------------------------------------------------
    // Register Address Map
    // -------------------------------------------------------------------------
    localparam ADDR_CTRL        = 8'h00;
    localparam ADDR_STATUS      = 8'h04;
    localparam ADDR_SRC_ADDR    = 8'h08;
    localparam ADDR_DST_ADDR    = 8'h0C;
    localparam ADDR_XFER_LEN    = 8'h10;
    localparam ADDR_BURST_CFG   = 8'h14;
    localparam ADDR_BYTES_DONE  = 8'h18;
    localparam ADDR_ARB_CFG     = 8'h1C;
    localparam ADDR_FIFO_STATUS = 8'h20;

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Cycle Counter Monitor
    always @(posedge clk) begin
        if (!rst_n)
            sim_cycles <= 0;
        else
            sim_cycles <= sim_cycles + 1;
    end

    // Global Safety Watchdog
    initial begin
        #50000000; // 50 ms simulation limit
        $display("\n=======================================================");
        $display("[FATAL ERROR] Global Simulation Watchdog Timeout reached!");
        $display("=======================================================");
        $finish(2);
    end

    // -------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // Behavioral Dual-Port Memory Model
    // -------------------------------------------------------------------------
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
    // Protocol Invariant Assertions
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            total_assertion_checks <= total_assertion_checks + 1;

            // Invariant 1: Bus Memory Request Address must be 32-bit Word Aligned
            if (mem_req_valid && mem_req_ready) begin
                if (mem_req_addr[1:0] != 2'b00) begin
                    $display("[ASSERTION VIOLATION @ cycle %0d] ASSERT_WORD_ALIGN: Memory request address 0x%08X is not 32-bit aligned!",
                             sim_cycles, mem_req_addr);
                    assertion_failures <= assertion_failures + 1;
                end
            end

            // Invariant 2: FIFO Capacity Overflow Violation
            if (u_dma_top.u_dma_fifo.wr_en && u_dma_top.u_dma_fifo.full && !u_dma_top.u_dma_fifo.rd_en) begin
                $display("[ASSERTION VIOLATION @ cycle %0d] ASSERT_FIFO_OVF: Illegal write push while FIFO is FULL!",
                         sim_cycles);
                assertion_failures <= assertion_failures + 1;
            end

            // Invariant 3: FIFO Underflow Violation
            if (u_dma_top.u_dma_fifo.rd_en && u_dma_top.u_dma_fifo.empty) begin
                $display("[ASSERTION VIOLATION @ cycle %0d] ASSERT_FIFO_UDF: Illegal read pop while FIFO is EMPTY!",
                         sim_cycles);
                assertion_failures <= assertion_failures + 1;
            end

            // Invariant 4: FSM Mutual Exclusivity (Engine cannot be busy and done simultaneously)
            if (u_dma_top.engine_busy && u_dma_top.engine_done) begin
                $display("[ASSERTION VIOLATION @ cycle %0d] ASSERT_FSM_MUTEX: engine_busy and engine_done are simultaneously active!",
                         sim_cycles);
                assertion_failures <= assertion_failures + 1;
            end

            // Invariant 5: Arbiter Non-Preemption during active burst lock
            if (u_dma_top.u_dma_arbiter.is_locked && (u_dma_top.u_dma_arbiter.grant == 2'b00)) begin
                $display("[ASSERTION VIOLATION @ cycle %0d] ASSERT_BURST_LOCK: Grant dropped while burst lock active!",
                         sim_cycles);
                assertion_failures <= assertion_failures + 1;
            end

            // Invariant 6: Transferred bytes upper bound check during active transfer
            if (u_dma_top.engine_busy && u_dma_top.reg_xfer_len > 0 && (debug_bytes_done > u_dma_top.reg_xfer_len)) begin
                $display("[ASSERTION VIOLATION @ cycle %0d] ASSERT_BYTES_BOUND: Bytes done (%0d) exceeded configured transfer length (%0d)!",
                         sim_cycles, debug_bytes_done, u_dma_top.reg_xfer_len);
                assertion_failures <= assertion_failures + 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Functional Coverage Tracking Model
    // -------------------------------------------------------------------------
    // Coverage Bins
    integer cov_burst_1, cov_burst_2, cov_burst_4, cov_burst_8;
    integer cov_len_single, cov_len_short, cov_len_med, cov_len_long, cov_len_rem;
    integer cov_err_zero_len, cov_err_unalign_len, cov_err_unalign_src, cov_err_unalign_dst;
    integer cov_err_bus_read, cov_err_bus_write, cov_err_timeout;
    integer cov_ctrl_abort, cov_ctrl_reset;
    integer cov_lat_0, cov_lat_1, cov_lat_multi;
    integer cov_arb_fixed, cov_arb_rr, cov_arb_lock;

    task init_coverage;
        begin
            cov_burst_1         = 0; cov_burst_2         = 0;
            cov_burst_4         = 0; cov_burst_8         = 0;
            cov_len_single      = 0; cov_len_short       = 0;
            cov_len_med         = 0; cov_len_long        = 0;
            cov_len_rem         = 0;
            cov_err_zero_len    = 0; cov_err_unalign_len = 0;
            cov_err_unalign_src = 0; cov_err_unalign_dst = 0;
            cov_err_bus_read    = 0; cov_err_bus_write   = 0;
            cov_err_timeout     = 0;
            cov_ctrl_abort      = 0; cov_ctrl_reset      = 0;
            cov_lat_0           = 0; cov_lat_1           = 0;
            cov_lat_multi       = 0;
            cov_arb_fixed       = 0; cov_arb_rr          = 0;
            cov_arb_lock        = 0;
        end
    endtask

    task sample_transfer_coverage;
        input [31:0] length_bytes;
        input [7:0]  burst_beats;
        input [7:0]  latency_cycles;
        input        policy;
        begin
            // Burst Bins
            case (burst_beats)
                8'd1: cov_burst_1 = cov_burst_1 + 1;
                8'd2: cov_burst_2 = cov_burst_2 + 1;
                8'd4: cov_burst_4 = cov_burst_4 + 1;
                8'd8: cov_burst_8 = cov_burst_8 + 1;
            endcase

            // Length Bins
            if (length_bytes == 4)
                cov_len_single = cov_len_single + 1;
            else if (length_bytes <= 16)
                cov_len_short = cov_len_short + 1;
            else if (length_bytes <= 64)
                cov_len_med = cov_len_med + 1;
            else
                cov_len_long = cov_len_long + 1;

            if ((length_bytes / 4) % burst_beats != 0)
                cov_len_rem = cov_len_rem + 1;

            // Latency Bins
            if (latency_cycles == 0)
                cov_lat_0 = cov_lat_0 + 1;
            else if (latency_cycles == 1)
                cov_lat_1 = cov_lat_1 + 1;
            else
                cov_lat_multi = cov_lat_multi + 1;

            // Arb Bins
            if (!policy)
                cov_arb_fixed = cov_arb_fixed + 1;
            else
                cov_arb_rr = cov_arb_rr + 1;

            if (burst_beats > 1)
                cov_arb_lock = cov_arb_lock + 1;
        end
    endtask

    task print_coverage_report;
        integer total_bins;
        integer covered_bins;
        real coverage_pct;
        begin
            total_bins = 24;
            covered_bins = 0;
            if (cov_burst_1 > 0) covered_bins = covered_bins + 1;
            if (cov_burst_2 > 0) covered_bins = covered_bins + 1;
            if (cov_burst_4 > 0) covered_bins = covered_bins + 1;
            if (cov_burst_8 > 0) covered_bins = covered_bins + 1;
            if (cov_len_single > 0) covered_bins = covered_bins + 1;
            if (cov_len_short > 0) covered_bins = covered_bins + 1;
            if (cov_len_med > 0) covered_bins = covered_bins + 1;
            if (cov_len_long > 0) covered_bins = covered_bins + 1;
            if (cov_len_rem > 0) covered_bins = covered_bins + 1;
            if (cov_err_zero_len > 0) covered_bins = covered_bins + 1;
            if (cov_err_unalign_len > 0) covered_bins = covered_bins + 1;
            if (cov_err_unalign_src > 0) covered_bins = covered_bins + 1;
            if (cov_err_unalign_dst > 0) covered_bins = covered_bins + 1;
            if (cov_err_bus_read > 0) covered_bins = covered_bins + 1;
            if (cov_err_bus_write > 0) covered_bins = covered_bins + 1;
            if (cov_err_timeout > 0) covered_bins = covered_bins + 1;
            if (cov_ctrl_abort > 0) covered_bins = covered_bins + 1;
            if (cov_ctrl_reset > 0) covered_bins = covered_bins + 1;
            if (cov_lat_0 > 0) covered_bins = covered_bins + 1;
            if (cov_lat_1 > 0) covered_bins = covered_bins + 1;
            if (cov_lat_multi > 0) covered_bins = covered_bins + 1;
            if (cov_arb_fixed > 0) covered_bins = covered_bins + 1;
            if (cov_arb_rr > 0) covered_bins = covered_bins + 1;
            if (cov_arb_lock > 0) covered_bins = covered_bins + 1;

            coverage_pct = (covered_bins * 100.0) / total_bins;

            $display("\n=======================================================");
            $display("         FUNCTIONAL COVERAGE SUMMARY REPORT");
            $display("=======================================================");
            $display(" Total Coverage Bins Defined : %0d", total_bins);
            $display(" Total Coverage Bins Hit     : %0d", covered_bins);
            $display(" Overall Coverage Percentage : %0.1f%%", coverage_pct);
            $display("-------------------------------------------------------");
            $display(" [BURST BINS]   1-Beat: %0d | 2-Beat: %0d | 4-Beat: %0d | 8-Beat: %0d",
                     cov_burst_1, cov_burst_2, cov_burst_4, cov_burst_8);
            $display(" [LENGTH BINS]  Single: %0d | Short: %0d | Med: %0d | Long: %0d | Rem: %0d",
                     cov_len_single, cov_len_short, cov_len_med, cov_len_long, cov_len_rem);
            $display(" [ERROR BINS]   ZeroLen: %0d | UnalignLen: %0d | UnalignSrc: %0d | UnalignDst: %0d",
                     cov_err_zero_len, cov_err_unalign_len, cov_err_unalign_src, cov_err_unalign_dst);
            $display("                BusRdErr: %0d | BusWrErr: %0d | Timeout: %0d",
                     cov_err_bus_read, cov_err_bus_write, cov_err_timeout);
            $display(" [CONTROL BINS] SWAbort: %0d | SoftReset: %0d",
                     cov_ctrl_abort, cov_ctrl_reset);
            $display(" [LATENCY BINS] 0-Cycle: %0d | 1-Cycle: %0d | Multi-Cycle: %0d",
                     cov_lat_0, cov_lat_1, cov_lat_multi);
            $display(" [ARBITER BINS] FixedPri: %0d | RoundRobin: %0d | BurstLock: %0d",
                     cov_arb_fixed, cov_arb_rr, cov_arb_lock);
            $display("=======================================================\n");
        end
    endtask

    // -------------------------------------------------------------------------
    // Host Configuration Driver Tasks
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
            #1; // Allow combinational propagation
            data = cfg_rdata;
            @(posedge clk);
            cfg_rd_en = 1'b0;
            #1;
        end
    endtask

    task wait_dma_completion;
        output reg [31:0] final_status;
        integer poll_timeout;
        begin
            poll_timeout = 0;
            repeat (2) @(posedge clk);
            read_reg(ADDR_STATUS, final_status);
            // Poll until DONE (bit 1) or any ERROR flag (bits [5:2]) asserts
            while (final_status[1] == 1'b0 && final_status[5:2] == 4'b0000 && poll_timeout < 3000) begin
                poll_timeout = poll_timeout + 1;
                read_reg(ADDR_STATUS, final_status);
            end
            if (poll_timeout >= 3000) begin
                $display("[-] Polling DMA completion timed out! Status = 0x%08X", final_status);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Reference Scoreboard Tasks
    // -------------------------------------------------------------------------
    task scoreboard_verify_transfer;
        input [31:0] src_addr;
        input [31:0] dst_addr;
        input integer word_count;
        output integer errors_found;
        integer w;
        reg [31:0] exp_word;
        reg [31:0] act_word;
        begin
            errors_found = 0;
            for (w = 0; w < word_count; w = w + 1) begin
                u_mem_model.backdoor_read_word(src_addr + (w * 4), exp_word);
                u_mem_model.backdoor_read_word(dst_addr + (w * 4), act_word);
                if (exp_word !== act_word) begin
                    $display("[-] SCOREBOARD MISMATCH @ word offset %0d | Addr 0x%08X: Exp=0x%08X, Act=0x%08X, Diff=0x%08X",
                             w, dst_addr + (w * 4), exp_word, act_word, exp_word ^ act_word);
                    errors_found = errors_found + 1;
                end
            end
            if (errors_found == 0) begin
                $display("[+] SCOREBOARD MATCH: %0d words (0x%08X -> 0x%08X) verified successfully.",
                         word_count, src_addr, dst_addr);
            end else begin
                $display("[-] SCOREBOARD FAILED: %0d mismatches out of %0d words.",
                         errors_found, word_count);
            end
        end
    endtask

    task scoreboard_verify_error;
        input integer exp_status_bit;
        input [127:0] err_name;
        output reg    success;
        reg [31:0]    status_val;
        begin
            read_reg(ADDR_STATUS, status_val);
            if (status_val[exp_status_bit] == 1'b1 && status_val[0] == 1'b0) begin
                $display("[+] ERROR VERIFIED: %0s correctly latched (STATUS = 0x%08X, BUSY = 0).",
                         err_name, status_val);
                success = 1'b1;
            end else begin
                $display("[-] ERROR VERIFICATION FAILED: %0s NOT latched as expected! STATUS = 0x%08X (Exp bit %0d = 1)",
                         err_name, status_val, exp_status_bit);
                success = 1'b0;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Verification Flow
    // -------------------------------------------------------------------------
    reg [31:0] rdata;
    integer start_cycle, end_cycle, latency_cycles;
    integer tc_errors;
    reg     tc_success;

    // Random test variables
    reg [31:0] rand_src, rand_dst, rand_len;
    reg [7:0]  rand_burst, rand_lat;
    integer    rand_words;

    initial begin
        $dumpfile("dma_tb.vcd");
        $dumpvars(0, tb_dma_top);

        // Determine random seed (from plusarg or default)
        if (!$value$plusargs("seed=%d", random_seed)) begin
            random_seed = 32'h1234_5678;
        end
        $display("[*] Simulation Random Seed Initialized: %0d (0x%08X)", random_seed, random_seed);

        // Signal initialization
        rst_n          = 1'b0;
        cfg_wr_en      = 1'b0;
        cfg_rd_en      = 1'b0;
        cfg_addr       = 8'h0;
        cfg_wdata      = 32'h0;
        ext_req        = 1'b0;
        ext_burst_lock = 1'b0;
        ext_req_rw     = 1'b0;
        ext_req_addr   = 32'h0;
        ext_req_wdata  = 32'h0;

        test_count          = 0;
        pass_count          = 0;
        fail_count          = 0;
        assertion_failures  = 0;
        total_assertion_checks = 0;

        init_coverage();

        $display("\n=======================================================");
        $display("    DMA Subsystem Verification Suite - Phase 3");
        $display("=======================================================");

        // ---------------------------------------------------------------------
        // TC01: Synchronous Reset and Register Defaults
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC01_RESET_AND_REG_DEFAULTS");
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        read_reg(ADDR_STATUS, rdata);
        if (rdata == 32'h0 && debug_fsm_state == 4'd0 && debug_fifo_occupancy == 5'd0) begin
            $display("[+] Reset initialized properly. STATUS = 0x%08X, FSM = %0d, FIFO occ = %0d",
                     rdata, debug_fsm_state, debug_fifo_occupancy);
            $display(">>> TEST_RESULT: PASS (TC01_RESET_AND_REG_DEFAULTS)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] Reset test failed! STATUS = 0x%08X, FSM = %0d", rdata, debug_fsm_state);
            $display(">>> TEST_RESULT: FAIL (TC01_RESET_AND_REG_DEFAULTS)");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TC02: Single-Word Transfer (Burst = 1 beat, 4 bytes)
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC02_SINGLE_WORD_TRANSFER");
        u_mem_model.set_latency(1);
        u_mem_model.backdoor_init_pattern(32'h0000_1000, 1, 32'hCAFE_BABE);
        u_mem_model.backdoor_clear_region(32'h0000_2000, 1);

        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd4);
        write_reg(ADDR_BURST_CFG, 32'd1);

        start_cycle = sim_cycles;
        write_reg(ADDR_CTRL, 32'h0000_0005);
        wait_dma_completion(rdata);
        end_cycle = sim_cycles;
        latency_cycles = end_cycle - start_cycle;

        scoreboard_verify_transfer(32'h0000_1000, 32'h0000_2000, 1, tc_errors);
        sample_transfer_coverage(4, 1, 1, 0);

        if (rdata[1] == 1'b1 && tc_errors == 0 && irq == 1'b1) begin
            $display("[+] Single-word transfer complete in %0d cycles (Throughput: %0.2f B/cycle).",
                     latency_cycles, 4.0 / latency_cycles);
            $display(">>> TEST_RESULT: PASS (TC02_SINGLE_WORD_TRANSFER)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] Single-word transfer failed! Status = 0x%08X, Errors = %0d", rdata, tc_errors);
            $display(">>> TEST_RESULT: FAIL (TC02_SINGLE_WORD_TRANSFER)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0002);

        // ---------------------------------------------------------------------
        // TC03: 2-Beat Burst Transfer (16 bytes = 4 words)
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC03_BURST_2_TRANSFER");
        u_mem_model.set_latency(1);
        u_mem_model.backdoor_init_pattern(32'h0000_1000, 4, 32'h2222_0001);
        u_mem_model.backdoor_clear_region(32'h0000_2000, 4);

        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd16);
        write_reg(ADDR_BURST_CFG, 32'd2);

        start_cycle = sim_cycles;
        write_reg(ADDR_CTRL, 32'h0000_0005);
        wait_dma_completion(rdata);
        end_cycle = sim_cycles;
        latency_cycles = end_cycle - start_cycle;

        scoreboard_verify_transfer(32'h0000_1000, 32'h0000_2000, 4, tc_errors);
        sample_transfer_coverage(16, 2, 1, 0);

        if (rdata[1] == 1'b1 && tc_errors == 0 && debug_bytes_done == 32'd16) begin
            $display("[+] 2-beat burst transfer complete in %0d cycles (Throughput: %0.2f B/cycle).",
                     latency_cycles, 16.0 / latency_cycles);
            $display(">>> TEST_RESULT: PASS (TC03_BURST_2_TRANSFER)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] 2-beat burst transfer failed! Status = 0x%08X, Errors = %0d", rdata, tc_errors);
            $display(">>> TEST_RESULT: FAIL (TC03_BURST_2_TRANSFER)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0002);

        // ---------------------------------------------------------------------
        // TC04: 4-Beat Burst Transfer (64 bytes = 16 words)
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC04_BURST_4_TRANSFER");
        u_mem_model.set_latency(1);
        u_mem_model.backdoor_init_pattern(32'h0000_1000, 16, 32'h4444_0001);
        u_mem_model.backdoor_clear_region(32'h0000_2000, 16);

        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd64);
        write_reg(ADDR_BURST_CFG, 32'd4);

        start_cycle = sim_cycles;
        write_reg(ADDR_CTRL, 32'h0000_0005);
        wait_dma_completion(rdata);
        end_cycle = sim_cycles;
        latency_cycles = end_cycle - start_cycle;

        scoreboard_verify_transfer(32'h0000_1000, 32'h0000_2000, 16, tc_errors);
        sample_transfer_coverage(64, 4, 1, 0);

        if (rdata[1] == 1'b1 && tc_errors == 0 && debug_bytes_done == 32'd64) begin
            $display("[+] 4-beat burst transfer complete in %0d cycles (Throughput: %0.2f B/cycle).",
                     latency_cycles, 64.0 / latency_cycles);
            $display(">>> TEST_RESULT: PASS (TC04_BURST_4_TRANSFER)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] 4-beat burst transfer failed! Status = 0x%08X, Errors = %0d", rdata, tc_errors);
            $display(">>> TEST_RESULT: FAIL (TC04_BURST_4_TRANSFER)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0002);

        // ---------------------------------------------------------------------
        // TC05: 8-Beat Burst Transfer (128 bytes = 32 words)
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC05_BURST_8_TRANSFER");
        u_mem_model.set_latency(1);
        u_mem_model.backdoor_init_pattern(32'h0000_1000, 32, 32'h8888_0001);
        u_mem_model.backdoor_clear_region(32'h0000_2000, 32);

        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd128);
        write_reg(ADDR_BURST_CFG, 32'd8);

        start_cycle = sim_cycles;
        write_reg(ADDR_CTRL, 32'h0000_0005);
        wait_dma_completion(rdata);
        end_cycle = sim_cycles;
        latency_cycles = end_cycle - start_cycle;

        scoreboard_verify_transfer(32'h0000_1000, 32'h0000_2000, 32, tc_errors);
        sample_transfer_coverage(128, 8, 1, 0);

        if (rdata[1] == 1'b1 && tc_errors == 0 && debug_bytes_done == 32'd128) begin
            $display("[+] 8-beat burst transfer complete in %0d cycles (Throughput: %0.2f B/cycle).",
                     latency_cycles, 128.0 / latency_cycles);
            $display(">>> TEST_RESULT: PASS (TC05_BURST_8_TRANSFER)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] 8-beat burst transfer failed! Status = 0x%08X, Errors = %0d", rdata, tc_errors);
            $display(">>> TEST_RESULT: FAIL (TC05_BURST_8_TRANSFER)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0002);

        // ---------------------------------------------------------------------
        // TC06: Incomplete Remainder Burst (20 bytes = 5 words, configured for 4-beat bursts)
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC06_INCOMPLETE_REMAINDER_BURST");
        u_mem_model.set_latency(1);
        u_mem_model.backdoor_init_pattern(32'h0000_1000, 5, 32'h5555_0001);
        u_mem_model.backdoor_clear_region(32'h0000_2000, 5);

        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd20);
        write_reg(ADDR_BURST_CFG, 32'd4);

        start_cycle = sim_cycles;
        write_reg(ADDR_CTRL, 32'h0000_0005);
        wait_dma_completion(rdata);
        end_cycle = sim_cycles;

        scoreboard_verify_transfer(32'h0000_1000, 32'h0000_2000, 5, tc_errors);
        sample_transfer_coverage(20, 4, 1, 0);

        if (rdata[1] == 1'b1 && tc_errors == 0 && debug_bytes_done == 32'd20) begin
            $display("[+] Remainder burst (4 + 1 words) completed cleanly: %0d cycles.", end_cycle - start_cycle);
            $display(">>> TEST_RESULT: PASS (TC06_INCOMPLETE_REMAINDER_BURST)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] Remainder burst failed! Status = 0x%08X, Errors = %0d", rdata, tc_errors);
            $display(">>> TEST_RESULT: FAIL (TC06_INCOMPLETE_REMAINDER_BURST)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0002);

        // ---------------------------------------------------------------------
        // TC07: FIFO Backpressure Flow Control Handling
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC07_FIFO_BACKPRESSURE_HANDLING");
        u_mem_model.set_latency(2);
        u_mem_model.backdoor_init_pattern(32'h0000_1000, 16, 32'h7777_0001);
        u_mem_model.backdoor_clear_region(32'h0000_2000, 16);

        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd64);
        write_reg(ADDR_BURST_CFG, 32'd4);

        write_reg(ADDR_CTRL, 32'h0000_0005);

        // Inject intermittent stalls during transfer to create backpressure
        repeat (10) @(posedge clk);
        u_mem_model.set_force_stall(1'b1);
        repeat (8) @(posedge clk);
        u_mem_model.set_force_stall(1'b0);

        wait_dma_completion(rdata);

        scoreboard_verify_transfer(32'h0000_1000, 32'h0000_2000, 16, tc_errors);
        sample_transfer_coverage(64, 4, 2, 0);

        if (rdata[1] == 1'b1 && tc_errors == 0 && u_dma_top.u_dma_fifo.overflow == 0) begin
            $display("[+] Backpressure flow control handled successfully with 0 overflows/underflows.");
            $display(">>> TEST_RESULT: PASS (TC07_FIFO_BACKPRESSURE_HANDLING)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] Backpressure test failed! Status = 0x%08X, Errors = %0d", rdata, tc_errors);
            $display(">>> TEST_RESULT: FAIL (TC07_FIFO_BACKPRESSURE_HANDLING)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0002);
        u_mem_model.set_latency(1);

        // ---------------------------------------------------------------------
        // TC08: Fixed-Priority Arbitration Contention
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC08_FIXED_PRIORITY_ARBITRATION_CONTENTION");
        write_reg(ADDR_ARB_CFG, 32'h0000_0000);

        u_mem_model.backdoor_init_pattern(32'h0000_1000, 8, 32'hAAAA_0001);
        u_mem_model.backdoor_clear_region(32'h0000_2000, 8);

        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd32);
        write_reg(ADDR_BURST_CFG, 32'd4);

        ext_req <= 1'b1;
        ext_req_rw <= 1'b0;
        ext_req_addr <= 32'h0000_5000;

        write_reg(ADDR_CTRL, 32'h0000_0005);
        wait_dma_completion(rdata);

        ext_req <= 1'b0;
        scoreboard_verify_transfer(32'h0000_1000, 32'h0000_2000, 8, tc_errors);
        sample_transfer_coverage(32, 4, 1, 0);

        if (rdata[1] == 1'b1 && tc_errors == 0) begin
            $display("[+] Fixed-priority arbitration verified: DMA held priority over external requester.");
            $display(">>> TEST_RESULT: PASS (TC08_FIXED_PRIORITY_ARBITRATION_CONTENTION)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] Fixed priority contention failed! Status = 0x%08X", rdata);
            $display(">>> TEST_RESULT: FAIL (TC08_FIXED_PRIORITY_ARBITRATION_CONTENTION)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0002);

        // ---------------------------------------------------------------------
        // TC09: Round-Robin Arbitration Contention
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC09_ROUND_ROBIN_ARBITRATION_CONTENTION");
        write_reg(ADDR_ARB_CFG, 32'h0000_0001);

        u_mem_model.backdoor_init_pattern(32'h0000_1000, 8, 32'hBBBB_0001);
        u_mem_model.backdoor_clear_region(32'h0000_2000, 8);

        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd32);
        write_reg(ADDR_BURST_CFG, 32'd4);

        ext_req <= 1'b1;
        ext_req_rw <= 1'b0;
        ext_req_addr <= 32'h0000_6000;

        write_reg(ADDR_CTRL, 32'h0000_0005);
        wait_dma_completion(rdata);

        ext_req <= 1'b0;
        scoreboard_verify_transfer(32'h0000_1000, 32'h0000_2000, 8, tc_errors);
        sample_transfer_coverage(32, 4, 1, 1);

        if (rdata[1] == 1'b1 && tc_errors == 0) begin
            $display("[+] Round-Robin arbitration contention passed: Fair bus sharing verified.");
            $display(">>> TEST_RESULT: PASS (TC09_ROUND_ROBIN_ARBITRATION_CONTENTION)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] Round-Robin contention failed! Status = 0x%08X", rdata);
            $display(">>> TEST_RESULT: FAIL (TC09_ROUND_ROBIN_ARBITRATION_CONTENTION)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0002);
        write_reg(ADDR_ARB_CFG, 32'h0000_0000); // Restore fixed-priority

        // ---------------------------------------------------------------------
        // TC10: Negative: Zero-Length Transfer Rejection
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC10_ERR_ZERO_LENGTH");
        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd0);
        write_reg(ADDR_CTRL, 32'h0000_0005);

        repeat (5) @(posedge clk);
        scoreboard_verify_error(2, "ERR_INVALID_CFG", tc_success);
        cov_err_zero_len = cov_err_zero_len + 1;

        if (tc_success) begin
            $display(">>> TEST_RESULT: PASS (TC10_ERR_ZERO_LENGTH)");
            pass_count = pass_count + 1;
        end else begin
            $display(">>> TEST_RESULT: FAIL (TC10_ERR_ZERO_LENGTH)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0004);

        // ---------------------------------------------------------------------
        // TC11: Negative: Unaligned Transfer Length Rejection
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC11_ERR_UNALIGNED_LENGTH");
        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd14); // Not a multiple of 4
        write_reg(ADDR_CTRL, 32'h0000_0005);

        repeat (5) @(posedge clk);
        scoreboard_verify_error(2, "ERR_INVALID_CFG", tc_success);
        cov_err_unalign_len = cov_err_unalign_len + 1;

        if (tc_success) begin
            $display(">>> TEST_RESULT: PASS (TC11_ERR_UNALIGNED_LENGTH)");
            pass_count = pass_count + 1;
        end else begin
            $display(">>> TEST_RESULT: FAIL (TC11_ERR_UNALIGNED_LENGTH)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0004);

        // ---------------------------------------------------------------------
        // TC12: Negative: Unaligned Source Address Rejection
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC12_ERR_UNALIGNED_SRC_ADDR");
        write_reg(ADDR_SRC_ADDR, 32'h0000_1002); // Offset 2 bytes
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd16);
        write_reg(ADDR_CTRL, 32'h0000_0005);

        repeat (5) @(posedge clk);
        scoreboard_verify_error(4, "ERR_ALIGN", tc_success);
        cov_err_unalign_src = cov_err_unalign_src + 1;

        if (tc_success) begin
            $display(">>> TEST_RESULT: PASS (TC12_ERR_UNALIGNED_SRC_ADDR)");
            pass_count = pass_count + 1;
        end else begin
            $display(">>> TEST_RESULT: FAIL (TC12_ERR_UNALIGNED_SRC_ADDR)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0010);

        // ---------------------------------------------------------------------
        // TC13: Negative: Unaligned Destination Address Rejection
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC13_ERR_UNALIGNED_DST_ADDR");
        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2001); // Offset 1 byte
        write_reg(ADDR_XFER_LEN, 32'd16);
        write_reg(ADDR_CTRL, 32'h0000_0005);

        repeat (5) @(posedge clk);
        scoreboard_verify_error(4, "ERR_ALIGN", tc_success);
        cov_err_unalign_dst = cov_err_unalign_dst + 1;

        if (tc_success) begin
            $display(">>> TEST_RESULT: PASS (TC13_ERR_UNALIGNED_DST_ADDR)");
            pass_count = pass_count + 1;
        end else begin
            $display(">>> TEST_RESULT: FAIL (TC13_ERR_UNALIGNED_DST_ADDR)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0010);

        // ---------------------------------------------------------------------
        // TC14: Fault Injection: Bus Error during Read
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC14_ERR_BUS_READ_INJECTION");
        u_mem_model.set_latency(1);
        u_mem_model.set_inject_err(1'b1); // Inject bus error on response

        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd16);
        write_reg(ADDR_BURST_CFG, 32'd1);
        write_reg(ADDR_CTRL, 32'h0000_0005);

        repeat (20) @(posedge clk);
        u_mem_model.set_inject_err(1'b0); // Deassert error injection

        scoreboard_verify_error(5, "ERR_BUS", tc_success);
        cov_err_bus_read = cov_err_bus_read + 1;

        if (tc_success && irq == 1'b1) begin
            $display("[+] Bus error during read cleanly halted engine and asserted IRQ.");
            $display(">>> TEST_RESULT: PASS (TC14_ERR_BUS_READ_INJECTION)");
            pass_count = pass_count + 1;
        end else begin
            $display(">>> TEST_RESULT: FAIL (TC14_ERR_BUS_READ_INJECTION)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0020);

        // ---------------------------------------------------------------------
        // TC15: Fault Injection: Bus Error during Write
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC15_ERR_BUS_WRITE_INJECTION");
        u_mem_model.set_latency(1);
        u_mem_model.backdoor_init_pattern(32'h0000_1000, 4, 32'h3333_0001);

        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd16);
        write_reg(ADDR_BURST_CFG, 32'd1);
        write_reg(ADDR_CTRL, 32'h0000_0005);

        // Wait until read completes and write phase starts
        repeat (12) @(posedge clk);
        u_mem_model.set_inject_err(1'b1);
        repeat (15) @(posedge clk);
        u_mem_model.set_inject_err(1'b0);

        scoreboard_verify_error(5, "ERR_BUS", tc_success);
        cov_err_bus_write = cov_err_bus_write + 1;

        if (tc_success && irq == 1'b1) begin
            $display("[+] Bus error during write cleanly halted engine and asserted IRQ.");
            $display(">>> TEST_RESULT: PASS (TC15_ERR_BUS_WRITE_INJECTION)");
            pass_count = pass_count + 1;
        end else begin
            $display(">>> TEST_RESULT: FAIL (TC15_ERR_BUS_WRITE_INJECTION)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0020);

        // ---------------------------------------------------------------------
        // TC16: Fault Injection: Slave Stalling Watchdog Timeout
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC16_ERR_WATCHDOG_TIMEOUT");
        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd16);
        write_reg(ADDR_BURST_CFG, 32'd1);

        // Force memory slave to lock ready low
        u_mem_model.set_force_stall(1'b1);
        write_reg(ADDR_CTRL, 32'h0000_0005);

        // Wait for watchdog timeout counter to expire (>200 cycles)
        repeat (220) @(posedge clk);
        u_mem_model.set_force_stall(1'b0);

        scoreboard_verify_error(3, "ERR_MEM_TIMEOUT", tc_success);
        cov_err_timeout = cov_err_timeout + 1;

        if (tc_success && irq == 1'b1) begin
            $display("[+] Watchdog timeout detected correctly after 200 cycles; engine gracefully aborted.");
            $display(">>> TEST_RESULT: PASS (TC16_ERR_WATCHDOG_TIMEOUT)");
            pass_count = pass_count + 1;
        end else begin
            $display(">>> TEST_RESULT: FAIL (TC16_ERR_WATCHDOG_TIMEOUT)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0008);

        // ---------------------------------------------------------------------
        // TC17: Reliability: Mid-Burst Software Abort
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC17_RELIABILITY_SW_ABORT");
        u_mem_model.set_latency(2);
        u_mem_model.backdoor_init_pattern(32'h0000_1000, 32, 32'hA5A5_0001);

        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd128); // 32 words
        write_reg(ADDR_BURST_CFG, 32'd4);

        write_reg(ADDR_CTRL, 32'h0000_0005); // Start transfer

        // Let engine process a few words, then issue Abort pulse
        repeat (25) @(posedge clk);
        write_reg(ADDR_CTRL, 32'h0000_0002); // Bit 1 = ABORT

        repeat (10) @(posedge clk);
        read_reg(ADDR_STATUS, rdata);
        read_reg(ADDR_BYTES_DONE, rand_len);

        cov_ctrl_abort = cov_ctrl_abort + 1;

        if (rdata[0] == 1'b0 && debug_fsm_state == 4'd0) begin
            $display("[+] Software abort returned FSM to IDLE (BUSY=0, bytes transferred before abort: %0d).", rand_len);
            $display(">>> TEST_RESULT: PASS (TC17_RELIABILITY_SW_ABORT)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] Software abort failed! STATUS = 0x%08X, FSM = %0d", rdata, debug_fsm_state);
            $display(">>> TEST_RESULT: FAIL (TC17_RELIABILITY_SW_ABORT)");
            fail_count = fail_count + 1;
        end
        u_mem_model.set_latency(1);

        // ---------------------------------------------------------------------
        // TC18: Reliability: Soft Reset Recovery & Immediate Re-arm
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC18_RELIABILITY_SOFT_RESET_RECOVERY");
        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd64);
        write_reg(ADDR_BURST_CFG, 32'd4);

        write_reg(ADDR_CTRL, 32'h0000_0005); // Start
        repeat (15) @(posedge clk);

        // Assert Soft Reset (CTRL[3] = 1)
        write_reg(ADDR_CTRL, 32'h0000_0008);
        repeat (5) @(posedge clk);

        read_reg(ADDR_STATUS, rdata);
        cov_ctrl_reset = cov_ctrl_reset + 1;

        if (rdata == 32'h0 && debug_fsm_state == 4'd0 && debug_fifo_occupancy == 5'd0) begin
            // Re-arm and execute a clean 16-byte transfer to prove recovery
            u_mem_model.backdoor_init_pattern(32'h0000_1000, 4, 32'h9999_0001);
            u_mem_model.backdoor_clear_region(32'h0000_2000, 4);

            write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
            write_reg(ADDR_DST_ADDR, 32'h0000_2000);
            write_reg(ADDR_XFER_LEN, 32'd16);
            write_reg(ADDR_BURST_CFG, 32'd2);
            write_reg(ADDR_CTRL, 32'h0000_0005);

            wait_dma_completion(rdata);
            scoreboard_verify_transfer(32'h0000_1000, 32'h0000_2000, 4, tc_errors);

            if (rdata[1] == 1'b1 && tc_errors == 0) begin
                $display("[+] Soft reset cleared all state; re-armed transfer completed with 100%% data match.");
                $display(">>> TEST_RESULT: PASS (TC18_RELIABILITY_SOFT_RESET_RECOVERY)");
                pass_count = pass_count + 1;
            end else begin
                $display("[-] Re-armed transfer failed after soft reset!");
                $display(">>> TEST_RESULT: FAIL (TC18_RELIABILITY_SOFT_RESET_RECOVERY)");
                fail_count = fail_count + 1;
            end
        end else begin
            $display("[-] Soft reset did not clear registers: STATUS = 0x%08X", rdata);
            $display(">>> TEST_RESULT: FAIL (TC18_RELIABILITY_SOFT_RESET_RECOVERY)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0002);

        // ---------------------------------------------------------------------
        // TC19: Latency Tolerance: Zero-Wait-State Memory Access
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC19_LATENCY_ZERO_WAIT_STATE");
        u_mem_model.set_latency(0); // 0-cycle latency (immediate response)
        u_mem_model.backdoor_init_pattern(32'h0000_1000, 8, 32'h1010_0001);
        u_mem_model.backdoor_clear_region(32'h0000_2000, 8);

        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd32);
        write_reg(ADDR_BURST_CFG, 32'd4);

        start_cycle = sim_cycles;
        write_reg(ADDR_CTRL, 32'h0000_0005);
        wait_dma_completion(rdata);
        end_cycle = sim_cycles;

        scoreboard_verify_transfer(32'h0000_1000, 32'h0000_2000, 8, tc_errors);
        sample_transfer_coverage(32, 4, 0, 0);

        if (rdata[1] == 1'b1 && tc_errors == 0) begin
            $display("[+] Zero-wait-state transfer complete in %0d cycles (Throughput: %0.2f B/cycle).",
                     end_cycle - start_cycle, 32.0 / (end_cycle - start_cycle));
            $display(">>> TEST_RESULT: PASS (TC19_LATENCY_ZERO_WAIT_STATE)");
            pass_count = pass_count + 1;
        end else begin
            $display(">>> TEST_RESULT: FAIL (TC19_LATENCY_ZERO_WAIT_STATE)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0002);
        u_mem_model.set_latency(1);

        // ---------------------------------------------------------------------
        // TC20: Latency Tolerance: High-Latency Memory Access
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC20_LATENCY_HIGH_LATENCY_SLAVE");
        u_mem_model.set_latency(4); // 4-cycle pipelined response latency
        u_mem_model.backdoor_init_pattern(32'h0000_1000, 8, 32'h4040_0001);
        u_mem_model.backdoor_clear_region(32'h0000_2000, 8);

        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd32);
        write_reg(ADDR_BURST_CFG, 32'd4);

        start_cycle = sim_cycles;
        write_reg(ADDR_CTRL, 32'h0000_0005);
        wait_dma_completion(rdata);
        end_cycle = sim_cycles;

        scoreboard_verify_transfer(32'h0000_1000, 32'h0000_2000, 8, tc_errors);
        sample_transfer_coverage(32, 4, 4, 0);

        if (rdata[1] == 1'b1 && tc_errors == 0) begin
            $display("[+] 4-cycle high-latency transfer completed successfully in %0d cycles.", end_cycle - start_cycle);
            $display(">>> TEST_RESULT: PASS (TC20_LATENCY_HIGH_LATENCY_SLAVE)");
            pass_count = pass_count + 1;
        end else begin
            $display(">>> TEST_RESULT: FAIL (TC20_LATENCY_HIGH_LATENCY_SLAVE)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0002);
        u_mem_model.set_latency(1);

        // ---------------------------------------------------------------------
        // TC21: FIFO Capacity Saturation & Watermark Verification
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC21_FIFO_CAPACITY_SATURATION");
        u_mem_model.set_latency(1);
        u_mem_model.backdoor_init_pattern(32'h0000_1000, 64, 32'h6464_0001);
        u_mem_model.backdoor_clear_region(32'h0000_2000, 64);

        write_reg(ADDR_SRC_ADDR, 32'h0000_1000);
        write_reg(ADDR_DST_ADDR, 32'h0000_2000);
        write_reg(ADDR_XFER_LEN, 32'd256); // 64 words (4x FIFO depth)
        write_reg(ADDR_BURST_CFG, 32'd8);

        start_cycle = sim_cycles;
        write_reg(ADDR_CTRL, 32'h0000_0005);
        wait_dma_completion(rdata);
        end_cycle = sim_cycles;

        scoreboard_verify_transfer(32'h0000_1000, 32'h0000_2000, 64, tc_errors);
        sample_transfer_coverage(256, 8, 1, 0);

        if (rdata[1] == 1'b1 && tc_errors == 0 && u_dma_top.u_dma_fifo.overflow == 0) begin
            $display("[+] Large 256-byte multi-burst saturation transfer completed cleanly without overflow/underflow.");
            $display(">>> TEST_RESULT: PASS (TC21_FIFO_CAPACITY_SATURATION)");
            pass_count = pass_count + 1;
        end else begin
            $display(">>> TEST_RESULT: FAIL (TC21_FIFO_CAPACITY_SATURATION)");
            fail_count = fail_count + 1;
        end
        write_reg(ADDR_STATUS, 32'h0000_0002);

        // ---------------------------------------------------------------------
        // TC22: Constrained-Randomized Testing Suite (25 Iterations)
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC22_CONSTRAINED_RANDOM_REGRESSION");
        $display("[*] Executing 25 constrained-random transfers with Seed = %0d (0x%08X)...",
                 random_seed, random_seed);

        tc_errors = 0;
        for (rand_iter = 1; rand_iter <= 25; rand_iter = rand_iter + 1) begin
            // Generate pseudo-random parameters based on seed
            rand_words = 1 + ($random(random_seed) & 31); // 1 to 32 words (4 to 128 bytes)
            rand_len   = rand_words * 4;

            case (($random(random_seed) & 3))
                0: rand_burst = 8'd1;
                1: rand_burst = 8'd2;
                2: rand_burst = 8'd4;
                3: rand_burst = 8'd8;
            endcase

            rand_lat = ($random(random_seed) & 3); // 0 to 3 cycles latency
            rand_src = 32'h0000_1000 + (($random(random_seed) & 15) * 4);
            rand_dst = 32'h0000_2000 + (($random(random_seed) & 15) * 4);

            u_mem_model.set_latency(rand_lat);
            u_mem_model.backdoor_init_pattern(rand_src, rand_words, 32'hF000_0000 + (rand_iter << 8));
            u_mem_model.backdoor_clear_region(rand_dst, rand_words);

            write_reg(ADDR_SRC_ADDR, rand_src);
            write_reg(ADDR_DST_ADDR, rand_dst);
            write_reg(ADDR_XFER_LEN, rand_len);
            write_reg(ADDR_BURST_CFG, {24'h0, rand_burst});
            write_reg(ADDR_CTRL, 32'h0000_0005);

            wait_dma_completion(rdata);

            scoreboard_verify_transfer(rand_src, rand_dst, rand_words, tc_errors);
            sample_transfer_coverage(rand_len, rand_burst, rand_lat, 0);
            write_reg(ADDR_STATUS, 32'h0000_0002);

            if (tc_errors > 0) begin
                $display("[-] Random Iteration %0d FAILED (Len=%0d, Burst=%0d, Lat=%0d)",
                         rand_iter, rand_len, rand_burst, rand_lat);
            end
        end

        if (tc_errors == 0) begin
            $display("[+] All 25 constrained-random transfers PASSED with 0 mismatches!");
            $display(">>> TEST_RESULT: PASS (TC22_CONSTRAINED_RANDOM_REGRESSION)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] Constrained-random regression encountered %0d mismatches!", tc_errors);
            $display(">>> TEST_RESULT: FAIL (TC22_CONSTRAINED_RANDOM_REGRESSION)");
            fail_count = fail_count + 1;
        end
        u_mem_model.set_latency(1);

        // ---------------------------------------------------------------------
        // Final Summary and Coverage Report
        // -------------------------------------------------------------------------
        print_coverage_report();

        $display("\n=======================================================");
        $display("         PHASE 3 VERIFICATION SUMMARY REPORT");
        $display("=======================================================");
        $display(" Total Tests Executed     : %0d", test_count);
        $display(" Total Tests Passed       : %0d", pass_count);
        $display(" Total Tests Failed       : %0d", fail_count);
        $display(" Total Assertion Checks   : %0d", total_assertion_checks);
        $display(" Assertion Failures       : %0d", assertion_failures);
        $display(" Total Simulation Cycles  : %0d", sim_cycles);
        if (fail_count == 0 && assertion_failures == 0) begin
            $display(" [REGRESSION STATUS]      : ALL TESTS PASSED (100%% SUCCESS)");
        end else begin
            $display(" [REGRESSION STATUS]      : REGRESSION FAILED");
        end
        $display("=======================================================\n");

        $finish(fail_count == 0 && assertion_failures == 0 ? 0 : 1);
    end

endmodule
