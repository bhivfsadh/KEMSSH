# test3

- Goal: run Figure-5 style window-sweep benchmark.
- Main script: test3
- Parameter policy: defaults in script with optional CLI overrides.
- Default sampling: rounds=1, iterations=50, warmup=5.
- Example override: bash testScripts/test3/test3 --iterations 100 --rounds 2 --warmup 10
- Data source: testScripts/backends/run_test3.sh
- Output directory: results/test3/
- Output files:
	- raw_runs.csv
	- round_means_append.csv
	- summary.csv
	- readable.md
- Run this test only: bash testScripts/test3/test3
- Run all tests: bash testScripts/run_all
