#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
ANVIL_PORT="${ANVIL_PORT:-8545}"
CHAIN_ID="${CHAIN_ID:-31337}"
START_ANVIL="${START_ANVIL:-1}"
ANVIL_LOG="${ANVIL_LOG:-/tmp/satisfy-anvil.log}"

# Default Anvil account #0 private key
DEPLOYER_PK="${DEPLOYER_PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
# Dedicated issuer keys used for proof signatures only
WORLD_ISSUER_PK="${WORLD_ISSUER_PK:-0x1000000000000000000000000000000000000000000000000000000000000001}"
SELF_ISSUER_PK="${SELF_ISSUER_PK:-0x2000000000000000000000000000000000000000000000000000000000000002}"

# This is the market participant whose credentials are being proven
SATISFY_USER="${SATISFY_USER:-0x0000000000000000000000000000000000001234}"

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

rpc() {
  local method="$1"
  local params_json="$2"

  local payload response
  payload=$(printf '{"jsonrpc":"2.0","id":1,"method":"%s","params":%s}' "$method" "$params_json")
  response=$(curl -sS -H "Content-Type: application/json" --data "$payload" "$RPC_URL")

  if echo "$response" | grep -q '"error"'; then
    echo "RPC error for $method: $response" >&2
    return 1
  fi

  echo "$response"
}

extract_result_string() {
  local json="$1"
  echo "$json" | tr -d '\n' | sed -n 's/.*"result":"\([^"]*\)".*/\1/p'
}

