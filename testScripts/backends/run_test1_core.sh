#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
EXP_ID="${EXP_ID:-test1}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/testScripts/.work-test1}"
RESULT_DIR="${RESULT_DIR:-$ROOT_DIR/testScripts/test1/results/test1}"
ITERATIONS="${ITERATIONS:?ITERATIONS is required}"
WARMUP="${WARMUP:?WARMUP is required}"
ROUNDS="${ROUNDS:?ROUNDS is required}"
TEST_USER="${TEST_USER:-$(id -un)}"
TEST_HOST="${TEST_HOST:?TEST_HOST is required}"
TEST_PORT="${TEST_PORT:?TEST_PORT is required}"
KEEP_WORKDIR="${KEEP_WORKDIR:-1}"

SSH_BIN="${SSH_BIN:-$ROOT_DIR/ssh}"
SSHD_BIN="${SSHD_BIN:-$ROOT_DIR/sshd}"
SSH_KEYGEN_BIN="${SSH_KEYGEN_BIN:-$ROOT_DIR/ssh-keygen}"
SSHD_SESSION_BIN="${SSHD_SESSION_BIN:-$ROOT_DIR/sshd-session}"
SSHD_AUTH_BIN="${SSHD_AUTH_BIN:-$ROOT_DIR/sshd-auth}"

ID_ED25519_FILE="${ID_ED25519_FILE:-$WORK_DIR/id_ed25519}"
ID_MD44_FILE="${ID_MD44_FILE:-$WORK_DIR/id_mldsa44}"
ID_MD65_FILE="${ID_MD65_FILE:-$WORK_DIR/id_mldsa65}"
ID_MD87_FILE="${ID_MD87_FILE:-$WORK_DIR/id_mldsa87}"
ID_SD128F_FILE="${ID_SD128F_FILE:-$WORK_DIR/id_slhdsa128f}"
ID_SD192F_FILE="${ID_SD192F_FILE:-$WORK_DIR/id_slhdsa192f}"
ID_SD256F_FILE="${ID_SD256F_FILE:-$WORK_DIR/id_slhdsa256f}"
ID_MK512_FILE="${ID_MK512_FILE:-$WORK_DIR/id_mlkem512}"
ID_MK768_FILE="${ID_MK768_FILE:-$ROOT_DIR/testScripts/.work-kem/id_mlkem768}"
ID_MK1024_FILE="${ID_MK1024_FILE:-$WORK_DIR/id_mlkem1024}"

if [[ ! -x "$SSH_BIN" || ! -x "$SSHD_BIN" || ! -x "$SSH_KEYGEN_BIN" ||
      ! -x "$SSHD_SESSION_BIN" || ! -x "$SSHD_AUTH_BIN" ]]; then
  echo "[ERR] missing binaries: ssh/sshd/ssh-keygen/sshd-session/sshd-auth"
  exit 1
fi

mkdir -p "$WORK_DIR" "$RESULT_DIR"
RAW_CSV="$RESULT_DIR/raw_runs.csv"
SUMMARY_CSV="$RESULT_DIR/summary.csv"
MANIFEST_CSV="$RESULT_DIR/cases_manifest.csv"
META_TXT="$RESULT_DIR/metadata.txt"
ROUND_MEAN_CSV="$RESULT_DIR/round_means_append.csv"

