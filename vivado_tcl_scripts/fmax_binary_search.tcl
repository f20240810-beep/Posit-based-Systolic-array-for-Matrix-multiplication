## =============================================================================
## fmax_binary_search.tcl
##
## Finds each design's real Fmax by binary-searching the clock period:
## re-implement at successive periods until WNS crosses from positive to
## negative within a tolerance, rather than reporting a single guessed
## period's WNS. This is the standard methodology for a defensible
## cross-format Fmax comparison (a single-guess WNS, as in the earlier
## 10ns attempt, only tells you PASS/FAIL at that one point - not the
## design's actual limit).
##
## USAGE:
##   1. Open the project for the variant you're characterizing (e.g. the
##      Posit8 project with posit_systolic_top as the synthesis top).
##   2. Edit the CONFIG block below (project/run names, XDC path, search
##      bounds).
##   3. In the Tcl console: source vivado_scripts/fmax_binary_search.tcl
##   4. Read the final period/Fmax printed at the end, and the full
##      iteration log in fmax_search_log.csv (useful for a "convergence"
##      plot in your report if you want one).
##
## HOW IT WORKS: standard binary search over clock period. Each iteration
## rewrites the create_clock line in your XDC file to the candidate
## period, re-runs implementation from scratch (reset_run ensures no
## stale results), and reads WNS from the routed design. If WNS >= 0,
## that period is achievable - search faster (tighter) periods. If
## WNS < 0, search slower (looser) periods. Converges when the search
## window is smaller than PERIOD_TOLERANCE_NS.
## =============================================================================

# ---------------- CONFIG - edit these for your project ----------------
set IMPL_RUN_NAME       "impl_1"
set XDC_FILE_PATH       [file normalize "./posit_systolic_top.xdc"]  ;# path Vivado actually reads from
set SEARCH_LO_NS        4.0     ;# period we're confident WILL meet timing (fast lower bound is fine to start conservative)
set SEARCH_HI_NS        30.0    ;# period we're confident WILL NOT fail timing
set PERIOD_TOLERANCE_NS 0.1     ;# stop when search window is tighter than this
set MAX_ITERATIONS      12      ;# binary search converges in ceil(log2(range/tol)) - this is a safety cap
# ------------------------------------------------------------------------

proc set_clock_period {xdc_path period_ns} {
    set fh [open $xdc_path r]
    set content [read $fh]
    close $fh
    # Matches: create_clock -period <number> ...
    set new_content [regsub {create_clock\s+-period\s+[0-9.]+} $content \
                             "create_clock -period $period_ns"]
    set fh [open $xdc_path w]
    puts -nonewline $fh $new_content
    close $fh
}

proc get_wns_for_period {run_name xdc_path period_ns} {
    set_clock_period $xdc_path $period_ns
    reset_run $run_name
    launch_runs $run_name -to_step route_design -jobs 4
    wait_on_run $run_name

    set status [get_property STATUS [get_runs $run_name]]
    if {[string match "*ERROR*" $status] || [string match "*Failed*" $status]} {
        puts "WARNING: run failed at period=$period_ns ($status) - treating as failing timing"
        return -1000.0
    }

    open_run $run_name -name timing_check
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    close_design
    return $wns
}

# ---------------- Binary search ----------------
set log [open "fmax_search_log.csv" w]
puts $log "iteration,period_ns,wns_ns,pass"

set lo $SEARCH_LO_NS
set hi $SEARCH_HI_NS
set best_passing_period $hi
set iter 0

puts "Starting Fmax binary search: \[$lo ns, $hi ns\], tolerance=$PERIOD_TOLERANCE_NS ns"

while {[expr {$hi - $lo}] > $PERIOD_TOLERANCE_NS && $iter < $MAX_ITERATIONS} {
    set mid [expr {($lo + $hi) / 2.0}]
    puts "\n--- Iteration $iter: trying period = $mid ns ---"
    set wns [get_wns_for_period $IMPL_RUN_NAME $XDC_FILE_PATH $mid]
    set pass [expr {$wns >= 0.0}]
    puts "  WNS = $wns ns -> [expr {$pass ? {PASS} : {FAIL}}]"
    puts $log "$iter,$mid,$wns,$pass"
    flush $log

    if {$pass} {
        set best_passing_period $mid
        set hi $mid
    } else {
        set lo $mid
    }
    incr iter
}
close $log

set fmax_mhz [expr {1000.0 / $best_passing_period}]
puts "\n=============================================="
puts "Fmax search converged after $iter iterations."
puts "Best passing period found: $best_passing_period ns"
puts "Fmax ~= $fmax_mhz MHz"
puts "Full iteration log: fmax_search_log.csv"
puts "=============================================="

# Leave the XDC set to the best passing period and re-run once more so the
# project's final implemented state matches the reported Fmax.
set_clock_period $XDC_FILE_PATH $best_passing_period
reset_run $IMPL_RUN_NAME
launch_runs $IMPL_RUN_NAME -to_step route_design -jobs 4
wait_on_run $IMPL_RUN_NAME
puts "Project re-implemented at the converged period. Ready for utilization/power reports."
