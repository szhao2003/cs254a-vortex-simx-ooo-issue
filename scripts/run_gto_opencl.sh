#!/usr/bin/env bash
set -euo pipefail

repo=$(realpath "${1:?pass the patched Vortex checkout}")
tools=$(realpath "${2:?pass the toolchain directory including POCL}")
mkdir -p "${3:?pass an output directory}"
output=$(realpath "$3")
cd "$repo/build"
../configure --xlen=32 --tooldir="$tools"
export MAKEFLAGS=-j4 SIMX_GTO=1 SIMX_OOO_STATS=1 SIMX_OOO_REJECT_FIRST_BYPASS=0

for cores in 1 4; do
    export CONFIGS="-DVX_CFG_NUM_CORES=$cores -DVX_CFG_NUM_WARPS=32 -DVX_CFG_NUM_THREADS=4"
    for app in sgemm sgemm2 sgemm3; do
        size=16
        if [[ $app == sgemm ]]; then size=32; fi
        for window in 0 1; do
            log="$output/$app-$cores-$window.log"
            SIMX_OOO_WINDOW=$window ./ci/blackbox.sh --driver=simx \
                --app="$PWD/tests/opencl/$app" --args="-n$size" > "$log" 2>&1
            grep -HE '^PERF: instrs=|PASS' "$log"
        done
    done
done
