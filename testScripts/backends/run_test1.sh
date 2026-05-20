#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
EX2_RUNNER="$ROOT_DIR/testScripts/backends/run_test1_core.sh"

# Parameters are supplied by testScripts/test1/test1.
FORMAL_ROUNDS="${FORMAL_ROUNDS:?FORMAL_ROUNDS is required}"
FORMAL_WARMUP="${FORMAL_WARMUP:?FORMAL_WARMUP is required}"
FORMAL_ITERATIONS="${FORMAL_ITERATIONS:?FORMAL_ITERATIONS is required}"
RTT_MS="${RTT_MS:?RTT_MS is required}"
INITCWND_MSS="${INITCWND_MSS:?INITCWND_MSS is required}"
NETEM_IFACE="${NETEM_IFACE:?NETEM_IFACE is required}"
NETEM_TARGET_MTU="${NETEM_TARGET_MTU:-1500}"
FORCE_DISABLE_OFFLOAD="${FORCE_DISABLE_OFFLOAD:-1}"
TEST_HOST="${TEST_HOST:?TEST_HOST is required}"
TEST_PORT="${TEST_PORT:?TEST_PORT is required}"

SUDO_BIN="${SUDO_BIN:-sudo}"
SUDO_NONINTERACTIVE="${SUDO_NONINTERACTIVE:-0}"
RESULT_DIR="${RESULT_DIR:-$ROOT_DIR/testScripts/test1/results/test1}"
META_TXT="$RESULT_DIR/metadata.txt"

if [[ ! -x "$EX2_RUNNER" ]]; then
  echo "[ERR] missing test1 runner: $EX2_RUNNER"
  exit 1
fi
if ! command -v tc >/dev/null 2>&1; then
  echo "[ERR] tc not found"
  exit 1
fi
if ! command -v ip >/dev/null 2>&1; then
  echo "[ERR] ip not found"
  exit 1
fi

run_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
    return
  fi
  if ! command -v "$SUDO_BIN" >/dev/null 2>&1; then
    echo "[ERR] sudo not found and current user is not root"
    exit 1
  fi
  if [[ "$SUDO_NONINTERACTIVE" == "1" ]]; then
    "$SUDO_BIN" -n "$@"
  else
    "$SUDO_BIN" "$@"
  fi
}

NETEM_DELAY_MS="$(awk -v rtt="$RTT_MS" 'BEGIN { printf "%.3f", rtt/2.0 }')"
ORIG_LOCAL_ROUTE=""
LOCAL_ROUTE_TOUCHED=0
ORIG_IFACE_MTU=""
IFACE_MTU_TOUCHED=0
ORIG_LO_TSO=""
ORIG_LO_GSO=""
ORIG_LO_GRO=""
OFFLOAD_TOUCHED=0

cleanup() {
  if [[ "$LOCAL_ROUTE_TOUCHED" == "1" && -n "$ORIG_LOCAL_ROUTE" ]]; then
    # Restore loopback local route prior to initcwnd change.
    run_root ip route replace table local $ORIG_LOCAL_ROUTE >/dev/null 2>&1 || true
  fi
  if [[ "$IFACE_MTU_TOUCHED" == "1" && -n "$ORIG_IFACE_MTU" ]]; then
    run_root ip link set dev "$NETEM_IFACE" mtu "$ORIG_IFACE_MTU" >/dev/null 2>&1 || true
  fi
  if [[ "$OFFLOAD_TOUCHED" == "1" && "$NETEM_IFACE" == "lo" ]]; then
    run_root ethtool -K "$NETEM_IFACE" tso "$ORIG_LO_TSO" gso "$ORIG_LO_GSO" gro "$ORIG_LO_GRO" >/dev/null 2>&1 || true
  fi
  run_root tc qdisc del dev "$NETEM_IFACE" root >/dev/null 2>&1 || true
}
trap cleanup EXIT

get_offload_state() {
  local feature="$1"
  ethtool -k "$NETEM_IFACE" 2>/dev/null | awk -v f="$feature" '$1 == f":" {print $2; exit}'
}

enforce_lo_offload_settings() {
  if [[ "$FORCE_DISABLE_OFFLOAD" != "1" ]]; then
    return 0
  fi
  if [[ "$NETEM_IFACE" != "lo" ]]; then
    return 0
  fi
  if ! command -v ethtool >/dev/null 2>&1; then
    echo "[ERR] ethtool is required when FORCE_DISABLE_OFFLOAD=1 on lo"
    exit 1
  fi

  ORIG_LO_TSO="$(get_offload_state tcp-segmentation-offload)"
  ORIG_LO_GSO="$(get_offload_state generic-segmentation-offload)"
  ORIG_LO_GRO="$(get_offload_state generic-receive-offload)"
  if [[ -z "$ORIG_LO_TSO" || -z "$ORIG_LO_GSO" || -z "$ORIG_LO_GRO" ]]; then
    echo "[ERR] failed to read current offload state for lo"
    exit 1
  fi

  if [[ "$ORIG_LO_TSO" != "off" || "$ORIG_LO_GSO" != "off" || "$ORIG_LO_GRO" != "off" ]]; then
    echo "[INFO] Disabling lo offload: tso=$ORIG_LO_TSO gso=$ORIG_LO_GSO gro=$ORIG_LO_GRO"
    run_root ethtool -K "$NETEM_IFACE" tso off gso off gro off
    OFFLOAD_TOUCHED=1
  else
    echo "[INFO] lo offload already disabled"
  fi
}

