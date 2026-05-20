# test1

- Goal: run Figure-3 style benchmark with fixed reviewer settings.
- Main script: test1
- Parameter policy: defaults in script with optional CLI overrides.
- Default sampling: rounds=1, iterations=50, warmup=5.
- Example override: bash testScripts/test1/test1 --iterations 100 --rounds 2 --warmup 10
- Data source: testScripts/backends/run_test1.sh
- Output directory: results/test1/
- Output files:
	- raw_runs.csv
	- round_means_append.csv
	- summary.csv
	- readable.md
- Run this test only: bash testScripts/test1/test1
- Run all tests: bash testScripts/run_all
