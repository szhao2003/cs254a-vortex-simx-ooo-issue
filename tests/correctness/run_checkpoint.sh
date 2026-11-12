#!/usr/bin/env bash
set -euo pipefail

stock=${1:?pass the absolute path to the stock Vortex checkout}
patched=${2:?pass the absolute path to the patched Vortex checkout}
tools=${3:?pass the absolute path to the RV32 toolchain}
output=${4:?pass an output directory}
test_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
probe_dir="$test_dir/../../baseline/b0-probe"

export SIMX_OOO_STATS=1
export SIMX_OOO_REJECT_FIRST_BYPASS=0
bash "$probe_dir/run.sh" "$stock" "$tools" "$output/b0"
bash "$probe_dir/run.sh" "$patched" "$tools" "$output/b1" "$probe_dir/kernel.cpp" -n1 b1
bash "$probe_dir/run.sh" "$patched" "$tools" "$output/o4" "$probe_dir/kernel.cpp" -n1 o4
SIMX_OOO_REJECT_FIRST_BYPASS=1 bash "$probe_dir/run.sh" \
    "$patched" "$tools" "$output/retry" "$probe_dir/kernel.cpp" -n1 o4
python3 "$test_dir/check_retry.py" "$output" "$output/b0"

bash "$probe_dir/run.sh" "$patched" "$tools" "$output/hazards" "$test_dir/hazards.cpp" -n1 o4
bash "$probe_dir/run.sh" "$patched" "$tools" "$output/boundaries" "$test_dir/boundaries.cpp" -n8 o4
python3 "$test_dir/check_boundaries.py" "$output/boundaries"