SSHD_PID=""
cleanup() {
  if [[ -n "$SSHD_PID" ]] && kill -0 "$SSHD_PID" 2>/dev/null; then
    kill "$SSHD_PID" 2>/dev/null || true
    wait "$SSHD_PID" 2>/dev/null || true
  fi
  if [[ "$KEEP_WORKDIR" != "1" ]]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

HOST_KEY="$WORK_DIR/ssh_host_ed25519_key"
KNOWN_HOSTS="$WORK_DIR/known_hosts"
SSHD_LOG="$WORK_DIR/sshd.log"
AUTHORIZED_KEYS="$WORK_DIR/authorized_keys"
AUTHORIZED_KEM_KEYS="$WORK_DIR/authorized_kem_keys"

if [[ ! -f "$HOST_KEY" ]]; then
  "$SSH_KEYGEN_BIN" -q -t ed25519 -N "" -f "$HOST_KEY" >/dev/null
fi
if [[ ! -f "$ID_ED25519_FILE" ]]; then
  mkdir -p "$(dirname "$ID_ED25519_FILE")"
  "$SSH_KEYGEN_BIN" -q -t ed25519 -N "" -f "$ID_ED25519_FILE" >/dev/null
fi

: > "$AUTHORIZED_KEYS"
: > "$AUTHORIZED_KEM_KEYS"

add_pubkey_if_exists() {
  local key="$1"
  if [[ -n "$key" && -f "$key.pub" ]]; then
    cat "$key.pub" >> "$AUTHORIZED_KEYS"
  fi
}

supports_ssh_key_alg() {
  local alg="$1"
  "$SSH_BIN" -Q key 2>/dev/null | grep -Fxq "$alg"
}

ensure_pubkey_identity() {
  local alg="$1"
  local path="$2"

  if [[ -f "$path" && -f "$path.pub" ]]; then
    return 0
  fi
  if ! supports_ssh_key_alg "$alg"; then
    return 1
  fi
  mkdir -p "$(dirname "$path")"
  "$SSH_KEYGEN_BIN" -q -t "$alg" -N "" -f "$path" >/dev/null
}

ensure_kem_identity() {
  local alg="$1"
  local path="$2"

  if [[ -f "$path" ]]; then
    return 0
  fi
  case "$alg" in
    ML-KEM-512)
      mkdir -p "$(dirname "$path")"
      bash "$ROOT_DIR/testScripts/backends/generate_kem_identity.sh" "$path" "ML-KEM-512" >/dev/null
      return 0
      ;;
    ML-KEM-768)
      mkdir -p "$(dirname "$path")"
      bash "$ROOT_DIR/testScripts/backends/generate_kem_identity.sh" "$path" "ML-KEM-768" >/dev/null
      return 0
      ;;
    ML-KEM-1024)
      mkdir -p "$(dirname "$path")"
      bash "$ROOT_DIR/testScripts/backends/generate_kem_identity.sh" "$path" "ML-KEM-1024" >/dev/null
      return 0
      ;;
  esac
  return 1
}

ensure_pubkey_identity "ssh-mldsa-44" "$ID_MD44_FILE" || true
ensure_pubkey_identity "ssh-mldsa-65" "$ID_MD65_FILE" || true
ensure_pubkey_identity "ssh-mldsa-87" "$ID_MD87_FILE" || true
ensure_pubkey_identity "ssh-slhdsapuresha2128f" "$ID_SD128F_FILE" || true
ensure_pubkey_identity "ssh-slhdsapuresha2192f" "$ID_SD192F_FILE" || true
ensure_pubkey_identity "ssh-slhdsapuresha2256f" "$ID_SD256F_FILE" || true

ensure_kem_identity "ML-KEM-512" "$ID_MK512_FILE" || true
ensure_kem_identity "ML-KEM-768" "$ID_MK768_FILE" || true
ensure_kem_identity "ML-KEM-1024" "$ID_MK1024_FILE" || true

extract_kem_public() {
  local f="$1"
  awk 'BEGIN{IGNORECASE=1} $1 ~ /^public$/ {print $2; exit}' "$f"
}

add_kem_if_exists() {
  local alg="$1"
  local key="$2"
  local pub
  if [[ -n "$key" && -f "$key" ]]; then
    pub="$(extract_kem_public "$key" || true)"
    if [[ -n "$pub" ]]; then
      printf '%s %s\n' "$alg" "$pub" >> "$AUTHORIZED_KEM_KEYS"
    fi
  fi
}

add_pubkey_if_exists "$ID_ED25519_FILE"
add_pubkey_if_exists "$ID_MD44_FILE"
add_pubkey_if_exists "$ID_MD65_FILE"
add_pubkey_if_exists "$ID_MD87_FILE"
add_pubkey_if_exists "$ID_SD128F_FILE"
add_pubkey_if_exists "$ID_SD192F_FILE"
add_pubkey_if_exists "$ID_SD256F_FILE"

