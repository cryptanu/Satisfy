#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEPLOYMENT_FILE="${DEPLOYMENT_FILE:-${1:-$ROOT_DIR/deployments/unichain-sepolia.json}}"
RPC_URL="${RPC_URL:-}"
RPC_TIMEOUT="${RPC_TIMEOUT:-120}"
STATE_FILE="${STATE_FILE:-$ROOT_DIR/.reactive_worker_state.json}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-15}"
START_BLOCK="${START_BLOCK:-latest}"
RUN_ONCE="${RUN_ONCE:-false}"
EXECUTOR_DRY_RUN="${EXECUTOR_DRY_RUN:-false}"
JOB_VALIDITY_SECONDS="${JOB_VALIDITY_SECONDS:-3600}"

REACTIVE_WORKER_PK="${REACTIVE_WORKER_PK:-${REACTIVE_EXECUTOR_PK:-${DEPLOYER_PK:-}}}"
RELAYER_PK="${RELAYER_PK:-${REACTIVE_RELAYER_PK:-$REACTIVE_WORKER_PK}}"
REVOCATION_ROTATE_EPOCH="${REVOCATION_ROTATE_EPOCH:-true}"
SIGNER_DISABLE_PAUSE="${SIGNER_DISABLE_PAUSE:-true}"
EPOCH_ROTATION_SECONDS="${EPOCH_ROTATION_SECONDS:-0}"

ATT_REV_SIG="AttestationRevoked(bytes32,address)"
SIGNER_UPDATED_SIG="TrustedSignerUpdated(address,bool)"
FALSE_BOOL_HEX="0x0000000000000000000000000000000000000000000000000000000000000000"

log() {
  echo "[reactive-worker] $*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

is_true() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|y) return 0 ;;
    *) return 1 ;;
  esac
}

cast_call() {
  local to="$1"
  local sig="$2"
  shift 2
  cast call "$to" "$sig" "$@" --rpc-url "$RPC_URL" --rpc-timeout "$RPC_TIMEOUT"
}

cast_send() {
  local to="$1"
  local sig="$2"
  shift 2
  cast send "$to" "$sig" "$@" --rpc-url "$RPC_URL" --rpc-timeout "$RPC_TIMEOUT" --private-key "$RELAYER_PK" >/dev/null
}

fetch_logs() {
  local signature="$1"
  local address="$2"
  local from_block="$3"
  local to_block="$4"
  cast logs "$signature" \
    --address "$address" \
    --from-block "$from_block" \
    --to-block "$to_block" \
    --rpc-url "$RPC_URL" \
    --rpc-timeout "$RPC_TIMEOUT" \
    --json
}

write_state() {
  local tmp
  tmp="$(mktemp)"
  jq -n \
    --argjson lastProcessedBlock "$last_processed_block" \
    --argjson nextEpochRotationTs "$next_epoch_rotation_ts" \
    '{
      lastProcessedBlock: $lastProcessedBlock,
      nextEpochRotationTs: $nextEpochRotationTs
    }' > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

submit_signed_job() {
  local action="$1"
  local payload="$2"
  local reason="$3"
  local nonce valid_until job_id job digest sig

  job_id="$(cast keccak "$reason")"
  nonce="$(cast_call "$REACTIVE_GATEWAY" "nextNonce(address)(uint256)" "$WORKER_ADDR")"
  valid_until="$(( $(date +%s) + JOB_VALIDITY_SECONDS ))"
  job="($job_id,$action,$payload,$valid_until,$nonce)"

  if is_true "$EXECUTOR_DRY_RUN"; then
    log "[dry-run] action=$action job=$job_id nonce=$nonce reason=$reason"
    return 0
  fi

  digest="$(cast_call "$REACTIVE_GATEWAY" "jobDigest((bytes32,uint8,bytes,uint64,uint256))(bytes32)" "$job")"
  sig="$(cast wallet sign --private-key "$REACTIVE_WORKER_PK" --no-hash "$digest")"

  log "submit action=$action job=$job_id nonce=$nonce reason=$reason"
  cast_send "$REACTIVE_GATEWAY" "execute((bytes32,uint8,bytes,uint64,uint256),bytes)" "$job" "$sig"
}

run_reactive_set_epoch() {
  local reason="$1"
  local current_epoch new_epoch payload
  current_epoch="$(cast_call "$POLICY_ENGINE" "currentEpoch()(uint64)")"
  new_epoch="$((current_epoch + 1))"
  payload="$(cast abi-encode "f(uint64)" "$new_epoch")"
  submit_signed_job "$ACTION_SET_EPOCH" "$payload" "$reason"
}

