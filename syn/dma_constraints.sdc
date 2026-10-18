# ==============================================================================
# Synopsys Design Constraints (SDC) for DMA Subsystem (Phase 9)
# AMD Design / Performance Verification Engineering Lab
# Target Frequency: 100.0 MHz (Period: 10.000 ns, 50% Duty Cycle)
# ==============================================================================

# Set unit scale
set_time_unit -nanoseconds
set_time_precision -picoseconds

# ------------------------------------------------------------------------------
# 1. Primary Clock Definition
# ------------------------------------------------------------------------------
create_clock -name clk -period 10.000 -waveform {0.000 5.000} [get_ports {clk}]

# Set clock uncertainty (jitter + duty-cycle distortion)
set_clock_uncertainty -setup 0.200 [get_clocks {clk}]
set_clock_uncertainty -hold  0.100 [get_clocks {clk}]

# ------------------------------------------------------------------------------
# 2. Input Delay Constraints (Referenced to clk rising edge)
# Assuming 2.0ns external board delay for memory bus & host configuration
# ------------------------------------------------------------------------------
set_input_delay -clock clk -max 2.000 [get_ports {rst_n}]
set_input_delay -clock clk -min 0.500 [get_ports {rst_n}]

set_input_delay -clock clk -max 2.500 [get_ports {cfg_wr_en cfg_rd_en cfg_addr* cfg_wdata*}]
set_input_delay -clock clk -min 0.500 [get_ports {cfg_wr_en cfg_rd_en cfg_addr* cfg_wdata*}]

set_input_delay -clock clk -max 2.500 [get_ports {mem_req_ready mem_rsp_valid mem_rsp_rdata* mem_rsp_err}]
set_input_delay -clock clk -min 0.500 [get_ports {mem_req_ready mem_rsp_valid mem_rsp_rdata* mem_rsp_err}]

set_input_delay -clock clk -max 2.500 [get_ports {ext_req ext_burst_lock ext_req_rw ext_req_addr* ext_req_wdata*}]
set_input_delay -clock clk -min 0.500 [get_ports {ext_req ext_burst_lock ext_req_rw ext_req_addr* ext_req_wdata*}]

# ------------------------------------------------------------------------------
# 3. Output Delay Constraints (Referenced to clk rising edge)
# Assuming 2.0ns setup requirement on receiving slave/host device
# ------------------------------------------------------------------------------
set_output_delay -clock clk -max 2.500 [get_ports {cfg_rdata* irq}]
set_output_delay -clock clk -min 0.500 [get_ports {cfg_rdata* irq}]

set_output_delay -clock clk -max 2.500 [get_ports {mem_req_valid mem_req_rw mem_req_addr* mem_req_wdata* mem_rsp_ready}]
set_output_delay -clock clk -min 0.500 [get_ports {mem_req_valid mem_req_rw mem_req_addr* mem_req_wdata* mem_rsp_ready}]

set_output_delay -clock clk -max 2.500 [get_ports {ext_grant}]
set_output_delay -clock clk -min 0.500 [get_ports {ext_grant}]

# Debug telemetry probes are asynchronous observability outputs
set_false_path -to [get_ports {debug_fsm_state* debug_bytes_done* debug_fifo_occupancy* debug_arb_grant*}]

# ------------------------------------------------------------------------------
# 4. Asynchronous Reset Constraints
# ------------------------------------------------------------------------------
# rst_n is active-low asynchronous assertion with synchronous deassertion
set_false_path -from [get_ports {rst_n}] -to [all_registers]