add_kem_if_exists "ML-KEM-512" "$ID_MK512_FILE"
add_kem_if_exists "ML-KEM-768" "$ID_MK768_FILE"
add_kem_if_exists "ML-KEM-1024" "$ID_MK1024_FILE"

cat > "$WORK_DIR/sshd.conf" <<EOF
Port $TEST_PORT
ListenAddress $TEST_HOST
PidFile $WORK_DIR/sshd.pid
LogLevel ERROR
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
PubkeyAcceptedAlgorithms ssh-ed25519,ssh-mldsa-44,ssh-mldsa-65,ssh-mldsa-87,ssh-slhdsapuresha2128f,ssh-slhdsapuresha2192f,ssh-slhdsapuresha2256f
KEMAuthentication yes
KEMAuthAlgorithms ML-KEM-512,ML-KEM-768,ML-KEM-1024
KexAlgorithms mlkem768x25519-sha256
HostKeyAlgorithms ssh-ed25519
AuthorizedKeysFile $AUTHORIZED_KEYS
AuthorizedKEMKeysFile $AUTHORIZED_KEM_KEYS
HostKey $HOST_KEY
SshdSessionPath $SSHD_SESSION_BIN
SshdAuthPath $SSHD_AUTH_BIN
StrictModes no
EOF

start_sshd() {
  "$SSHD_BIN" -f "$WORK_DIR/sshd.conf" -E "$SSHD_LOG" -D &
  SSHD_PID=$!
  for _ in $(seq 1 200); do
    if { exec 3<>"/dev/tcp/$TEST_HOST/$TEST_PORT"; } 2>/dev/null; then
      exec 3>&- || true
      exec 3<&- || true
      return 0
    fi
    read -r -t 0.05 _ || true
  done
  echo "[ERR] sshd start timeout"
  return 1
}

run_once() {
  local case_name="$1"
  local round="$2"
  local phase="$3"
  local iter="$4"
  local auth_mode="$5"
  local impl_alg="$6"
  local id_file="$7"
  local rc=0
  local start_ns end_ns delta_ns delta_ms

  start_ns="$(date +%s%N)"
  if [[ "$auth_mode" == "publickey" ]]; then
    "$SSH_BIN" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile="$KNOWN_HOSTS" \
      -o BatchMode=yes \
      -o PasswordAuthentication=no \
      -o KbdInteractiveAuthentication=no \
      -o ConnectTimeout=5 \
      -o KexAlgorithms=mlkem768x25519-sha256 \
      -o HostKeyAlgorithms=ssh-ed25519 \
      -o PreferredAuthentications=publickey \
      -o PubkeyAcceptedAlgorithms="$impl_alg" \
      -o IdentityFile="$id_file" \
      -o KEMAuthentication=no \
      -p "$TEST_PORT" \
      "$TEST_USER@$TEST_HOST" true >/dev/null 2>&1 || rc=$?
  else
    "$SSH_BIN" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile="$KNOWN_HOSTS" \
      -o BatchMode=yes \
      -o PasswordAuthentication=no \
      -o KbdInteractiveAuthentication=no \
      -o ConnectTimeout=5 \
      -o KexAlgorithms=mlkem768x25519-sha256 \
      -o HostKeyAlgorithms=ssh-ed25519 \
      -o PreferredAuthentications=publickey-kem \
      -o PubkeyAuthentication=no \
      -o KEMAuthentication=yes \
      -o KEMAuthAlgorithms="$impl_alg" \
      -o IdentityKEMFile="$id_file" \
      -p "$TEST_PORT" \
      "$TEST_USER@$TEST_HOST" true >/dev/null 2>&1 || rc=$?
  fi
  end_ns="$(date +%s%N)"
  delta_ns=$((end_ns - start_ns))
  delta_ms=$(awk -v ns="$delta_ns" 'BEGIN { printf "%.3f", ns/1000000.0 }')
  echo "$case_name,$round,$phase,$iter,$auth_mode,$impl_alg,$rc,$delta_ms" >> "$RAW_CSV"
}

