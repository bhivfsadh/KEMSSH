# test2

- Goal: run Figure-4 style benchmark at three latency levels.
- Main script: test2
- Parameter policy: defaults in script with optional CLI overrides.
- Default sampling: rounds=1, iterations=50, warmup=5.
- Optional profile override: --profile all|close|intermediate|long
- Example override: bash testScripts/test2/test2 --profile intermediate --iterations 100 --rounds 2 --warmup 10
- Data source: testScripts/backends/run_test2.sh (three latency profiles)
- Output directories:
	- results/test2-C (close latency)
	- results/test2-I (intermediate latency)
	- results/test2-L (long latency)
- Output files in each directory:
	- raw_runs.csv
	- round_means_append.csv
	- summary.csv
	- readable.md
- Run this test only: bash testScripts/test2/test2
- Run all tests: bash testScripts/run_all
