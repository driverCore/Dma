// =============================================================================
// File: tb_dma_arbiter.v
// Module: tb_dma_arbiter
// Description: Standalone unit verification testbench for dma_arbiter.
//              Verifies Fixed-Priority and Round-Robin policies, burst locking,
//              starvation behavior, fairness ratio, and wait-cycle telemetry.
// Standard: IEEE 1364-2001 Verilog
// =============================================================================

`timescale 1ns / 1ps

module tb_dma_arbiter;

    parameter CLK_PERIOD = 10;
    parameter NUM_REQUESTERS = 2;

    reg                       clk;
    reg                       rst_n;
    reg                       cfg_policy;
    reg  [NUM_REQUESTERS-1:0] req;
    reg  [NUM_REQUESTERS-1:0] burst_lock;

    wire [NUM_REQUESTERS-1:0] grant;
    wire                      grant_valid;
    wire                      grant_id;

    wire [31:0]               wait_cycles_req0;
    wire [31:0]               wait_cycles_req1;
    wire [31:0]               grants_req0;
    wire [31:0]               grants_req1;

    integer test_count;
    integer pass_count;
    integer fail_count;
    integer i;
    integer rr_grants_req0_start, rr_grants_req1_start;
    integer rr_g0, rr_g1;

    // Clock Generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // DUT Instantiation
    dma_arbiter #(
        .NUM_REQUESTERS(NUM_REQUESTERS)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .cfg_policy      (cfg_policy),
        .req             (req),
        .burst_lock      (burst_lock),
        .grant           (grant),
        .grant_valid     (grant_valid),
        .grant_id        (grant_id),
        .wait_cycles_req0(wait_cycles_req0),
        .wait_cycles_req1(wait_cycles_req1),
        .grants_req0     (grants_req0),
        .grants_req1     (grants_req1)
    );

    initial begin
        $dumpfile("arbiter_tb.vcd");
        $dumpvars(0, tb_dma_arbiter);

        clk        = 1'b0;
        rst_n      = 1'b0;
        cfg_policy = 1'b0; // 0 = Fixed-Priority
        req        = 2'b00;
        burst_lock = 2'b00;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        $display("\n=======================================================");
        $display("     DMA Memory Arbiter Unit Verification Suite");
        $display("=======================================================");

        // ---------------------------------------------------------------------
        // TC01: Reset and Idle State
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC01_ARB_RESET_AND_IDLE");
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        if (grant == 2'b00 && grant_valid == 1'b0 && grants_req0 == 0 && grants_req1 == 0) begin
            $display("[+] Reset initialized properly: grant=2'b%02b, valid=%0b", grant, grant_valid);
            $display(">>> TEST_RESULT: PASS (TC01_ARB_RESET_AND_IDLE)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] Reset test failed! grant=2'b%02b, valid=%0b", grant, grant_valid);
            $display(">>> TEST_RESULT: FAIL (TC01_ARB_RESET_AND_IDLE)");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TC02: Single Requester Grants (Isolated)
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC02_ARB_ISOLATED_GRANTS");
        // Request 0 only
        req <= 2'b01;
        @(posedge clk);
        #1;
        if (grant == 2'b01 && grant_id == 1'b0 && grant_valid == 1'b1) begin
            $display("[+] Isolated Req 0 granted correctly.");
        end else begin
            $display("[-] Req 0 grant failed! grant=2'b%02b", grant);
        end
        req <= 2'b00;
        @(posedge clk);

        // Request 1 only
        req <= 2'b10;
        @(posedge clk);
        #1;
        if (grant == 2'b10 && grant_id == 1'b1 && grant_valid == 1'b1) begin
            $display("[+] Isolated Req 1 granted correctly.");
            $display(">>> TEST_RESULT: PASS (TC02_ARB_ISOLATED_GRANTS)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] Req 1 grant failed! grant=2'b%02b", grant);
            $display(">>> TEST_RESULT: FAIL (TC02_ARB_ISOLATED_GRANTS)");
            fail_count = fail_count + 1;
        end
        req <= 2'b00;
        @(posedge clk);

        // ---------------------------------------------------------------------
        // TC03: Fixed-Priority Simultaneous Contention
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC03_ARB_FIXED_PRIORITY_CONTENTION");
        cfg_policy <= 1'b0; // Fixed-Priority: 0 > 1
        req <= 2'b11; // Both asserting simultaneously
        @(posedge clk);
        #1;

        if (grant == 2'b01 && grant_id == 1'b0) begin
            $display("[+] Fixed priority resolved in favor of Req 0: grant=2'b%02b, id=%0d", grant, grant_id);
            $display(">>> TEST_RESULT: PASS (TC03_ARB_FIXED_PRIORITY_CONTENTION)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] Fixed priority failed! grant=2'b%02b (Exp: 2'b01)", grant);
            $display(">>> TEST_RESULT: FAIL (TC03_ARB_FIXED_PRIORITY_CONTENTION)");
            fail_count = fail_count + 1;
        end
        req <= 2'b00;
        @(posedge clk);

        // ---------------------------------------------------------------------
        // TC04: Fixed-Priority Starvation and Wait Telemetry
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC04_ARB_FIXED_PRIORITY_STARVATION");
        // Keep both requests asserted for 10 consecutive cycles under Fixed Priority
        req <= 2'b11;
        repeat (10) @(posedge clk);
        #1;

        if (grant == 2'b01 && wait_cycles_req1 >= 10) begin
            $display("[+] Req 1 starved as expected under fixed priority: wait_cycles_req1=%0d", wait_cycles_req1);
            $display(">>> TEST_RESULT: PASS (TC04_ARB_FIXED_PRIORITY_STARVATION)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] Starvation test failed: grant=2'b%02b, wait_cycles_req1=%0d", grant, wait_cycles_req1);
            $display(">>> TEST_RESULT: FAIL (TC04_ARB_FIXED_PRIORITY_STARVATION)");
            fail_count = fail_count + 1;
        end
        req <= 2'b00;
        @(posedge clk);

        // ---------------------------------------------------------------------
        // TC05: Round-Robin Fairness & Alternating Arbitration
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC05_ARB_ROUND_ROBIN_FAIRNESS");
        cfg_policy <= 1'b1; // Switch to Round-Robin
        @(posedge clk);

        rr_grants_req0_start = grants_req0;
        rr_grants_req1_start = grants_req1;

        // Perform 10 consecutive arbitration cycles with both requesting
        for (i = 0; i < 10; i = i + 1) begin
            req <= 2'b11;
            @(posedge clk);
            #1;
            // Deassert briefly between arbitration decisions to observe token rotation
            req <= 2'b00;
            @(posedge clk);
        end

        rr_g0 = grants_req0 - rr_grants_req0_start;
        rr_g1 = grants_req1 - rr_grants_req1_start;

        $display("[+] Round-Robin Grants over 10 rounds: Req 0 = %0d, Req 1 = %0d", rr_g0, rr_g1);
        if (rr_g0 == 5 && rr_g1 == 5) begin
            $display("[+] Perfect 50/50 round-robin fairness achieved!");
            $display(">>> TEST_RESULT: PASS (TC05_ARB_ROUND_ROBIN_FAIRNESS)");
            pass_count = pass_count + 1;
        end else if (rr_g0 >= 4 && rr_g1 >= 4) begin
            $display("[+] Balanced round-robin fairness verified.");
            $display(">>> TEST_RESULT: PASS (TC05_ARB_ROUND_ROBIN_FAIRNESS)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] Round-Robin fairness failed! Req0=%0d, Req1=%0d", rr_g0, rr_g1);
            $display(">>> TEST_RESULT: FAIL (TC05_ARB_ROUND_ROBIN_FAIRNESS)");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TC06: Burst Lock Non-Preemption
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC06_ARB_BURST_LOCK_NON_PREEMPTION");
        // Start Req 1 with burst lock
        cfg_policy <= 1'b0; // Fixed priority (Req 0 normally has priority)
        req        <= 2'b10;
        burst_lock <= 2'b10; // Req 1 locks the bus
        @(posedge clk);
        #1;

        if (grant == 2'b10) begin
            $display("[+] Req 1 acquired grant with burst_lock.");
        end

        // Now higher-priority Req 0 asserts while Req 1 holds lock!
        req <= 2'b11;
        repeat (5) @(posedge clk);
        #1;

        if (grant == 2'b10) begin
            $display("[+] Non-preemption verified: Req 1 held grant across 5 cycles despite Req 0 contention.");
        end else begin
            $display("[-] Premature preemption occurred! grant=2'b%02b", grant);
        end

        // Release lock
        burst_lock <= 2'b00;
        @(posedge clk);
        #1;

        if (grant == 2'b01) begin
            $display("[+] Upon lock release, higher-priority Req 0 immediately granted.");
            $display(">>> TEST_RESULT: PASS (TC06_ARB_BURST_LOCK_NON_PREEMPTION)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] Lock release transition failed! grant=2'b%02b", grant);
            $display(">>> TEST_RESULT: FAIL (TC06_ARB_BURST_LOCK_NON_PREEMPTION)");
            fail_count = fail_count + 1;
        end

        req        <= 2'b00;
        burst_lock <= 2'b00;
        repeat (3) @(posedge clk);

        // ---------------------------------------------------------------------
        // TC07: Request Withdrawal without Grant
        // ---------------------------------------------------------------------
        test_count = test_count + 1;
        $display("\n>>> TEST_START: TC07_ARB_REQUEST_WITHDRAWAL");
        // Req 0 is granted, Req 1 asserts then withdraws without getting grant
        req <= 2'b01;
        @(posedge clk);
        req <= 2'b11; // Req 1 requests but Req 0 holds grant
        @(posedge clk);
        req <= 2'b01; // Req 1 withdraws request
        @(posedge clk);
        req <= 2'b00; // Req 0 finishes
        @(posedge clk);
        #1;

        if (grant == 2'b00 && grant_valid == 1'b0) begin
            $display("[+] Request withdrawal handled cleanly; arbiter idle.");
            $display(">>> TEST_RESULT: PASS (TC07_ARB_REQUEST_WITHDRAWAL)");
            pass_count = pass_count + 1;
        end else begin
            $display("[-] Withdrawal failed! grant=2'b%02b", grant);
            $display(">>> TEST_RESULT: FAIL (TC07_ARB_REQUEST_WITHDRAWAL)");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------------
        $display("\n=======================================================");
        $display("          ARBITER UNIT VERIFICATION SUMMARY");
        $display("=======================================================");
        $display(" Total Tests Executed : %0d", test_count);
        $display(" Total Tests Passed   : %0d", pass_count);
        $display(" Total Tests Failed   : %0d", fail_count);
        if (fail_count == 0) begin
            $display(" [ARBITER REGRESSION] : ALL TESTS PASSED (100%% SUCCESS)");
        end else begin
            $display(" [ARBITER REGRESSION] : UNIT TEST FAILED");
        end
        $display("=======================================================\n");

        $finish(fail_count == 0 ? 0 : 1);
    end

endmodule