summarize_case() {
  local case_name="$1"
  local auth_mode="$2"
  local paper_alg="$3"
  local impl_alg="$4"
  local status="$5"
  local reason="$6"

  local total fail success mean p50 p95
  total=$(awk -F, -v c="$case_name" '$1==c && $3=="measure" {n++} END {print n+0}' "$RAW_CSV")
  fail=$(awk -F, -v c="$case_name" '$1==c && $3=="measure" && $7!=0 {n++} END {print n+0}' "$RAW_CSV")
  success=$((total - fail))

  if (( success > 0 )); then
    read -r mean p50 p95 <<EOFSTATS
$(awk -F, -v c="$case_name" '$1==c && $3=="measure" && $7==0 {print $8}' "$RAW_CSV" |
  sort -n |
  awk '
    {a[NR]=$1; s+=$1}
    END {
      n=NR;
      if (n==0) {print "NA NA NA"; exit}
      p50i=int(0.50*n + 0.999999); if (p50i<1) p50i=1; if (p50i>n) p50i=n;
      p95i=int(0.95*n + 0.999999); if (p95i<1) p95i=1; if (p95i>n) p95i=n;
      printf "%.3f %.3f %.3f\n", s/n, a[p50i], a[p95i]
    }')
EOFSTATS
  else
    mean="NA"; p50="NA"; p95="NA"
  fi

  fail_rate=$(awk -v f="$fail" -v t="$total" 'BEGIN{if (t==0) printf "NA"; else printf "%.4f", f/t}')
  retry_rate="0.0000"
  echo "$case_name,$auth_mode,$paper_alg,$impl_alg,$status,$reason,$mean,$p50,$p95,$fail_rate,$retry_rate,$total,$success,$fail" >> "$SUMMARY_CSV"
}

append_round_mean() {
  local case_name="$1"
  local paper_alg="$2"
  local impl_alg="$3"
  local round="$4"
  local mean success total fail

  total=$(awk -F, -v c="$case_name" -v r="$round" '$1==c && $2==r && $3=="measure" {n++} END {print n+0}' "$RAW_CSV")
  fail=$(awk -F, -v c="$case_name" -v r="$round" '$1==c && $2==r && $3=="measure" && $7!=0 {n++} END {print n+0}' "$RAW_CSV")
  success=$((total - fail))
  if (( success > 0 )); then
    mean=$(awk -F, -v c="$case_name" -v r="$round" '$1==c && $2==r && $3=="measure" && $7==0 {s+=$8;n++} END{if(n==0) print "NA"; else printf "%.3f", s/n}' "$RAW_CSV")
  else
    mean="NA"
  fi

  printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(TZ=America/New_York date +%Y-%m-%dT%H:%M:%S%z)" "$EXP_ID" "$round" "$paper_alg" "$impl_alg" "$mean" "$success" "$total" >> "$ROUND_MEAN_CSV"
}

start_sshd

echo "case,round,phase,iter,auth_mode,impl_alg,rc,latency_ms" > "$RAW_CSV"
echo "case,auth_mode,paper_alg,impl_alg,status,reason,mean_ms,p50_ms,p95_ms,failure_rate,retry_rate,total,success,fail" > "$SUMMARY_CSV"
echo "paper_alg,auth_mode,impl_alg,identity_file" > "$MANIFEST_CSV"
echo "ts_us,experiment,round,paper_alg,impl_alg,mean_ms,success,total" > "$ROUND_MEAN_CSV"

# paper_alg|auth_mode|impl_alg|id_file
cases=(
  "ed25519|publickey|ssh-ed25519|$ID_ED25519_FILE"
  "md44|publickey|ssh-mldsa-44|$ID_MD44_FILE"
  "md65|publickey|ssh-mldsa-65|$ID_MD65_FILE"
  "md87|publickey|ssh-mldsa-87|$ID_MD87_FILE"
  "sd128f|publickey|ssh-slhdsapuresha2128f|$ID_SD128F_FILE"
  "sd192f|publickey|ssh-slhdsapuresha2192f|$ID_SD192F_FILE"
  "sd256f|publickey|ssh-slhdsapuresha2256f|$ID_SD256F_FILE"
  "mk512|publickey-kem|ML-KEM-512|$ID_MK512_FILE"
  "mk768|publickey-kem|ML-KEM-768|$ID_MK768_FILE"
  "mk1024|publickey-kem|ML-KEM-1024|$ID_MK1024_FILE"
)

runnable_cases=()

for entry in "${cases[@]}"; do
  IFS='|' read -r paper_alg auth_mode impl_alg id_file <<< "$entry"
  case_name="test1_${paper_alg}"
  echo "$paper_alg,$auth_mode,$impl_alg,$id_file" >> "$MANIFEST_CSV"

  if [[ "$auth_mode" == "publickey" ]]; then
    if ! supports_ssh_key_alg "$impl_alg"; then
      summarize_case "$case_name" "$auth_mode" "$paper_alg" "$impl_alg" "UNSUPPORTED" "algorithm not supported by current build"
      continue
    fi
    if [[ ! -f "$id_file" || ! -f "$id_file.pub" ]]; then
      summarize_case "$case_name" "$auth_mode" "$paper_alg" "$impl_alg" "UNSUPPORTED" "identity generation unavailable"
      continue
    fi
  else
    if [[ ! -f "$id_file" ]]; then
      summarize_case "$case_name" "$auth_mode" "$paper_alg" "$impl_alg" "UNSUPPORTED" "KEM identity generation unavailable"
      continue
    fi
  fi

  runnable_cases+=("$entry")
done

runnable_count="${#runnable_cases[@]}"
if (( runnable_count > 0 )); then
  for round in $(seq 1 "$ROUNDS"); do
    # Round-robin rotate test order by round index: 1..N, 2..N,1, ..., N,1..N-1.
    for offset in $(seq 0 $((runnable_count - 1))); do
      idx=$(((round - 1 + offset) % runnable_count))
      entry="${runnable_cases[$idx]}"
      IFS='|' read -r paper_alg auth_mode impl_alg id_file <<< "$entry"
      case_name="test1_${paper_alg}"

      for i in $(seq 1 "$WARMUP"); do
        run_once "$case_name" "$round" "warmup" "$i" "$auth_mode" "$impl_alg" "$id_file"
      done
      for i in $(seq 1 "$ITERATIONS"); do
        run_once "$case_name" "$round" "measure" "$i" "$auth_mode" "$impl_alg" "$id_file"
      done
      append_round_mean "$case_name" "$paper_alg" "$impl_alg" "$round"
    done
    echo "[PROGRESS] round=$round done"
  done

  for entry in "${runnable_cases[@]}"; do
    IFS='|' read -r paper_alg auth_mode impl_alg id_file <<< "$entry"
    case_name="test1_${paper_alg}"

    fail=$(awk -F, -v c="$case_name" '$1==c && $3=="measure" && $7!=0 {n++} END {print n+0}' "$RAW_CSV")
    if (( fail == 0 )); then
      summarize_case "$case_name" "$auth_mode" "$paper_alg" "$impl_alg" "PASS" ""
    else
      summarize_case "$case_name" "$auth_mode" "$paper_alg" "$impl_alg" "FAIL" "non-zero failures"
    fi
    echo "[PROGRESS] case=$case_name done"
  done
fi

cat > "$META_TXT" <<EOF
experiment=test1
objective=fig3-fixed-kex-client-auth-compare
kex=mlkem768x25519-sha256
server_hostkey=ssh-ed25519
rtt_target_ms=67
initcwnd_mss=10
rounds=$ROUNDS
iterations_per_round=$ITERATIONS
warmup_per_round=$WARMUP
total_measurements=$((ROUNDS * ITERATIONS))
iterations=$ITERATIONS
warmup=$WARMUP
raw_csv=$RAW_CSV
summary_csv=$SUMMARY_CSV
manifest_csv=$MANIFEST_CSV
round_mean_csv=$ROUND_MEAN_CSV
EOF

echo "[OK] test1 completed"
echo "[ARTIFACT] $SUMMARY_CSV"
echo "[ARTIFACT] $RAW_CSV"
