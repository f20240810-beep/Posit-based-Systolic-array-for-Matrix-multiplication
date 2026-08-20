## =============================================================================
## extract_reports.tcl
##
## Run this AFTER implementation completes (e.g. right after
## fmax_binary_search.tcl converges, or after any manual
## launch_runs...route_design). Dumps utilization, timing summary, and
## a baseline (vectorless) power report to text files in the current
## directory - the numbers you'll pull into your comparison table.
##
## USAGE: source vivado_scripts/extract_reports.tcl
## (assumes the run named in IMPL_RUN_NAME is already implemented/open,
##  or opens it if not)
## =============================================================================

set IMPL_RUN_NAME "impl_1"
set REPORT_PREFIX "report"  ;# output files: report_utilization.txt etc.

if {[catch {current_design}]} {
    open_run $IMPL_RUN_NAME
}

report_utilization -file "${REPORT_PREFIX}_utilization.txt"
report_utilization -hierarchical -file "${REPORT_PREFIX}_utilization_hierarchical.txt"

report_timing_summary -delay_type max -max_paths 10 -file "${REPORT_PREFIX}_timing_summary.txt"

# Vectorless (statistical) power - a quick baseline. For a defensible
# number in your writeup, use power_saif_flow.tcl instead (see that
# script's header for why vectorless estimates are weaker evidence).
report_power -file "${REPORT_PREFIX}_power_vectorless.txt"

puts "Reports written:"
puts "  ${REPORT_PREFIX}_utilization.txt"
puts "  ${REPORT_PREFIX}_utilization_hierarchical.txt"
puts "  ${REPORT_PREFIX}_timing_summary.txt"
puts "  ${REPORT_PREFIX}_power_vectorless.txt"
puts ""
puts "For LUT/FF/DSP/BRAM counts, see the 'Slice Logic' / 'DSP' / 'Memory'"
puts "sections of ${REPORT_PREFIX}_utilization.txt - copy those rows into"
puts "your comparison table (Vivado's utilization report API varies enough"
puts "across versions that a hardcoded Tcl parse here would be fragile;"
puts "the text report is the reliable source)."