enforce_iface_mtu() {
  local current_mtu

  current_mtu="$(ip -o link show "$NETEM_IFACE" | awk '{for(i=1;i<=NF;i++) if($i=="mtu") {print $(i+1); exit}}')"
  if [[ -z "$current_mtu" ]]; then
    echo "[ERR] failed to query MTU for iface=$NETEM_IFACE"
    exit 1
  fi

  ORIG_IFACE_MTU="$current_mtu"
  if [[ "$current_mtu" != "$NETEM_TARGET_MTU" ]]; then
    echo "[INFO] Adjusting iface=$NETEM_IFACE MTU: $current_mtu -> $NETEM_TARGET_MTU"
    run_root ip link set dev "$NETEM_IFACE" mtu "$NETEM_TARGET_MTU"
    IFACE_MTU_TOUCHED=1
  else
    echo "[INFO] iface=$NETEM_IFACE MTU already $NETEM_TARGET_MTU"
  fi
}

enforce_iface_mtu
enforce_lo_offload_settings
echo "[INFO] Applying netem: iface=$NETEM_IFACE, RTT=$RTT_MS ms (one-way delay $NETEM_DELAY_MS ms)"
run_root tc qdisc del dev "$NETEM_IFACE" root >/dev/null 2>&1 || true
run_root tc qdisc add dev "$NETEM_IFACE" root netem delay "${NETEM_DELAY_MS}ms"

echo "[INFO] Enforcing initcwnd=$INITCWND_MSS"
if [[ "$TEST_HOST" == 127.* && "$NETEM_IFACE" == "lo" ]]; then
  ORIG_LOCAL_ROUTE="$(ip route show table local 127.0.0.0/8 dev lo | head -n1)"
  if [[ -z "$ORIG_LOCAL_ROUTE" ]]; then
    echo "[ERR] failed to locate loopback local route for initcwnd"
    exit 1
  fi
  LOCAL_ROUTE_TOUCHED=1
  run_root ip route replace table local local 127.0.0.0/8 dev lo proto kernel scope host src 127.0.0.1 initcwnd "$INITCWND_MSS"
  if ! ip route show table local 127.0.0.0/8 dev lo | grep -q "initcwnd $INITCWND_MSS"; then
    echo "[ERR] initcwnd not applied to loopback route"
    exit 1
  fi
else
  echo "[WARN] initcwnd auto-enforcement currently implemented for TEST_HOST=127.x + lo"
  echo "[WARN] current TEST_HOST=$TEST_HOST, NETEM_IFACE=$NETEM_IFACE"
  exit 1
fi

echo "[INFO] Running test1: rounds=$FORMAL_ROUNDS, warmup=$FORMAL_WARMUP, iterations=$FORMAL_ITERATIONS"
ROUNDS="$FORMAL_ROUNDS" \
ITERATIONS="$FORMAL_ITERATIONS" \
WARMUP="$FORMAL_WARMUP" \
TEST_HOST="$TEST_HOST" \
TEST_PORT="$TEST_PORT" \
RESULT_DIR="$RESULT_DIR" \
bash "$EX2_RUNNER"

if [[ -f "$META_TXT" ]]; then
  {
    echo "use_netem=1"
    echo "netem_iface=$NETEM_IFACE"
    echo "netem_target_mtu=$NETEM_TARGET_MTU"
    echo "effective_mtu=$(ip -o link show "$NETEM_IFACE" | awk '{for(i=1;i<=NF;i++) if($i=="mtu") {print $(i+1); exit}}')"
    echo "force_disable_offload=$FORCE_DISABLE_OFFLOAD"
    echo "effective_tso=$(if [[ "$NETEM_IFACE" == "lo" ]] && command -v ethtool >/dev/null 2>&1; then ethtool -k "$NETEM_IFACE" | awk '$1=="tcp-segmentation-offload:" {print $2; exit}'; else echo "NA"; fi)"
    echo "effective_gso=$(if [[ "$NETEM_IFACE" == "lo" ]] && command -v ethtool >/dev/null 2>&1; then ethtool -k "$NETEM_IFACE" | awk '$1=="generic-segmentation-offload:" {print $2; exit}'; else echo "NA"; fi)"
    echo "effective_gro=$(if [[ "$NETEM_IFACE" == "lo" ]] && command -v ethtool >/dev/null 2>&1; then ethtool -k "$NETEM_IFACE" | awk '$1=="generic-receive-offload:" {print $2; exit}'; else echo "NA"; fi)"
    echo "netem_delay_mode=half_rtt"
    echo "netem_applied_delay_ms=$NETEM_DELAY_MS"
    echo "initcwnd_enforced=1"
    echo "rounds=$FORMAL_ROUNDS"
    echo "iterations_per_round=$FORMAL_ITERATIONS"
    echo "warmup_per_round=$FORMAL_WARMUP"
    echo "total_measurements=$((FORMAL_ROUNDS * FORMAL_ITERATIONS))"
  } >> "$META_TXT"
fi

echo "[OK] test1 run completed"
echo "[ARTIFACT] $RESULT_DIR/summary.csv"
