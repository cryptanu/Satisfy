#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEPLOYMENT_FILE="${1:-${DEPLOYMENT_FILE:-$ROOT_DIR/deployments/unichain-sepolia.json}}"
RPC_URL="${RPC_URL:-}"
RPC_TIMEOUT="${RPC_TIMEOUT:-120}"
DEPLOYER_PK="${DEPLOYER_PK:-}"
FORCE_NONCE_START="${FORCE_NONCE_START:-}"
FORCE_SOURCE_NONCE_START="${FORCE_SOURCE_NONCE_START:-$FORCE_NONCE_START}"
FORCE_LASNA_NONCE_START="${FORCE_LASNA_NONCE_START:-}"

LASNA_RPC_URL="${LASNA_RPC_URL:-https://lasna-rpc.rnk.dev}"
LASNA_CHAIN_ID="${LASNA_CHAIN_ID:-5318007}"
LASNA_DEPLOYER_PK="${LASNA_DEPLOYER_PK:-$DEPLOYER_PK}"
LASNA_PROCESSOR_VALUE="${LASNA_PROCESSOR_VALUE:-0.01ether}"

REACTIVE_CALLBACK_GAS_LIMIT="${REACTIVE_CALLBACK_GAS_LIMIT:-500000}"
REVOCATION_ROTATE_EPOCH="${REVOCATION_ROTATE_EPOCH:-true}"
SIGNER_DISABLE_PAUSE="${SIGNER_DISABLE_PAUSE:-true}"
CALLBACK_OWNER="${CALLBACK_OWNER:-}"
REACTIVE_CALLBACK_SENDER="${REACTIVE_CALLBACK_SENDER:-}"

strip_ansi() {
  sed -E 's/\x1B\[[0-9;]*[mK]//g'
}

log() {
  echo "[deploy-reactive] $*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_cmd forge
require_cmd cast
require_cmd jq

if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
  echo "deployment artifact not found: $DEPLOYMENT_FILE" >&2
  exit 1
fi

if [[ -z "$DEPLOYER_PK" ]]; then
  echo "DEPLOYER_PK is required." >&2
  exit 1
fi
if [[ -z "$LASNA_DEPLOYER_PK" ]]; then
  echo "LASNA_DEPLOYER_PK is required (or set DEPLOYER_PK)." >&2
  exit 1
fi

if [[ -z "$RPC_URL" ]]; then
  RPC_URL="$(jq -r '.rpcUrl' "$DEPLOYMENT_FILE")"
fi

SOURCE_CHAIN_ID="$(jq -r '.chainId' "$DEPLOYMENT_FILE")"
SOURCE_SELF_REGISTRY="$(jq -r '.selfRegistry' "$DEPLOYMENT_FILE")"
SOURCE_POLICY_ENGINE="$(jq -r '.policyEngine' "$DEPLOYMENT_FILE")"
SOURCE_GATEWAY="$(jq -r '.reactiveGateway // empty' "$DEPLOYMENT_FILE")"

if [[ -z "$SOURCE_GATEWAY" || "$SOURCE_GATEWAY" == "null" ]]; then
  echo "reactiveGateway missing from deployment artifact; redeploy Unichain contracts first." >&2
  exit 1
fi

DEPLOYER_ADDR="$(cast wallet address --private-key "$DEPLOYER_PK")"
LASNA_DEPLOYER_ADDR="$(cast wallet address --private-key "$LASNA_DEPLOYER_PK")"
if [[ -z "$CALLBACK_OWNER" ]]; then
  CALLBACK_OWNER="$DEPLOYER_ADDR"
fi

if [[ -z "$REACTIVE_CALLBACK_SENDER" ]]; then
  case "$SOURCE_CHAIN_ID" in
    1301)
      # Reactive callback proxy for Unichain Sepolia.
      REACTIVE_CALLBACK_SENDER="0x4d7d194675E6844f7E23C1e830d6A03071DF4f4D"
      ;;
    130)
      # Reactive callback proxy for Unichain Mainnet.
      REACTIVE_CALLBACK_SENDER="0x32DA1ecA6fD77A54651223E317915A6f9f8D4f94"
      ;;
    *)
      echo "REACTIVE_CALLBACK_SENDER is required for source chainId=$SOURCE_CHAIN_ID." >&2
      exit 1
      ;;
  esac
fi

current_source_chain_id="$(cast chain-id --rpc-url "$RPC_URL")"
if [[ "$current_source_chain_id" != "$SOURCE_CHAIN_ID" ]]; then
  echo "RPC_URL chain mismatch: artifact chainId=$SOURCE_CHAIN_ID, rpc chainId=$current_source_chain_id" >&2
  exit 1
fi

current_lasna_chain_id="$(cast chain-id --rpc-url "$LASNA_RPC_URL")"
if [[ "$current_lasna_chain_id" != "$LASNA_CHAIN_ID" ]]; then
  echo "LASNA_RPC_URL chain mismatch: expected $LASNA_CHAIN_ID, got $current_lasna_chain_id" >&2
  exit 1
