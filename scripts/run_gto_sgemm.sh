#!/usr/bin/env bash
set -euo pipefail

repo=$(realpath "${1:?pass the patched Vortex checkout}")
tools=$(realpath "${2:?pass the RV32 toolchain directory}")
mkdir -p "${3:?pass a results directory}"
output=$(realpath "$3")

cd "$repo/build"
../configure --xlen=32 --tooldir="$tools"
export MAKEFLAGS=-j4
export SIMX_OOO_STATS=1 SIMX_OOO_REJECT_FIRST_BYPASS=0

for cores in 1 4; do
    export CONFIGS="-DVX_CFG_NUM_CORES=$cores"
    make -C tests/regression/sgemm > "$output/build-$cores.log" 2>&1
    for gto in 0 1; do
        for window in 0 1; do
            log="$output/sgemm-$cores-$gto-$window.log"
            SIMX_GTO=$gto SIMX_OOO_WINDOW=$window \
                ./ci/blackbox.sh --driver=simx --app=sgemm --args=-n16 > "$log" 2>&1
            grep -HF 'PASSED!' "$log"
            grep -HF 'PERF:' "$log"
        done
    done
done
