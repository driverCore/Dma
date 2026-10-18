# ==============================================================================
# Automated Quartus Prime Synthesis and Timing Script (Phase 9)
# Usage: quartus_sh -t quartus_synth.tcl
# ==============================================================================

package require ::quartus::project
package require ::quartus::flow
package require ::quartus::report
package require ::quartus::sta

puts "=========================================================="
puts "  AMD DMA Subsystem: Automated Quartus Synthesis Flow    "
puts "=========================================================="

set project_name "dma_top"

# Open or create project
if {[project_exists $project_name]} {
    project_open $project_name -current_revision
} else {
    project_new $project_name -overwrite
    set_global_assignment -name FAMILY "Cyclone V"
    set_global_assignment -name DEVICE 5CSXFC6D6F31C6
    set_global_assignment -name TOP_LEVEL_ENTITY dma_top
    set_global_assignment -name VERILOG_FILE ../rtl/dma_fifo.v
    set_global_assignment -name VERILOG_FILE ../rtl/dma_arbiter.v
    set_global_assignment -name VERILOG_FILE ../rtl/dma_top.v
    set_global_assignment -name SDC_FILE dma_constraints.sdc
}

# Run Full Compilation Flow (Analysis & Synthesis -> Fitter -> Timing Analysis)
puts "\n[+] Running Analysis & Synthesis (quartus_map)..."
execute_module -tool map

puts "\n[+] Running Fitter Placement & Routing (quartus_fit)..."
execute_module -tool fit

puts "\n[+] Running TimeQuest Static Timing Analysis (quartus_sta)..."
execute_module -tool sta

# Extract Resource Utilization from Compilation Report
load_report
puts "\n=========================================================="
puts "              SYNTHESIS UTILIZATION SUMMARY              "
puts "=========================================================="

set panel_name "Fitter||Fitter Summary"
set panel_id [get_report_panel_id $panel_name]
if {$panel_id != -1} {
    set num_rows [get_number_of_rows -name $panel_name]
    for {set i 0} {$i < $num_rows} {incr i} {
        set row_data [get_report_panel_row -name $panel_name -row $i]
        puts "  [lindex $row_data 0]: [lindex $row_data 1]"
    }
}

# Run STA and print slack
project_close
puts "\n[+] Synthesis flow completed successfully."
