# Correctness tests

See [the root README](../../README.md#3-check-the-implementation) for the full run command. The dependency probe exercises RAW, WAR, and WAW. The boundary probe checks lane masks and store ordering. The retry check compares issue traces and verifies that a rejected instruction is issued once after retry.