run_reactive_pause_all() {
  local paused="$1"
  local reason="$2"
  local payload
  payload="$(cast abi-encode "f(bool)" "$paused")"
  submit_signed_job "$ACTION_PAUSE_ALL" "$payload" "$reason"
}

require_cmd cast
require_cmd jq

if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
  echo "deployment artifact not found: $DEPLOYMENT_FILE" >&2
  exit 1
fi

if [[ -z "$RPC_URL" ]]; then
  RPC_URL="$(jq -r '.rpcUrl' "$DEPLOYMENT_FILE")"
fi

AUTOMATION_MODULE="$(jq -r '.automationModule' "$DEPLOYMENT_FILE")"
POLICY_ENGINE="$(jq -r '.policyEngine' "$DEPLOYMENT_FILE")"
SELF_REGISTRY="$(jq -r '.selfRegistry' "$DEPLOYMENT_FILE")"
REACTIVE_GATEWAY="$(jq -r '.reactiveGateway // empty' "$DEPLOYMENT_FILE")"

if [[ -z "$REACTIVE_GATEWAY" || "$REACTIVE_GATEWAY" == "null" ]]; then
  echo "reactiveGateway missing in deployment artifact. Redeploy with updated pipeline." >&2
  exit 1
fi

if [[ "$AUTOMATION_MODULE" == "null" || -z "$AUTOMATION_MODULE" ]]; then
  echo "automationModule missing in deployment artifact." >&2
  exit 1
fi
if [[ "$POLICY_ENGINE" == "null" || -z "$POLICY_ENGINE" ]]; then
  echo "policyEngine missing in deployment artifact." >&2
  exit 1
fi
if [[ "$SELF_REGISTRY" == "null" || -z "$SELF_REGISTRY" ]]; then
  echo "selfRegistry missing in deployment artifact." >&2
  exit 1
fi

if ! is_true "$EXECUTOR_DRY_RUN" && [[ -z "$REACTIVE_WORKER_PK" ]]; then
  echo "REACTIVE_WORKER_PK (or REACTIVE_EXECUTOR_PK/DEPLOYER_PK) is required unless EXECUTOR_DRY_RUN=true." >&2
  exit 1
fi

if ! is_true "$EXECUTOR_DRY_RUN" && [[ -z "$RELAYER_PK" ]]; then
  echo "RELAYER_PK (or REACTIVE_RELAYER_PK) is required unless EXECUTOR_DRY_RUN=true." >&2
  exit 1
fi

if is_true "$EXECUTOR_DRY_RUN"; then
  WORKER_ADDR="${REACTIVE_WORKER_ADDRESS:-0x0000000000000000000000000000000000000000}"
  RELAYER_ADDR="${REACTIVE_RELAYER_ADDRESS:-0x0000000000000000000000000000000000000000}"
  log "Running in dry-run mode (no signatures or transactions)."
else
  WORKER_ADDR="$(cast wallet address --private-key "$REACTIVE_WORKER_PK")"
  RELAYER_ADDR="$(cast wallet address --private-key "$RELAYER_PK")"
fi

if ! is_true "$EXECUTOR_DRY_RUN"; then
  is_worker_trusted="$(cast_call "$REACTIVE_GATEWAY" "trustedWorkers(address)(bool)" "$WORKER_ADDR")"
  if [[ "$is_worker_trusted" != "true" ]]; then
    echo "worker is not trusted by reactive gateway." >&2
    echo "Worker:  $WORKER_ADDR" >&2
    echo "Gateway: $REACTIVE_GATEWAY" >&2
    exit 1
  fi
fi

configured_automation="$(cast_call "$REACTIVE_GATEWAY" "automationModule()(address)")"
if [[ "${configured_automation,,}" != "${AUTOMATION_MODULE,,}" ]]; then
  echo "reactive gateway automation mismatch." >&2
  echo "artifact automationModule: $AUTOMATION_MODULE" >&2
  echo "gateway automationModule:  $configured_automation" >&2
  exit 1
fi

ACTION_SET_EPOCH="$(cast_call "$REACTIVE_GATEWAY" "ACTION_SET_EPOCH()(uint8)")"
ACTION_PAUSE_ALL="$(cast_call "$REACTIVE_GATEWAY" "ACTION_PAUSE_ALL()(uint8)")"