rpc_ready() {
  local out
  out=$(rpc "eth_blockNumber" "[]" 2>/dev/null || true)
  [[ -n "$(extract_result_string "$out")" ]]
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

wait_receipt() {
  local tx_hash="$1"
  local tries=0
  while true; do
    local receipt
    receipt=$(rpc "eth_getTransactionReceipt" "[\"$tx_hash\"]")

    if echo "$receipt" | grep -q '"result":null'; then
      tries=$((tries + 1))
      if ((tries > 120)); then
        echo "timed out waiting for receipt: $tx_hash" >&2
        exit 1
      fi
      sleep 0.25
      continue
    fi

    echo "$receipt"
    return 0
  done
}

receipt_status() {
  local receipt="$1"
  echo "$receipt" | tr -d '\n' | sed -n 's/.*"status":"\([^"]*\)".*/\1/p'
}

receipt_contract_address() {
  local receipt="$1"
  echo "$receipt" | tr -d '\n' | sed -n 's/.*"contractAddress":"\([^"]*\)".*/\1/p'
}

send_tx() {
  local to="$1"
  local data="$2"
  local expect_success="${3:-1}"

  local tx_obj resp tx_hash receipt status

  if [[ -n "$to" ]]; then
    tx_obj=$(printf '{"from":"%s","to":"%s","data":"%s"}' "$DEPLOYER_ADDR" "$to" "$data")
  else
    tx_obj=$(printf '{"from":"%s","data":"%s"}' "$DEPLOYER_ADDR" "$data")
  fi

  resp=$(rpc "eth_sendTransaction" "[$tx_obj]")
  tx_hash=$(extract_result_string "$resp")

  if [[ -z "$tx_hash" ]]; then
    echo "failed to send transaction: $resp" >&2
    exit 1
  fi

  receipt=$(wait_receipt "$tx_hash")
  status=$(receipt_status "$receipt")

  if [[ "$expect_success" == "1" && "$status" != "0x1" ]]; then
    echo "transaction reverted unexpectedly: $tx_hash" >&2
    echo "$receipt" >&2
    exit 1
  fi

  if [[ "$expect_success" == "0" && "$status" != "0x0" ]]; then
    echo "expected revert but tx succeeded: $tx_hash" >&2
    echo "$receipt" >&2
    exit 1
  fi

  echo "$receipt"
}

eth_call_raw() {
  local to="$1"
  local data="$2"

  local params resp
  params=$(printf '[{"to":"%s","data":"%s"},"latest"]' "$to" "$data")
  resp=$(rpc "eth_call" "$params")

  local result
  result=$(extract_result_string "$resp")
  if [[ -z "$result" ]]; then
    echo "failed eth_call decode: $resp" >&2
    exit 1
  fi

  echo "$result"
}

deploy_contract() {
  local contract_id="$1"
  local ctor_sig="$2"
  shift 2

  local bytecode ctor_args calldata receipt deployed
  bytecode=$(cd "$ROOT_DIR" && forge inspect "$contract_id" bytecode --offline)
  ctor_args=$(cast abi-encode "$ctor_sig" "$@")
  calldata="${bytecode}${ctor_args#0x}"

  receipt=$(send_tx "" "$calldata" 1)
  deployed=$(receipt_contract_address "$receipt")

  if [[ -z "$deployed" || "$deployed" == "null" ]]; then
    echo "failed to deploy $contract_id" >&2
    echo "$receipt" >&2
    exit 1
  fi

  echo "$deployed"
}

call_bool() {
  local to="$1"
  local sig="$2"
  shift 2

  local calldata raw
  calldata=$(cast calldata "$sig" "$@")
  raw=$(eth_call_raw "$to" "$calldata")
  cast decode-abi "f()(bool)" "$raw"
}

call_uint() {
  local to="$1"
  local sig="$2"
  shift 2

  local calldata raw decoded
  calldata=$(cast calldata "$sig" "$@")
  raw=$(eth_call_raw "$to" "$calldata")
  decoded=$(cast decode-abi "f()(uint256)" "$raw")
  echo "$decoded"
}

send_contract_tx() {
  local to="$1"
  local sig="$2"
  shift 2

  local calldata
  calldata=$(cast calldata "$sig" "$@")
  send_tx "$to" "$calldata" 1 >/dev/null
}

world_proof_payload() {
  local user="$1"
  local expires_at="$2"

  local packed digest sig
  packed=$(cast abi-encode --packed "f(string,address,bool,uint64)" "SATISFY_WORLD_ID_V1" "$user" true "$expires_at")
  digest=$(cast keccak "$packed")
  sig=$(cast wallet sign --private-key "$WORLD_ISSUER_PK" "$digest")

  cast abi-encode "f((bool,uint64,bytes))" "(true,$expires_at,$sig)"
}

self_proof_payload() {
  local user="$1"
  local age="$2"
  local contributor="$3"
  local dao_member="$4"
  local expires_at="$5"

  local packed digest sig
  packed=$(cast abi-encode --packed "f(string,address,uint8,bool,bool,uint64)" \
    "SATISFY_SELF_V1" "$user" "$age" "$contributor" "$dao_member" "$expires_at")
  digest=$(cast keccak "$packed")
  sig=$(cast wallet sign --private-key "$SELF_ISSUER_PK" "$digest")

  cast abi-encode "f((uint8,bool,bool,uint64,bytes))" "($age,$contributor,$dao_member,$expires_at,$sig)"
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
WORLD_ISSUER_ADDR=$(cast wallet address --private-key "$WORLD_ISSUER_PK")
SELF_ISSUER_ADDR=$(cast wallet address --private-key "$SELF_ISSUER_PK")

log "Building contracts"
(cd "$ROOT_DIR" && forge build --offline >/dev/null)

log "Deploying contracts"
ENGINE=$(deploy_contract "src/SatisfyPolicyEngine.sol:SatisfyPolicyEngine" "constructor(address)" "$DEPLOYER_ADDR")
WORLD_ADAPTER=$(deploy_contract "src/adapters/WorldIdAdapter.sol:WorldIdAdapter" "constructor(address,address)" "$DEPLOYER_ADDR" "$WORLD_ISSUER_ADDR")
SELF_ADAPTER=$(deploy_contract "src/adapters/SelfAdapter.sol:SelfAdapter" "constructor(address,address)" "$DEPLOYER_ADDR" "$SELF_ISSUER_ADDR")
HOOK=$(deploy_contract "src/SatisfyHook.sol:SatisfyHook" "constructor(address,address,address)" "$DEPLOYER_ADDR" "$ENGINE" "$DEPLOYER_ADDR")

WORLD_ID=$(cast keccak "WORLD_ID")
SELF_ID=$(cast keccak "SELF")
POOL_ID=$(cast keccak "HUMAN_DAO_POOL")

WORLD_CONDITION=$(cast abi-encode "f(bool)" true)
SELF_CONDITION=$(cast abi-encode "f((uint8,bool,bool))" "(18,true,false)")
PREDICATES="[(${WORLD_ID},${WORLD_CONDITION}),(${SELF_ID},${SELF_CONDITION})]"

log "Configuring policy engine and hook"
send_contract_tx "$ENGINE" "registerAdapter(bytes32,address)" "$WORLD_ID" "$WORLD_ADAPTER"
send_contract_tx "$ENGINE" "registerAdapter(bytes32,address)" "$SELF_ID" "$SELF_ADAPTER"
send_contract_tx "$ENGINE" "setAuthorizedConsumer(address,bool)" "$HOOK" true
send_contract_tx "$ENGINE" "createPolicy(uint8,(bytes32,bytes)[],uint64,uint64,bool)" 0 "$PREDICATES" 0 0 true
POLICY_ID=$(call_uint "$ENGINE" "policyCount()(uint256)")
send_contract_tx "$HOOK" "setPoolPolicy(bytes32,uint256)" "$POOL_ID" "$POLICY_ID"

CURRENT_EPOCH=$(call_uint "$ENGINE" "currentEpoch()(uint256)")
EXPIRES_AT=$(( $(date +%s) + 86400 ))

WORLD_PROOF=$(world_proof_payload "$SATISFY_USER" "$EXPIRES_AT")
SELF_PROOF=$(self_proof_payload "$SATISFY_USER" 25 true false "$EXPIRES_AT")

PROOFS="[(${WORLD_ID},${WORLD_PROOF}),(${SELF_ID},${SELF_PROOF})]"
NULLIFIER_1=$(cast keccak "nullifier-1")
BUNDLE_1="(${PROOFS},${NULLIFIER_1},${CURRENT_EPOCH})"

log "Verifying satisfies() with valid proofs"
SAT_OK=$(
  call_bool "$ENGINE" "satisfies(uint256,address,((bytes32,bytes)[],bytes32,uint64))(bool)" "$POLICY_ID" "$SATISFY_USER" "$BUNDLE_1"
)
if [[ "$SAT_OK" != "true" ]]; then
  echo "expected satisfies() to be true, got: $SAT_OK" >&2
  exit 1
fi

log "Executing beforeSwap with valid proof bundle"
DATA_BEFORE_SWAP=$(
  cast calldata "beforeSwap(bytes32,address,((bytes32,bytes)[],bytes32,uint64))(bytes4)" "$POOL_ID" "$SATISFY_USER" "$BUNDLE_1"
)
send_tx "$HOOK" "$DATA_BEFORE_SWAP" 1 >/dev/null

log "Checking replay protection (expected revert)"
send_tx "$HOOK" "$DATA_BEFORE_SWAP" 0 >/dev/null

log "Rotating epoch and submitting fresh bundle"
send_contract_tx "$ENGINE" "setEpoch(uint64)" 2
NEW_EPOCH=$(call_uint "$ENGINE" "currentEpoch()(uint256)")
NULLIFIER_2=$(cast keccak "nullifier-2")
BUNDLE_2="(${PROOFS},${NULLIFIER_2},${NEW_EPOCH})"

OLD_EPOCH_VALID=$(
  call_bool "$ENGINE" "satisfies(uint256,address,((bytes32,bytes)[],bytes32,uint64))(bool)" "$POLICY_ID" "$SATISFY_USER" "$BUNDLE_1"
)
if [[ "$OLD_EPOCH_VALID" != "false" ]]; then
  echo "expected old epoch bundle to be invalid, got: $OLD_EPOCH_VALID" >&2
  exit 1
fi

DATA_BEFORE_SWAP_2=$(
  cast calldata "beforeSwap(bytes32,address,((bytes32,bytes)[],bytes32,uint64))(bytes4)" "$POOL_ID" "$SATISFY_USER" "$BUNDLE_2"
)
send_tx "$HOOK" "$DATA_BEFORE_SWAP_2" 1 >/dev/null

log "Checking policy mismatch with underage self proof"
UNDERAGE_SELF_PROOF=$(self_proof_payload "$SATISFY_USER" 16 true false "$EXPIRES_AT")
NULLIFIER_3=$(cast keccak "nullifier-3")
UNDERAGE_PROOFS="[(${WORLD_ID},${WORLD_PROOF}),(${SELF_ID},${UNDERAGE_SELF_PROOF})]"
UNDERAGE_BUNDLE="(${UNDERAGE_PROOFS},${NULLIFIER_3},${NEW_EPOCH})"
UNDERAGE_OK=$(
  call_bool "$ENGINE" "satisfies(uint256,address,((bytes32,bytes)[],bytes32,uint64))(bool)" "$POLICY_ID" "$SATISFY_USER" "$UNDERAGE_BUNDLE"
)
if [[ "$UNDERAGE_OK" != "false" ]]; then
  echo "expected underage bundle to fail policy, got: $UNDERAGE_OK" >&2
  exit 1
fi

log "Scenario complete"
log "Deployer:      $DEPLOYER_ADDR"
log "PolicyEngine:  $ENGINE"
log "WorldAdapter:  $WORLD_ADAPTER"
log "SelfAdapter:   $SELF_ADAPTER"
log "Hook:          $HOOK"
log "PolicyId:      $POLICY_ID"

if [[ -n "$ANVIL_PID" ]]; then
  log "Anvil log:     $ANVIL_LOG"
fi
