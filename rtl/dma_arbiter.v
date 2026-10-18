// =============================================================================
// File: dma_arbiter.v
// Module: dma_arbiter
// Description: Multi-master shared resource arbiter supporting both
//              Fixed-Priority and Round-Robin arbitration policies,
//              burst transaction locking, fairness tracking, and cycle-accurate
//              contention wait-time telemetry counters.
// Standard: IEEE 1364-2001 Verilog Synthesizable RTL
// =============================================================================

`timescale 1ns / 1ps

module dma_arbiter #(
    parameter NUM_REQUESTERS = 2
) (
    input  wire                      clk,
    input  wire                      rst_n,

    // Arbitration Policy Configuration: 0 = Fixed-Priority (0 > 1), 1 = Round-Robin
    input  wire                      cfg_policy,

    // Requester Interface (Request and Burst Lock)
    input  wire [NUM_REQUESTERS-1:0] req,
    input  wire [NUM_REQUESTERS-1:0] burst_lock, // Held high during multi-beat bursts

    // Grant Interface
    output reg  [NUM_REQUESTERS-1:0] grant,
    output reg                       grant_valid,
    output reg                       grant_id,   // 0 or 1 for 2 requesters

    // Telemetry and Contention Performance Metrics
    output reg  [31:0]               wait_cycles_req0,
    output reg  [31:0]               wait_cycles_req1,
    output reg  [31:0]               grants_req0,
    output reg  [31:0]               grants_req1
);

    reg last_grant_id;
    wire is_locked = (grant[0] && burst_lock[0] && req[0]) ||
                     (grant[1] && burst_lock[1] && req[1]);

    always @(posedge clk) begin
        if (!rst_n) begin
            grant            <= {NUM_REQUESTERS{1'b0}};
            grant_valid      <= 1'b0;
            grant_id         <= 1'b0;
            last_grant_id    <= 1'b0;
            wait_cycles_req0 <= 32'd0;
            wait_cycles_req1 <= 32'd0;
            grants_req0      <= 32'd0;
            grants_req1      <= 32'd0;
        end else begin
            // -----------------------------------------------------------------
            // Contention Wait-Time Telemetry Tracking
            // -----------------------------------------------------------------
            if (req[0] && !grant[0])
                wait_cycles_req0 <= wait_cycles_req0 + 1'b1;
            if (req[1] && !grant[1])
                wait_cycles_req1 <= wait_cycles_req1 + 1'b1;

            // -----------------------------------------------------------------
            // Arbitration Logic
            // -----------------------------------------------------------------
            if (is_locked) begin
                // Maintain current grant while burst lock is active and request persists
                grant_valid <= 1'b1;
            end else begin
                if (!cfg_policy) begin
`ifdef BUG_ARBITER_STARVE
                    // Injected Bug: Priority inversion where Master 1 starves Master 0
                    if (req[1]) begin
                        grant            <= 2'b10;
                        grant_valid      <= 1'b1;
                        grant_id         <= 1'b1;
                        if (!grant[1])
                            grants_req1 <= grants_req1 + 1'b1;
                    end else if (req[0]) begin
                        grant            <= 2'b01;
                        grant_valid      <= 1'b1;
                        grant_id         <= 1'b0;
                        if (!grant[0])
                            grants_req0 <= grants_req0 + 1'b1;
                    end else begin
                        grant       <= 2'b00;
                        grant_valid <= 1'b0;
                    end
`else
                    // ---------------------------------------------------------
                    // Fixed-Priority: Requester 0 has strict priority over 1
                    // ---------------------------------------------------------
                    if (req[0]) begin
                        grant            <= 2'b01;
                        grant_valid      <= 1'b1;
                        grant_id         <= 1'b0;
                        if (!grant[0])
                            grants_req0 <= grants_req0 + 1'b1;
                    end else if (req[1]) begin
                        grant            <= 2'b10;
                        grant_valid      <= 1'b1;
                        grant_id         <= 1'b1;
                        if (!grant[1])
                            grants_req1 <= grants_req1 + 1'b1;
                    end else begin
                        grant       <= 2'b00;
                        grant_valid <= 1'b0;
                    end
`endif
                end else begin
                    // ---------------------------------------------------------
                    // Round-Robin: Alternating rotating priority token
                    // ---------------------------------------------------------
                    case (last_grant_id)
                        1'b0: begin
                            // Last granted was Req 0 -> Priority order: 1, then 0
                            if (req[1]) begin
                                grant         <= 2'b10;
                                grant_valid   <= 1'b1;
                                grant_id      <= 1'b1;
                                last_grant_id <= 1'b1;
                                if (!grant[1])
                                    grants_req1 <= grants_req1 + 1'b1;
                            end else if (req[0]) begin
                                grant         <= 2'b01;
                                grant_valid   <= 1'b1;
                                grant_id      <= 1'b0;
                                last_grant_id <= 1'b0;
                                if (!grant[0])
                                    grants_req0 <= grants_req0 + 1'b1;
                            end else begin
                                grant       <= 2'b00;
                                grant_valid <= 1'b0;
                            end
                        end

                        1'b1: begin
                            // Last granted was Req 1 -> Priority order: 0, then 1
                            if (req[0]) begin
                                grant         <= 2'b01;
                                grant_valid   <= 1'b0;
                                grant_id      <= 1'b0;
                                last_grant_id <= 1'b0;
                                grant_valid   <= 1'b1;
                                if (!grant[0])
                                    grants_req0 <= grants_req0 + 1'b1;
                            end else if (req[1]) begin
                                grant         <= 2'b10;
                                grant_valid   <= 1'b1;
                                grant_id      <= 1'b1;
                                last_grant_id <= 1'b1;
                                if (!grant[1])
                                    grants_req1 <= grants_req1 + 1'b1;
                            end else begin
                                grant       <= 2'b00;
                                grant_valid <= 1'b0;
                            end
                        end
                    endcase
                end
            end
        end
    end

endmodule