if [[ -f "$STATE_FILE" ]]; then
  last_processed_block="$(jq -r '.lastProcessedBlock // 0' "$STATE_FILE")"
  next_epoch_rotation_ts="$(jq -r '.nextEpochRotationTs // 0' "$STATE_FILE")"
else
  if [[ "$START_BLOCK" == "latest" ]]; then
    last_processed_block="$(cast block-number --rpc-url "$RPC_URL" --rpc-timeout "$RPC_TIMEOUT")"
  else
    last_processed_block="$START_BLOCK"
  fi
  if (( EPOCH_ROTATION_SECONDS > 0 )); then
    next_epoch_rotation_ts="$(( $(date +%s) + EPOCH_ROTATION_SECONDS ))"
  else
    next_epoch_rotation_ts=0
  fi
  write_state
fi

log "RPC: $RPC_URL"
log "Deployment: $DEPLOYMENT_FILE"
log "Gateway: $REACTIVE_GATEWAY"
log "Automation: $AUTOMATION_MODULE"
log "SelfRegistry: $SELF_REGISTRY"
log "Worker: $WORKER_ADDR"
log "Relayer: $RELAYER_ADDR"
log "State file: $STATE_FILE"
log "Start block cursor: $last_processed_block"

while true; do
  latest_block="$(cast block-number --rpc-url "$RPC_URL" --rpc-timeout "$RPC_TIMEOUT")"

  if (( latest_block > last_processed_block )); then
    from_block="$((last_processed_block + 1))"
    to_block="$latest_block"
    log "Scanning blocks $from_block..$to_block"

    revocation_logs="[]"
    signer_logs="[]"

    if ! revocation_logs="$(fetch_logs "$ATT_REV_SIG" "$SELF_REGISTRY" "$from_block" "$to_block")"; then
      log "Failed to fetch revocation logs; retrying next loop."
      sleep "$POLL_INTERVAL_SECONDS"
      continue
    fi

    if ! signer_logs="$(fetch_logs "$SIGNER_UPDATED_SIG" "$SELF_REGISTRY" "$from_block" "$to_block")"; then
      log "Failed to fetch signer logs; retrying next loop."
      sleep "$POLL_INTERVAL_SECONDS"
      continue
    fi

    revocation_count="$(echo "$revocation_logs" | jq 'length')"
    signer_disabled_count="$(echo "$signer_logs" | jq --arg falseHex "$FALSE_BOOL_HEX" '[.[] | select((.data | ascii_downcase) == ($falseHex | ascii_downcase))] | length')"

    if (( revocation_count > 0 )); then
      log "Detected $revocation_count attestation revocation event(s)."
      if is_true "$REVOCATION_ROTATE_EPOCH"; then
        revocation_key="$(echo "$revocation_logs" | jq -r '.[0] | "\(.transactionHash)-\(.logIndex)"')"
        run_reactive_set_epoch "reactive:revocation-epoch:${revocation_key}" || true
      fi
    fi

    if (( signer_disabled_count > 0 )); then
      log "Detected $signer_disabled_count trusted-signer disable event(s)."
      if is_true "$SIGNER_DISABLE_PAUSE"; then
        current_paused="$(cast_call "$POLICY_ENGINE" "paused()(bool)")"
        if [[ "$current_paused" != "true" ]]; then
          signer_key="$(echo "$signer_logs" | jq --arg falseHex "$FALSE_BOOL_HEX" -r '[.[] | select((.data | ascii_downcase) == ($falseHex | ascii_downcase))][0] | "\(.transactionHash)-\(.logIndex)"')"
          run_reactive_pause_all true "reactive:signer-disabled-pause:${signer_key}" || true
        else
          log "Engine already paused; skip reactivePauseAll."
        fi
      fi
    fi

    last_processed_block="$to_block"
    write_state
  fi

  if (( EPOCH_ROTATION_SECONDS > 0 )); then
    now_ts="$(date +%s)"
    if (( next_epoch_rotation_ts == 0 )); then
      next_epoch_rotation_ts="$(( now_ts + EPOCH_ROTATION_SECONDS ))"
      write_state
    fi
    if (( now_ts >= next_epoch_rotation_ts )); then
      run_reactive_set_epoch "reactive:timer-epoch:${next_epoch_rotation_ts}" || true
      while (( now_ts >= next_epoch_rotation_ts )); do
        next_epoch_rotation_ts="$(( next_epoch_rotation_ts + EPOCH_ROTATION_SECONDS ))"
      done
      write_state
    fi
  fi

  if is_true "$RUN_ONCE"; then
    log "RUN_ONCE=true; exiting."
    exit 0
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done
