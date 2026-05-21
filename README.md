# KEM-Based-User-Authentication-for-Post-Quantum-SSH (Anonymous Research Artifact)

This repository is an research artifact for evaluating KEM-based user authentication in SSH based on OQS-openSSHv10.

## Anonymous Statement

This artifact is prepared for anonymous review. Repository-specific personal identifiers are intentionally minimized in the project-owned scripts and documentation.

## Scope

This repository uses a full-source distribution approach so reviewers can build and run experiments directly.

Core contribution focus:
- KEM user-authentication workflow integration in the SSH stack.
- Reproducible experiment wrappers under [testScripts](testScripts) for paper-aligned evaluations.
- Controlled network emulation for RTT and TCP initcwnd experiments.

Non-core items are intentionally not expanded into separate benchmark suites if they are not central to the KEM user-authentication claim.

## Repository Layout

- Build helpers:
  - [oqs-scripts/clone_liboqs.sh](oqs-scripts/clone_liboqs.sh)
  - [oqs-scripts/build_liboqs.sh](oqs-scripts/build_liboqs.sh)
  - [oqs-scripts/build_openssh.sh](oqs-scripts/build_openssh.sh)
- Reviewer-facing experiments:
  - [testScripts/run_all](testScripts/run_all)
  - [testScripts/test1/test1](testScripts/test1/test1)
  - [testScripts/test2/test2](testScripts/test2/test2)
  - [testScripts/test3/test3](testScripts/test3/test3)
  - Backend runners in [testScripts/backends](testScripts/backends)
- Experiment notes:
  - [testScripts/plan.md](testScripts/plan.md)

## Build


Recommended environment: Linux with sudo privileges for network shaping.

### Quick Build (Recommended)

1. Build liboqs:
  ```bash
  bash oqs-scripts/clone_liboqs.sh
  bash oqs-scripts/build_liboqs.sh
  ```

2. Build OQS-OpenSSH:
  ```bash
  bash oqs-scripts/build_openssh.sh
  ```

After building, the ssh, sshd, ssh-keygen and related binaries will appear in the repository root or in the oqs-test/tmp directory.

---

### Manual Build (for custom configuration or debugging)

If you need to customize build parameters or wish to debug the build process manually, follow these steps:

1. Install dependencies (example for Ubuntu/Debian):
  ```bash
  sudo apt-get update
  sudo apt-get install -y autoconf automake libtool make gcc g++ pkg-config libssl-dev zlib1g-dev
  ```

2. In the repository root, generate the configure script (if not already present):
  ```bash
  autoreconf -i
  ```

3. Configure build parameters (adjust --prefix, --with-liboqs-dir, etc. as needed):
  ```bash
  ./configure --prefix="$PWD/oqs-test/tmp" --with-liboqs-dir="$PWD/oqs" --with-ssl-dir=/usr --with-cflags="-I$PWD/oqs-test/tmp/include"
  ```

4. Build and install:
  ```bash
  make -j
  make install
  ```

5. The resulting ssh/sshd/ssh-keygen binaries will be located in `$PWD/oqs-test/tmp`.

For more configure options, run `./configure --help`.

You may also refer to the `oqs-scripts/build_openssh.sh` script for an automated version of these steps.

## Experiments

Run all experiments in one command:

```bash
bash testScripts/run_all
```

### Test 1 (Figure-3 style)

```bash
bash testScripts/test1/test1
```

Defaults:
- rounds=1
- iterations=50
- warmup=5
- RTT=67ms
- initcwnd=10

Optional overrides:

```bash
bash testScripts/test1/test1 --iterations 100 --rounds 2 --warmup 10 --rtt 67 --initcwnd 10
```

### Test 2 (Figure-4 style, close/intermediate/long RTT)

```bash
bash testScripts/test2/test2
```

Defaults:
- rounds=1
- iterations=50
- warmup=5
- initcwnd=10
- profiles: all (close/intermediate/long)

Optional overrides:

```bash
bash testScripts/test2/test2 --profile intermediate --iterations 100 --rounds 2 --warmup 10
```

Supported profiles:
- all
- close
- intermediate
- long

### Test 3 (Figure-5 style, 11 initcwnd points)

```bash
bash testScripts/test3/test3
```

Defaults:
- rounds=1
- iterations=50
- warmup=5
- RTT=67ms
- initcwnd list: 3 5 7 10 15 20 25 30 35 40 50

Optional overrides:

```bash
bash testScripts/test3/test3 --iterations 100 --rounds 2 --warmup 10 --rtt 67 --initcwnd-list "3 5 7 10 15 20 25 30 35 40 50"
```

## Outputs

Each test generates a reviewer-facing output set:
- raw_runs.csv
- round_means_append.csv
- summary.csv
- readable.md

See [testScripts/plan.md](testScripts/plan.md) for mapping.

## Notes on Reproducibility

- Network shaping depends on host load and scheduler behavior; small jitter is expected.
- Results are for reproducibility and comparative evaluation, not a strict absolute-latency guarantee across all platforms.
- If you publish results, align the environment with the paper setup for closest correspondence.

## License

This repository includes upstream OpenSSH/OQS components and follows their corresponding licenses.

Primary license references in this repository:
- [LICENCE](LICENCE)
