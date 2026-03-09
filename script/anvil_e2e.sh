#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
ANVIL_PORT="${ANVIL_PORT:-8545}"
CHAIN_ID="${CHAIN_ID:-31337}"
START_ANVIL="${START_ANVIL:-1}"
ANVIL_LOG="${ANVIL_LOG:-/tmp/satisfy-anvil.log}"

DEPLOYER_PK="${DEPLOYER_PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
SELF_SIGNER_PK="${SELF_SIGNER_PK:-0x1000000000000000000000000000000000000000000000000000000000000001}"
REACTIVE_WORKER_PK="${REACTIVE_WORKER_PK:-0x2000000000000000000000000000000000000000000000000000000000000002}"
RELAYER_PK="${RELAYER_PK:-$DEPLOYER_PK}"

SATISFY_USER="${SATISFY_USER:-0x0000000000000000000000000000000000001234}"
WORLD_POLICY_CONTEXT="${WORLD_POLICY_CONTEXT:-$(cast keccak "ANVIL_WORLD_POLICY_CONTEXT")}" 

ANVIL_PID=""

log() {
  echo "[satisfy-e2e] $*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

cleanup() {
  if [[ -n "${ANVIL_PID}" ]]; then
    kill "${ANVIL_PID}" >/dev/null 2>&1 || true
    wait "${ANVIL_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

rpc_ready() {
  local payload response
  payload='{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'
  response=$(curl -sS -H "Content-Type: application/json" --data "$payload" "$RPC_URL" 2>/dev/null || true)
  [[ "$response" == *"\"result\":"* ]]
}

wait_for_rpc() {
  local tries=0
  until rpc_ready; do
    tries=$((tries + 1))
    if ((tries > 80)); then
      echo "RPC did not come up at $RPC_URL" >&2
      exit 1
    fi
    sleep 0.25
  done
}

send_tx() {
  send_tx_with_key "$DEPLOYER_PK" "$@"
}

send_tx_with_key() {
  local private_key="$1"
  local to="$2"
  local sig="$3"
  shift 3

  cast send "$to" "$sig" "$@" \
    --rpc-url "$RPC_URL" \
    --private-key "$private_key" >/dev/null
}

send_expect_revert() {
  send_expect_revert_with_key "$DEPLOYER_PK" "$@"
}

send_expect_revert_with_key() {
  local private_key="$1"
  local to="$2"
  local sig="$3"
  shift 3

  if cast send "$to" "$sig" "$@" --rpc-url "$RPC_URL" --private-key "$private_key" >/dev/null 2>&1; then
    echo "expected revert but tx succeeded for $sig" >&2
    exit 1
  fi
}

call_view() {
  local to="$1"
  local sig="$2"
  shift 2

  cast call "$to" "$sig" "$@" --rpc-url "$RPC_URL"
}

deploy_contract() {
  local contract_id="$1"
  shift

  local output deployed
  local cmd=(
    forge create "$contract_id"
    --rpc-url "$RPC_URL"
    --private-key "$DEPLOYER_PK"
    --broadcast
  )
  if (( $# > 0 )); then
    cmd+=(--constructor-args "$@")
  fi
  output=$(cd "$ROOT_DIR" && "${cmd[@]}" 2>&1)

  deployed=$(echo "$output" | sed -n 's/^Deployed to: //p' | tail -n1)
  if [[ -z "$deployed" ]]; then
    echo "failed to deploy $contract_id" >&2
    echo "$output" >&2
    exit 1
  fi

  echo "$deployed"
}

require_cmd anvil
require_cmd cast
require_cmd forge
require_cmd curl

if rpc_ready; then
  log "Using existing RPC at $RPC_URL"
else
  if [[ "$START_ANVIL" != "1" ]]; then
    echo "RPC unavailable at $RPC_URL and START_ANVIL=$START_ANVIL" >&2
    exit 1
  fi

  log "Starting Anvil on port $ANVIL_PORT"
  anvil --port "$ANVIL_PORT" --chain-id "$CHAIN_ID" --silent >"$ANVIL_LOG" 2>&1 &
  ANVIL_PID=$!
  wait_for_rpc
fi

DEPLOYER_ADDR=$(cast wallet address --private-key "$DEPLOYER_PK")
SELF_SIGNER_ADDR=$(cast wallet address --private-key "$SELF_SIGNER_PK")
REACTIVE_WORKER_ADDR=$(cast wallet address --private-key "$REACTIVE_WORKER_PK")

log "Building contracts"
(cd "$ROOT_DIR" && forge build --offline >/dev/null)

log "Deploying contracts"
ENGINE=$(deploy_contract "src/SatisfyPolicyEngine.sol:SatisfyPolicyEngine" "$DEPLOYER_ADDR")
WORLD_VERIFIER=$(deploy_contract "src/mocks/MockWorldIdVerifier.sol:MockWorldIdVerifier")
SELF_REGISTRY=$(deploy_contract "src/SelfAttestationRegistry.sol:SelfAttestationRegistry" "$DEPLOYER_ADDR" "$SELF_SIGNER_ADDR")
WORLD_ADAPTER=$(deploy_contract "src/adapters/WorldIdAdapter.sol:WorldIdAdapter" "$DEPLOYER_ADDR" "$WORLD_VERIFIER" 1)
SELF_ADAPTER=$(deploy_contract "src/adapters/SelfAdapter.sol:SelfAdapter" "$DEPLOYER_ADDR" "$SELF_REGISTRY")
HOOK=$(deploy_contract "src/SatisfyHook.sol:SatisfyHook" "$DEPLOYER_ADDR" "$ENGINE" "$DEPLOYER_ADDR")
TIMELOCK=$(deploy_contract "src/SatisfyTimelock.sol:SatisfyTimelock" "$DEPLOYER_ADDR" 0 "$DEPLOYER_ADDR" "$DEPLOYER_ADDR")
GATEWAY=$(deploy_contract "src/SatisfyReactiveGateway.sol:SatisfyReactiveGateway" "$DEPLOYER_ADDR" "0x0000000000000000000000000000000000000000" "$REACTIVE_WORKER_ADDR")
AUTOMATION=$(deploy_contract \
  "src/SatisfyAutomationModule.sol:SatisfyAutomationModule" \
  "$DEPLOYER_ADDR" \
  "$DEPLOYER_ADDR" \
  "$DEPLOYER_ADDR" \
  "$DEPLOYER_ADDR" \
  "$DEPLOYER_ADDR" \
  "$GATEWAY" \
  "$DEPLOYER_ADDR" \
  "$ENGINE" \
  "$HOOK" \
  "$WORLD_ADAPTER" \
  "$SELF_ADAPTER" \
  "$SELF_REGISTRY")

send_tx "$GATEWAY" "setAutomationModule(address)" "$AUTOMATION"

WORLD_ID=$(cast keccak "WORLD_ID")
SELF_ID=$(cast keccak "SELF")
POOL_ID=$(cast keccak "HUMAN_DAO_POOL")

WORLD_CONDITION=$(cast abi-encode "f((bool,bytes32,bytes32,uint64))" "(true,0x0000000000000000000000000000000000000000000000000000000000000000,$WORLD_POLICY_CONTEXT,86400)")
SELF_CONDITION=$(cast abi-encode "f((uint8,bool,bool,uint64,uint64,bytes32))" "(18,true,false,86400,0,0x0000000000000000000000000000000000000000000000000000000000000000)")
PREDICATES="[(${WORLD_ID},${WORLD_CONDITION}),(${SELF_ID},${SELF_CONDITION})]"

log "Configuring policy engine and hook"
send_tx "$ENGINE" "registerAdapter(bytes32,address)" "$WORLD_ID" "$WORLD_ADAPTER"
send_tx "$ENGINE" "registerAdapter(bytes32,address)" "$SELF_ID" "$SELF_ADAPTER"
send_tx "$ENGINE" "setAuthorizedConsumer(address,bool)" "$HOOK" true
send_tx "$ENGINE" "createPolicy(uint8,(bytes32,bytes)[],uint64,uint64,bool)" 0 "$PREDICATES" 0 0 true
POLICY_ID=$(call_view "$ENGINE" "policyCount()(uint256)")
send_tx "$HOOK" "setPoolPolicy(bytes32,uint256)" "$POOL_ID" "$POLICY_ID"

log "Transferring ownership to automation module"
send_tx "$ENGINE" "transferOwnership(address)" "$AUTOMATION"
send_tx "$HOOK" "transferOwnership(address)" "$AUTOMATION"
send_tx "$WORLD_ADAPTER" "transferOwnership(address)" "$AUTOMATION"
send_tx "$SELF_ADAPTER" "transferOwnership(address)" "$AUTOMATION"
send_tx "$SELF_REGISTRY" "transferOwnership(address)" "$AUTOMATION"

CURRENT_EPOCH=$(call_view "$ENGINE" "currentEpoch()(uint64)")
EXPIRES_AT=$(( $(date +%s) + 86400 ))
ISSUED_AT=$(date +%s)

WORLD_EXTERNAL_NULLIFIER=$(cast keccak "$(cast abi-encode --packed "f(uint256,address,bytes32)" "$CHAIN_ID" "$WORLD_ADAPTER" "$WORLD_POLICY_CONTEXT")")
WORLD_SIGNAL=$(cast keccak "$(cast abi-encode --packed "f(uint256,address,address,bytes32,bytes32)" "$CHAIN_ID" "$WORLD_ADAPTER" "$SATISFY_USER" "$WORLD_POLICY_CONTEXT" "$WORLD_EXTERNAL_NULLIFIER")")

WORLD_ROOT=111
WORLD_NULLIFIER_HASH=222
WORLD_PROOF_ARRAY="[1,2,3,4,5,6,7,8]"

send_tx \
  "$WORLD_VERIFIER" \
  "setValidProof(uint256,uint256,uint256,uint256,uint256,uint256[8],bool)" \
  "$WORLD_ROOT" \
  1 \
  "$WORLD_SIGNAL" \
  "$WORLD_NULLIFIER_HASH" \
  "$WORLD_EXTERNAL_NULLIFIER" \
  "$WORLD_PROOF_ARRAY" \
  true

WORLD_PROOF=$(cast abi-encode "f((uint256,uint256,uint256[8],uint64,uint64,bytes32,bytes32))" "($WORLD_ROOT,$WORLD_NULLIFIER_HASH,$WORLD_PROOF_ARRAY,$ISSUED_AT,$EXPIRES_AT,$WORLD_SIGNAL,$WORLD_EXTERNAL_NULLIFIER)")

SELF_CONTEXT=$(cast keccak "$(cast abi-encode --packed "f(uint256,address,address,bytes)" "$CHAIN_ID" "$SELF_ADAPTER" "$SATISFY_USER" "$SELF_CONDITION")")
ATTESTATION_ID=$(cast keccak "self-attestation-live")
SELF_NONCE=$(call_view "$SELF_REGISTRY" "nextNonce(address)(uint256)" "$SELF_SIGNER_ADDR")
SOURCE_BRIDGE_ID=$(cast keccak "ANVIL_BRIDGE")
SOURCE_TX_HASH=$(cast keccak "anvil-source-tx")
SELF_PAYLOAD="($ATTESTATION_ID,$SATISFY_USER,25,true,false,$ISSUED_AT,$EXPIRES_AT,$SELF_CONTEXT,$CHAIN_ID,$SOURCE_BRIDGE_ID,$SOURCE_TX_HASH,0,$SELF_NONCE)"
SELF_DIGEST=$(call_view "$SELF_REGISTRY" "attestationDigest((bytes32,address,uint8,bool,bool,uint64,uint64,bytes32,uint64,bytes32,bytes32,uint32,uint256))(bytes32)" "$SELF_PAYLOAD")
SELF_SIGNATURE=$(cast wallet sign --private-key "$SELF_SIGNER_PK" --no-hash "$SELF_DIGEST")

send_tx "$SELF_REGISTRY" "submitAttestation((bytes32,address,uint8,bool,bool,uint64,uint64,bytes32,uint64,bytes32,bytes32,uint32,uint256),bytes)" "$SELF_PAYLOAD" "$SELF_SIGNATURE"
SELF_PROOF=$(cast abi-encode "f((bytes32,bytes32))" "($ATTESTATION_ID,$SELF_CONTEXT)")

PROOFS="[(${WORLD_ID},${WORLD_PROOF}),(${SELF_ID},${SELF_PROOF})]"
NULLIFIER_1=$(cast keccak "nullifier-1")
BUNDLE_1="(${PROOFS},${NULLIFIER_1},${CURRENT_EPOCH})"

log "Verifying satisfies() with valid proofs"
SAT_OK=$(call_view "$ENGINE" "satisfies(uint256,address,((bytes32,bytes)[],bytes32,uint64))(bool)" "$POLICY_ID" "$SATISFY_USER" "$BUNDLE_1")
if [[ "$SAT_OK" != "true" ]]; then
  echo "expected satisfies() to be true, got: $SAT_OK" >&2
  exit 1
fi

log "Executing beforeSwap with valid proof bundle"
send_tx "$HOOK" "beforeSwap(bytes32,address,((bytes32,bytes)[],bytes32,uint64))(bytes4)" "$POOL_ID" "$SATISFY_USER" "$BUNDLE_1"

log "Checking replay protection (expected revert)"
send_expect_revert "$HOOK" "beforeSwap(bytes32,address,((bytes32,bytes)[],bytes32,uint64))(bytes4)" "$POOL_ID" "$SATISFY_USER" "$BUNDLE_1"

ACTION_SET_EPOCH=$(call_view "$GATEWAY" "ACTION_SET_EPOCH()(uint8)")
ACTION_PAUSE_ALL=$(call_view "$GATEWAY" "ACTION_PAUSE_ALL()(uint8)")

submit_gateway_job() {
  local action="$1"
  local payload="$2"
  local reason="$3"
  local job_id nonce valid_until job digest signature

  job_id=$(cast keccak "$reason")
  nonce=$(call_view "$GATEWAY" "nextNonce(address)(uint256)" "$REACTIVE_WORKER_ADDR")
  valid_until=$(( $(date +%s) + 3600 ))
  job="($job_id,$action,$payload,$valid_until,$nonce)"
  digest=$(call_view "$GATEWAY" "jobDigest((bytes32,uint8,bytes,uint64,uint256))(bytes32)" "$job")
  signature=$(cast wallet sign --private-key "$REACTIVE_WORKER_PK" --no-hash "$digest")

  send_tx_with_key "$RELAYER_PK" "$GATEWAY" "execute((bytes32,uint8,bytes,uint64,uint256),bytes)" "$job" "$signature"
}

log "Rotating epoch via reactive gateway worker job and submitting fresh bundle"
SET_EPOCH_PAYLOAD=$(cast abi-encode "f(uint64)" 2)
submit_gateway_job "$ACTION_SET_EPOCH" "$SET_EPOCH_PAYLOAD" "job-rotate-epoch-2"
NEW_EPOCH=$(call_view "$ENGINE" "currentEpoch()(uint64)")
NULLIFIER_2=$(cast keccak "nullifier-2")
BUNDLE_2="(${PROOFS},${NULLIFIER_2},${NEW_EPOCH})"

OLD_EPOCH_VALID=$(call_view "$ENGINE" "satisfies(uint256,address,((bytes32,bytes)[],bytes32,uint64))(bool)" "$POLICY_ID" "$SATISFY_USER" "$BUNDLE_1")
if [[ "$OLD_EPOCH_VALID" != "false" ]]; then
  echo "expected old epoch bundle to be invalid, got: $OLD_EPOCH_VALID" >&2
  exit 1
fi

send_tx "$HOOK" "beforeSwap(bytes32,address,((bytes32,bytes)[],bytes32,uint64))(bytes4)" "$POOL_ID" "$SATISFY_USER" "$BUNDLE_2"

log "Pausing engine + hook via reactive gateway worker job and checking enforcement"
PAUSE_PAYLOAD=$(cast abi-encode "f(bool)" true)
submit_gateway_job "$ACTION_PAUSE_ALL" "$PAUSE_PAYLOAD" "job-pause-all-true"
send_expect_revert "$HOOK" "beforeSwap(bytes32,address,((bytes32,bytes)[],bytes32,uint64))(bytes4)" "$POOL_ID" "$SATISFY_USER" "$BUNDLE_2"
UNPAUSE_PAYLOAD=$(cast abi-encode "f(bool)" false)
submit_gateway_job "$ACTION_PAUSE_ALL" "$UNPAUSE_PAYLOAD" "job-pause-all-false"

log "E2E succeeded"
log "PolicyEngine:  $ENGINE"
log "Hook:          $HOOK"
log "WorldAdapter:  $WORLD_ADAPTER"
log "SelfAdapter:   $SELF_ADAPTER"
log "SelfRegistry:  $SELF_REGISTRY"
log "WorldVerifier: $WORLD_VERIFIER"
log "Timelock:      $TIMELOCK"
log "Automation:    $AUTOMATION"
log "Gateway:       $GATEWAY"
log "PolicyId:      $POLICY_ID"
log "PoolId:        $POOL_ID"
log "Epoch:         $NEW_EPOCH"

cat <<EOFVARS

# Frontend local values (custom mode)
VITE_DEFAULT_NETWORK=custom
VITE_RPC_URL=$RPC_URL
VITE_CHAIN_ID=$CHAIN_ID
VITE_POLICY_ENGINE_ADDRESS=$ENGINE
VITE_HOOK_ADDRESS=$HOOK
VITE_POLICY_ID=$POLICY_ID
VITE_POOL_ID=$POOL_ID
VITE_EPOCH=$NEW_EPOCH
VITE_WORLD_ADAPTER_ID=$WORLD_ID
VITE_SELF_ADAPTER_ID=$SELF_ID
VITE_WORLD_PROOF_PAYLOAD=$WORLD_PROOF
VITE_SELF_PROOF_PAYLOAD=$SELF_PROOF
VITE_NULLIFIER=$NULLIFIER_2
EOFVARS
