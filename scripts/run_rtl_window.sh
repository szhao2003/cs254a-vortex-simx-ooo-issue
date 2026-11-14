#!/usr/bin/env bash
set -euo pipefail

output=${1:?pass an output directory}
lib=$(realpath "${2:?pass the Nangate45 Liberty path}")

src=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$output"
cd "$output"
obj_dir=$(mktemp -d /tmp/cs254a-rtl-build.XXXXXX)
trap 'rm -rf -- "$obj_dir"' EXIT
yosys=${YOSYS:-yosys}
verilator=${VERILATOR:-verilator}

"$verilator" --binary --timing --assert -j 4 --top-module issue_window_tb \
    --Mdir "$obj_dir" "$src/src/rtl/issue_window.sv" \
    "$src/tests/rtl/issue_window_tb.sv" > verilator.log 2>&1
"$obj_dir/Vissue_window_tb" | tee simulation.log
grep -q '^PASS:' simulation.log

for mode in 0 1; do
    "$yosys" -Q -p "read_verilog -sv \"$src/src/rtl/issue_window.sv\"; chparam -set OOO $mode issue_window; synth -top issue_window -flatten; dfflibmap -liberty \"$lib\"; abc -liberty \"$lib\"; stat -liberty \"$lib\"; write_verilog -noattr mapped-$mode.v" > "yosys-$mode.log"
    cat > "timing-$mode.tcl" <<EOF
read_liberty {$lib}
read_verilog mapped-$mode.v
link_design issue_window
create_clock -name clk -period 2.0 [get_ports clk]
set_input_delay -clock clk 0.1 [get_ports {reset push_valid push_regs* push_mask* push_kind* entry_ready* accept}]
set_output_delay -clock clk 0.1 [all_outputs]
set_load 0.005 [all_outputs]
report_checks -path_delay max -digits 4
exit
EOF
    "${STA:-sta}" -exit "timing-$mode.tcl" > "sta-$mode.log" 2>&1
    if grep -Eq '^(Error|Warning):' "sta-$mode.log"; then cat "sta-$mode.log"; exit 1; fi
    grep 'Chip area' "yosys-$mode.log"
    grep -E 'slack \((MET|VIOLATED)\)' "sta-$mode.log"
done
