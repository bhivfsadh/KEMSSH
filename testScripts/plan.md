# testScripts/plan.md

This directory contains the reviewer-facing experiment wrappers.

## One-click Entry
- Entry script: testScripts/run_all
- Usage: bash testScripts/run_all
- Behavior: runs test1, test2, and test3 in sequence with default reviewer settings.
- Default sampling: iterations=50, warmup=5 (rounds default to 1).
- Optional override: each test script supports CLI options for rounds/iterations/warmup and selected network parameters.

## Test Groups

### test1
- Goal: Figure-3 dataset generation
- Script: testScripts/test1/test1
- Outputs: raw_runs.csv, round_means_append.csv, summary.csv, readable.md

### test2-C / test2-I / test2-L
- Goal: Figure-4 dataset generation at close/intermediate/long latency
- Script: testScripts/test2/test2
- Outputs (per level): raw_runs.csv, round_means_append.csv, summary.csv, readable.md

### test3
- Goal: Figure-5 dataset generation
- Script: testScripts/test3/test3
- Outputs: raw_runs.csv, round_means_append.csv, summary.csv, readable.md

## Rules
- Scripts are one-click runnable with fixed settings.
- Keep output naming stable and minimal.
- Keep all content in English for reviewer usability.
