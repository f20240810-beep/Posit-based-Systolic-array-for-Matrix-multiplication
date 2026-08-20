## =============================================================================
## posit_systolic_top.xdc
##
## Minimal timing constraints for posit_systolic_top (top-level module).
## The 669 "TIMING-17 / not reached by a timing clock" warnings you saw
## happen because no clock was ever declared for `clk` - Vivado can't
## build a timing graph for a clock domain it doesn't know exists, so
## every register on that net (FSM state, a_matrix_reg, etc.) gets
## flagged. This file fixes that.
##
## 100 MHz (10 ns period) is a conservative starting point given the
## barrel shifters / priority encoders in the pack/unpack/fixed_to_posit8
## logic. After implementation, check the timing summary's WNS (Worst
## Negative Slack): if it's positive with margin to spare, you can
## tighten CLK_PERIOD_NS below and re-run; if it's negative, either relax
## the period or look at Report Timing for the critical path.
## =============================================================================

## Measured critical path (first pass, 10ns/100MHz attempt): WNS=-2.111ns,
## meaning actual critical-path delay ≈ 10 - (-2.111) = 12.111ns (~82 MHz
## max). 298/535 endpoints failed by a similar small margin, consistent
## with one repeated structural bottleneck (the barrel shifter + priority
## encoder chain in fixed_to_posit8.v / posit8_pack.v, instantiated once
## per PE x 9 PEs) rather than many unrelated issues.
##
## Set to 14ns (~71 MHz) here: ~1.9ns of margin over the measured 12.111ns
## path, enough to absorb the small shift in timing analysis Vivado does
## between synthesis-time estimate and a fully placed/routed run. If WNS
## is still negative after re-implementing, either relax further (try
## 15-16ns) or pipeline the bottleneck (see note in project README / ask
## for help - happy to add a pipeline register there).
create_clock -period 14.000 -name clk [get_ports clk]

## rst_n is asynchronous (used on the negedge-sensitive reset branches),
## so treat paths from it as false paths rather than timed against clk -
## avoids spurious "reset didn't meet setup/hold" style violations.
set_false_path -from [get_ports rst_n]

## If you assign a physical pin to clk (e.g. on a real board), uncomment
## and edit this to match your board's clock pin/voltage standard:
# set_property PACKAGE_PIN <PIN>   [get_ports clk]
# set_property IOSTANDARD  LVCMOS33 [get_ports clk]

## =============================================================================
## Bitstream DRC relaxation (NSTD-1 / UCIO-1)
##
## By default Vivado REFUSES to generate a bitstream unless every top-level
## port has both a specific IOSTANDARD and a physical package pin (LOC)
## assigned - because on real hardware, an unconstrained I/O standard can
## cause voltage mismatches that damage the board. Since this project has
## no target board yet (no real pins to assign), these checks are being
## downgraded from Error to Warning so implementation/bitstream generation
## can complete. This does NOT affect simulation, synthesis, timing, or
## utilization results in any way - it only affects whether a (currently
## meaningless, since there's no board to load it onto) bitstream file gets
## written.
##
## If you later target a real board: DELETE these two lines and instead add
## that board's actual PACKAGE_PIN / IOSTANDARD constraints (usually
## available as a vendor-provided master XDC, e.g. Digilent's for
## Basys3/Nexys/Zybo) for clk, rst_n, start, done, and the a/b/c matrix buses.
## =============================================================================
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
