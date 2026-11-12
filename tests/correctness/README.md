# Correctness tests on stock SimX

Both kernels use the stock demo's host-side result check.

- `hazards.cpp` puts RAW, WAR, and WAW register dependencies behind loads. The trace shows the instruction order, and the host checks the computed sums.
- `boundaries.cpp` uses two groups of lanes with different masks. One path places an independent XOR behind a store, and the other gives that XOR room to issue early once the window is enabled.

Run these commands from the repository root after building the stock demo. Replace the two paths with your Vortex checkout and RV32 toolchain directories.

```bash
vortex=/path/to/vortex-baseline
tools=/path/to/vortex-tools-v3.0.1
bash baseline/b0-probe/run.sh "$vortex" "$tools" ./b0-results/hazards tests/correctness/hazards.cpp -n1
bash baseline/b0-probe/run.sh "$vortex" "$tools" ./b0-results/boundaries tests/correctness/boundaries.cpp -n8
```

Each command saves a disassembly, a debug trace, and a release log. Look for `PASSED!` in both runs. The stock traces provide the reference for checking dependencies, masks, and store ordering when we enable out-of-order issue.

Both builds passed on the pinned Vortex checkout. Debug and release reported the same counts.

| Test | Simulated instructions | Simulated cycles |
| --- | ---: | ---: |
| Register hazards | 232 | 795 |
| Lane masks and store boundary | 952 | 3,044 |