fi

SOURCE_LATEST_NONCE="$(cast nonce "$DEPLOYER_ADDR" --rpc-url "$RPC_URL" --block latest)"
SOURCE_PENDING_NONCE="$(cast nonce "$DEPLOYER_ADDR" --rpc-url "$RPC_URL" --block pending)"
if [[ -n "$FORCE_SOURCE_NONCE_START" ]]; then
  SOURCE_NEXT_NONCE="$FORCE_SOURCE_NONCE_START"
else
  SOURCE_NEXT_NONCE="$SOURCE_LATEST_NONCE"
fi

LASNA_LATEST_NONCE="$(cast nonce "$LASNA_DEPLOYER_ADDR" --rpc-url "$LASNA_RPC_URL" --block latest)"
LASNA_PENDING_NONCE="$(cast nonce "$LASNA_DEPLOYER_ADDR" --rpc-url "$LASNA_RPC_URL" --block pending)"
if [[ -n "$FORCE_LASNA_NONCE_START" ]]; then
  LASNA_NEXT_NONCE="$FORCE_LASNA_NONCE_START"
else
  LASNA_NEXT_NONCE="$LASNA_LATEST_NONCE"
fi

deploy_contract() {
  local rpc_url="$1"
  local chain_id="$2"
  local private_key="$3"
  local value="$4"
  local from_addr="$5"
  local nonce="$6"
  local contract_id="$7"
  shift 7

  local cmd output deployed
  cmd=(
    forge create "$contract_id"
    --rpc-url "$rpc_url"
    --rpc-timeout "$RPC_TIMEOUT"
    --chain "$chain_id"
    --from "$from_addr"
    --nonce "$nonce"
    --private-key "$private_key"
    --broadcast
  )
  if [[ -n "$value" ]]; then
    cmd+=(--value "$value")
  fi
  if (( $# > 0 )); then
    cmd+=(--constructor-args "$@")
  fi

  output=$(cd "$ROOT_DIR" && "${cmd[@]}" 2>&1)
  if echo "$output" | grep -qi "nonce too low"; then
    echo "nonce too low deploying $contract_id on chain $chain_id (used nonce=$nonce)" >&2
    echo "$output" >&2
    exit 1
  fi
  deployed="$(echo "$output" | strip_ansi | sed -n 's/^Deployed to: //p' | tail -n1)"
  if [[ -z "$deployed" ]]; then
    echo "failed to parse deployed address for $contract_id" >&2
    echo "$output" >&2
    exit 1
  fi
  echo "$deployed"
}

send_source_tx() {
  local to="$1"
  local sig="$2"
  shift 2
  local tx_nonce="$SOURCE_NEXT_NONCE"
  local output
  output="$(cast send \
    "$to" \
    "$sig" \
    "$@" \
    --rpc-url "$RPC_URL" \
    --rpc-timeout "$RPC_TIMEOUT" \
    --chain "$SOURCE_CHAIN_ID" \
    --from "$DEPLOYER_ADDR" \
    --nonce "$tx_nonce" \
    --private-key "$DEPLOYER_PK" 2>&1)"
  if echo "$output" | grep -qi "nonce too low"; then
    echo "nonce too low sending $sig to $to on source chain (used nonce=$tx_nonce)" >&2
    echo "$output" >&2
    exit 1
  fi
  SOURCE_NEXT_NONCE="$((SOURCE_NEXT_NONCE + 1))"
}

log "Source RPC: $RPC_URL (chainId=$SOURCE_CHAIN_ID)"
log "Lasna RPC:  $LASNA_RPC_URL (chainId=$LASNA_CHAIN_ID)"
log "Source deployer: $DEPLOYER_ADDR"
log "Lasna deployer:  $LASNA_DEPLOYER_ADDR"
log "Source gateway:  $SOURCE_GATEWAY"
log "Source registry: $SOURCE_SELF_REGISTRY"
log "Callback sender: $REACTIVE_CALLBACK_SENDER"
log "Source nonce latest/pending/start: $SOURCE_LATEST_NONCE/$SOURCE_PENDING_NONCE/$SOURCE_NEXT_NONCE"
log "Lasna nonce latest/pending/start:  $LASNA_LATEST_NONCE/$LASNA_PENDING_NONCE/$LASNA_NEXT_NONCE"

log "Deploying SatisfyReactiveCallbackReceiver on source chain"
CALLBACK_RECEIVER="$(
  deploy_contract \
    "$RPC_URL" \
    "$SOURCE_CHAIN_ID" \
    "$DEPLOYER_PK" \
    "" \
    "$DEPLOYER_ADDR" \
    "$SOURCE_NEXT_NONCE" \
    "src/reactive/SatisfyReactiveCallbackReceiver.sol:SatisfyReactiveCallbackReceiver" \
    "$CALLBACK_OWNER" \
    "$REACTIVE_CALLBACK_SENDER" \
    "$LASNA_DEPLOYER_ADDR" \
    "$SOURCE_GATEWAY" \
    "$SOURCE_POLICY_ENGINE"
)"
SOURCE_NEXT_NONCE="$((SOURCE_NEXT_NONCE + 1))"
log "Callback receiver (source): $CALLBACK_RECEIVER"

gateway_owner="$(cast call "$SOURCE_GATEWAY" "owner()(address)" --rpc-url "$RPC_URL" --rpc-timeout "$RPC_TIMEOUT")"
if [[ "$(printf '%s' "$gateway_owner" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$DEPLOYER_ADDR" | tr '[:upper:]' '[:lower:]')" ]]; then
  echo "DEPLOYER_PK is not owner of SatisfyReactiveGateway." >&2
  echo "Gateway owner: $gateway_owner" >&2
  echo "Deployer:     $DEPLOYER_ADDR" >&2
  echo "Use gateway owner key or run authorization through governance." >&2
  exit 1
fi

log "Authorizing callback receiver on SatisfyReactiveGateway"
send_source_tx \
  "$SOURCE_GATEWAY" \
  "setReactiveCallback(address,bool)" \
  "$CALLBACK_RECEIVER" \
  true

authorized="$(cast call "$SOURCE_GATEWAY" "authorizedReactiveCallbacks(address)(bool)" "$CALLBACK_RECEIVER" --rpc-url "$RPC_URL" --rpc-timeout "$RPC_TIMEOUT")"
for _ in {1..10}; do
  if [[ "$authorized" == "true" ]]; then
    break
  fi
  sleep 2
  authorized="$(cast call "$SOURCE_GATEWAY" "authorizedReactiveCallbacks(address)(bool)" "$CALLBACK_RECEIVER" --rpc-url "$RPC_URL" --rpc-timeout "$RPC_TIMEOUT")"
done
if [[ "$authorized" != "true" ]]; then
  echo "failed to authorize callback receiver on gateway" >&2
  echo "Gateway: $SOURCE_GATEWAY" >&2
  echo "Callback receiver: $CALLBACK_RECEIVER" >&2
  exit 1
fi

log "Deploying SatisfyLasnaReactiveProcessor on Lasna"
LASNA_PROCESSOR="$(
  deploy_contract \
    "$LASNA_RPC_URL" \
    "$LASNA_CHAIN_ID" \
    "$LASNA_DEPLOYER_PK" \
    "$LASNA_PROCESSOR_VALUE" \
    "$LASNA_DEPLOYER_ADDR" \
    "$LASNA_NEXT_NONCE" \
    "src/reactive/SatisfyLasnaReactiveProcessor.sol:SatisfyLasnaReactiveProcessor" \
    "$LASNA_DEPLOYER_ADDR" \
    "$SOURCE_CHAIN_ID" \
    "$SOURCE_SELF_REGISTRY" \
    "$SOURCE_CHAIN_ID" \
    "$CALLBACK_RECEIVER" \
    "$REACTIVE_CALLBACK_GAS_LIMIT" \
    "$REVOCATION_ROTATE_EPOCH" \
    "$SIGNER_DISABLE_PAUSE"
)"
LASNA_NEXT_NONCE="$((LASNA_NEXT_NONCE + 1))"

tmp="$(mktemp)"
jq \
  --arg callbackReceiver "$CALLBACK_RECEIVER" \
  --arg callbackSender "$REACTIVE_CALLBACK_SENDER" \
  --arg reactiveOwner "$LASNA_DEPLOYER_ADDR" \
  --arg lasnaProcessor "$LASNA_PROCESSOR" \
  --arg lasnaRpcUrl "$LASNA_RPC_URL" \
  --argjson lasnaChainId "$LASNA_CHAIN_ID" \
  --argjson callbackGasLimit "$REACTIVE_CALLBACK_GAS_LIMIT" \
  --arg revocationRotate "$REVOCATION_ROTATE_EPOCH" \
  --arg signerDisablePause "$SIGNER_DISABLE_PAUSE" \
  '
  .reactiveNetwork = {
    enabled: true,
    mode: "lasna-reactive-callback",
    lasnaChainId: $lasnaChainId,
    lasnaRpcUrl: $lasnaRpcUrl,
    lasnaProcessor: $lasnaProcessor,
    sourceChainId: .chainId,
    sourceSelfRegistry: .selfRegistry,
    destinationChainId: .chainId,
    destinationCallbackReceiver: $callbackReceiver,
    destinationCallbackSender: $callbackSender,
    reactiveOwner: $reactiveOwner,
    callbackGasLimit: $callbackGasLimit,
    revocationRotateEpoch: ($revocationRotate | ascii_downcase | . == "true"),
    signerDisablePause: ($signerDisablePause | ascii_downcase | . == "true")
  }' "$DEPLOYMENT_FILE" > "$tmp"
mv "$tmp" "$DEPLOYMENT_FILE"

log "Reactive pipeline deployed"
log "CallbackReceiver (source): $CALLBACK_RECEIVER"
log "LasnaProcessor:            $LASNA_PROCESSOR"
log "Updated artifact:          $DEPLOYMENT_FILE"
