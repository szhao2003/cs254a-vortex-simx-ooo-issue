#!/usr/bin/env bash
set -euo pipefail

repo=$(realpath "${1:?pass the patched Vortex checkout}")
tools=$(realpath "${2:?pass the RV32 toolchain directory}")
mkdir -p "${3:?pass a results directory}"
output=$(realpath "$3")
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

cd "$repo/build"
../configure --xlen=32 --tooldir="$tools"
export MAKEFLAGS=-j4 SIMX_GTO=1 SIMX_OOO_STATS=1 SIMX_OOO_REJECT_FIRST_BYPASS=0
python3 - "$script_dir/../tests/b0_probe/run_matrix.py" "$repo" <<'PY'
import runpy
import sys
from pathlib import Path

matrix = runpy.run_path(sys.argv[1])
app = matrix["stage_app"](Path(sys.argv[2]))
(app / "kernel.cpp").write_text(matrix["kernel_source"](4, 0))
PY

for cores in 1 4; do
    export CONFIGS="-DVX_CFG_NUM_CORES=$cores"
    for app in window_matrix sgemm; do
        args=-n16
        if [[ $app == window_matrix ]]; then args="-n64 -x4 -y1"; fi
        for window in 0 1; do
            for profile in 4 7; do
                log="$output/$app-$cores-$window-p$profile.log"
                SIMX_OOO_WINDOW=$window ./ci/blackbox.sh --driver=simx \
                    --app="$app" --args="$args" --perf="$profile" > "$log" 2>&1
                grep -q '^PASSED!' "$log"
                grep -q '^PERF: instrs=' "$log"
                if [[ $profile == 4 ]]; then
                    grep -q 'dcache:' "$log"
                else
                    grep -q 'memory: reqs=' "$log"
                fi
            done
        done
    done
done
