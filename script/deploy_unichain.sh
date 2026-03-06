#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

UNICHAIN_NETWORK="${UNICHAIN_NETWORK:-sepolia}"

case "$UNICHAIN_NETWORK" in
  sepolia)
    CHAIN_ID="1301"
    DEFAULT_RPC_URL="https://sepolia.unichain.org"
    EXPLORER_URL="https://sepolia.uniscan.xyz"
    ;;
  mainnet)
    CHAIN_ID="130"
    DEFAULT_RPC_URL="https://mainnet.unichain.org"
    EXPLORER_URL="https://uniscan.xyz"
    ;;
  *)
    echo "Unsupported UNICHAIN_NETWORK='$UNICHAIN_NETWORK'. Use 'sepolia' or 'mainnet'." >&2
    exit 1
    ;;
esac

RPC_URL="${RPC_URL:-$DEFAULT_RPC_URL}"
DEPLOYER_PK="${DEPLOYER_PK:-}"
MIN_REQUIRED_WEI="${MIN_REQUIRED_WEI:-1000000000000000}" # 0.001 ETH default safety floor

if [[ -z "$DEPLOYER_PK" ]]; then
  echo "DEPLOYER_PK is required." >&2
  exit 1
fi

WORLD_ADAPTER_ID="${WORLD_ADAPTER_ID:-$(cast keccak "WORLD_ID")}"
SELF_ADAPTER_ID="${SELF_ADAPTER_ID:-$(cast keccak "SELF")}" 
POOL_ID="${POOL_ID:-$(cast keccak "HUMAN_DAO_POOL")}" 

WORLD_REQUIRE_HUMAN="${WORLD_REQUIRE_HUMAN:-true}"
POLICY_MIN_AGE="${POLICY_MIN_AGE:-18}"
POLICY_REQUIRE_CONTRIBUTOR="${POLICY_REQUIRE_CONTRIBUTOR:-true}"
POLICY_REQUIRE_DAO_MEMBER="${POLICY_REQUIRE_DAO_MEMBER:-false}"

POLICY_START_TIME="${POLICY_START_TIME:-0}"
POLICY_END_TIME="${POLICY_END_TIME:-0}"
POLICY_ACTIVE="${POLICY_ACTIVE:-true}"

log() {
  echo "[deploy-unichain] $*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

strip_ansi() {
  sed -E 's/\x1B\[[0-9;]*[mK]//g'
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

require_cmd forge
require_cmd cast

DEPLOYER_ADDR="$(cast wallet address --private-key "$DEPLOYER_PK")"
WORLD_ISSUER="${WORLD_ISSUER:-$DEPLOYER_ADDR}"
SELF_ISSUER="${SELF_ISSUER:-$DEPLOYER_ADDR}"
INITIAL_HOOK_CALLER="${INITIAL_HOOK_CALLER:-$DEPLOYER_ADDR}"

ACTUAL_CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"
if [[ "$ACTUAL_CHAIN_ID" != "$CHAIN_ID" ]]; then
  echo "RPC chain-id mismatch. Expected $CHAIN_ID for '$UNICHAIN_NETWORK' but got $ACTUAL_CHAIN_ID." >&2
  echo "Set the correct RPC_URL or UNICHAIN_NETWORK and retry." >&2
  exit 1
fi

DEPLOYER_BALANCE_WEI="$(cast balance "$DEPLOYER_ADDR" --rpc-url "$RPC_URL")"
DEPLOYER_BALANCE_ETH="$(cast balance "$DEPLOYER_ADDR" --rpc-url "$RPC_URL" --ether)"
if (( DEPLOYER_BALANCE_WEI < MIN_REQUIRED_WEI )); then
  echo "Insufficient deployer balance on Unichain '$UNICHAIN_NETWORK'." >&2
  echo "Address: $DEPLOYER_ADDR" >&2
  echo "Balance: $DEPLOYER_BALANCE_WEI wei (~$DEPLOYER_BALANCE_ETH ETH)" >&2
  echo "Required floor: $MIN_REQUIRED_WEI wei" >&2
  echo "Fund this address with native Unichain ETH and rerun." >&2
  exit 1
fi

log "Network: $UNICHAIN_NETWORK (chainId=$CHAIN_ID)"
log "RPC URL: $RPC_URL"
log "Deployer: $DEPLOYER_ADDR"
log "Deployer balance: ${DEPLOYER_BALANCE_ETH} ETH"
log "World issuer: $WORLD_ISSUER"
log "Self issuer: $SELF_ISSUER"
LATEST_NONCE="$(cast nonce "$DEPLOYER_ADDR" --rpc-url "$RPC_URL" --block latest)"
PENDING_NONCE="$(cast nonce "$DEPLOYER_ADDR" --rpc-url "$RPC_URL" --block pending)"
FORCE_NONCE_START="${FORCE_NONCE_START:-}"
if [[ -n "$FORCE_NONCE_START" ]]; then
  NEXT_NONCE="$FORCE_NONCE_START"
else
  NEXT_NONCE="$LATEST_NONCE"
fi
RPC_GAS_PRICE_WEI="$(cast gas-price --rpc-url "$RPC_URL")"
TX_GAS_PRICE_WEI="${TX_GAS_PRICE_WEI:-$RPC_GAS_PRICE_WEI}"
log "Latest nonce:   $LATEST_NONCE"
log "Pending nonce:  $PENDING_NONCE"
log "Starting nonce: $NEXT_NONCE"
if (( PENDING_NONCE > LATEST_NONCE )); then
  log "Pending transactions detected for deployer (pending > latest)."
fi
log "RPC gas price:  ${RPC_GAS_PRICE_WEI} wei"
log "Tx gas price:   ${TX_GAS_PRICE_WEI} wei"

log "Building contracts"
(cd "$ROOT_DIR" && forge build --offline >/dev/null)

deploy_contract() {
  local contract_id="$1"
  shift

  local output deployed tx_nonce
  tx_nonce="$NEXT_NONCE"
  output=$(cd "$ROOT_DIR" && forge create "$contract_id" \
    --rpc-url "$RPC_URL" \
    --chain "$CHAIN_ID" \
    --gas-price "$TX_GAS_PRICE_WEI" \
    --from "$DEPLOYER_ADDR" \
    --nonce "$tx_nonce" \
    --private-key "$DEPLOYER_PK" \
    --broadcast \
    --constructor-args "$@" 2>&1)

  local forge_deployer
  forge_deployer=$(echo "$output" | strip_ansi | sed -n 's/^Deployer: //p' | tail -n1)
  if [[ -n "$forge_deployer" ]]; then
    if [[ "$(to_lower "$forge_deployer")" != "$(to_lower "$DEPLOYER_ADDR")" ]]; then
      echo "Forge deployer mismatch for $contract_id." >&2
      echo "Expected: $DEPLOYER_ADDR" >&2
      echo "Forge used: $forge_deployer" >&2
      echo "Check DEPLOYER_PK and shell CHAIN env settings." >&2
      echo "$output" >&2
      exit 1
    fi
  fi

  if echo "$output" | grep -qi "insufficient funds"; then
    echo "Deployment failed for $contract_id due to insufficient funds." >&2
    echo "Expected deployer: $DEPLOYER_ADDR" >&2
    echo "Nonce:              $tx_nonce" >&2
    if [[ -n "$forge_deployer" ]]; then
      echo "Forge deployer:    $forge_deployer" >&2
    fi
    echo "Current balance (expected deployer): $(cast balance "$DEPLOYER_ADDR" --rpc-url "$RPC_URL" --ether) ETH" >&2
    echo "$output" >&2
    exit 1
  fi

  deployed=$(echo "$output" | strip_ansi | sed -n 's/^Deployed to: //p' | tail -n1)

  if [[ -z "$deployed" ]]; then
    echo "Failed to parse deployed address for $contract_id" >&2
    echo "$output" >&2
    exit 1
  fi

  NEXT_NONCE="$((NEXT_NONCE + 1))"
  echo "$deployed"
}

send_tx() {
  local to="$1"
  local sig="$2"
  shift 2

  local tx_nonce
  tx_nonce="$NEXT_NONCE"
  cast send "$to" "$sig" "$@" \
    --rpc-url "$RPC_URL" \
    --chain "$CHAIN_ID" \
    --gas-price "$TX_GAS_PRICE_WEI" \
    --from "$DEPLOYER_ADDR" \
    --nonce "$tx_nonce" \
    --private-key "$DEPLOYER_PK" >/dev/null
  NEXT_NONCE="$((NEXT_NONCE + 1))"
}

call_view() {
  local to="$1"
  local sig="$2"
  shift 2

  cast call "$to" "$sig" "$@" --rpc-url "$RPC_URL"
}

log "Deploying SatisfyPolicyEngine"
ENGINE_ADDR=$(deploy_contract "src/SatisfyPolicyEngine.sol:SatisfyPolicyEngine" "$DEPLOYER_ADDR")

log "Deploying WorldIdAdapter"
WORLD_ADAPTER_ADDR=$(deploy_contract "src/adapters/WorldIdAdapter.sol:WorldIdAdapter" "$DEPLOYER_ADDR" "$WORLD_ISSUER")

log "Deploying SelfAdapter"
SELF_ADAPTER_ADDR=$(deploy_contract "src/adapters/SelfAdapter.sol:SelfAdapter" "$DEPLOYER_ADDR" "$SELF_ISSUER")

log "Deploying SatisfyHook"
HOOK_ADDR=$(deploy_contract "src/SatisfyHook.sol:SatisfyHook" "$DEPLOYER_ADDR" "$ENGINE_ADDR" "$INITIAL_HOOK_CALLER")

log "Registering adapters and authorizing hook"
send_tx "$ENGINE_ADDR" "registerAdapter(bytes32,address)" "$WORLD_ADAPTER_ID" "$WORLD_ADAPTER_ADDR"
send_tx "$ENGINE_ADDR" "registerAdapter(bytes32,address)" "$SELF_ADAPTER_ID" "$SELF_ADAPTER_ADDR"
send_tx "$ENGINE_ADDR" "setAuthorizedConsumer(address,bool)" "$HOOK_ADDR" true

WORLD_CONDITION=$(cast abi-encode "f(bool)" "$WORLD_REQUIRE_HUMAN")
SELF_CONDITION=$(cast abi-encode "f((uint8,bool,bool))" "($POLICY_MIN_AGE,$POLICY_REQUIRE_CONTRIBUTOR,$POLICY_REQUIRE_DAO_MEMBER)")
PREDICATES="[(${WORLD_ADAPTER_ID},${WORLD_CONDITION}),(${SELF_ADAPTER_ID},${SELF_CONDITION})]"

log "Creating default policy"
send_tx "$ENGINE_ADDR" "createPolicy(uint8,(bytes32,bytes)[],uint64,uint64,bool)" 0 "$PREDICATES" "$POLICY_START_TIME" "$POLICY_END_TIME" "$POLICY_ACTIVE"

POLICY_ID=$(call_view "$ENGINE_ADDR" "policyCount()(uint256)")

log "Binding policy to pool"
send_tx "$HOOK_ADDR" "setPoolPolicy(bytes32,uint256)" "$POOL_ID" "$POLICY_ID"

CURRENT_EPOCH=$(call_view "$ENGINE_ADDR" "currentEpoch()(uint64)")

mkdir -p "$ROOT_DIR/deployments"
DEPLOYMENT_FILE="$ROOT_DIR/deployments/unichain-${UNICHAIN_NETWORK}.json"

cat > "$DEPLOYMENT_FILE" <<JSON
{
  "network": "$UNICHAIN_NETWORK",
  "chainId": $CHAIN_ID,
  "rpcUrl": "$RPC_URL",
  "explorer": "$EXPLORER_URL",
  "deployer": "$DEPLOYER_ADDR",
  "policyEngine": "$ENGINE_ADDR",
  "worldAdapter": "$WORLD_ADAPTER_ADDR",
  "selfAdapter": "$SELF_ADAPTER_ADDR",
  "hook": "$HOOK_ADDR",
  "worldAdapterId": "$WORLD_ADAPTER_ID",
  "selfAdapterId": "$SELF_ADAPTER_ID",
  "poolId": "$POOL_ID",
  "policyId": "$POLICY_ID",
  "epoch": "$CURRENT_EPOCH"
}
JSON

log "Deployment complete"
log "PolicyEngine: $ENGINE_ADDR"
log "WorldAdapter: $WORLD_ADAPTER_ADDR"
log "SelfAdapter:  $SELF_ADAPTER_ADDR"
log "Hook:         $HOOK_ADDR"
log "PolicyId:     $POLICY_ID"
log "PoolId:       $POOL_ID"
log "Epoch:        $CURRENT_EPOCH"
log "Artifact:     $DEPLOYMENT_FILE"

if [[ "$UNICHAIN_NETWORK" == "sepolia" ]]; then
  cat <<ENVVARS

# Frontend .env.local values for Unichain Sepolia
VITE_DEFAULT_NETWORK=unichain-sepolia
VITE_UNICHAIN_SEPOLIA_POLICY_ENGINE_ADDRESS=$ENGINE_ADDR
VITE_UNICHAIN_SEPOLIA_HOOK_ADDRESS=$HOOK_ADDR
VITE_UNICHAIN_SEPOLIA_POLICY_ID=$POLICY_ID
VITE_UNICHAIN_SEPOLIA_POOL_ID=$POOL_ID
VITE_UNICHAIN_SEPOLIA_EPOCH=$CURRENT_EPOCH
VITE_UNICHAIN_SEPOLIA_WORLD_ADAPTER_ID=$WORLD_ADAPTER_ID
VITE_UNICHAIN_SEPOLIA_SELF_ADAPTER_ID=$SELF_ADAPTER_ID
ENVVARS
else
  cat <<ENVVARS

# Frontend .env.local values for Unichain Mainnet
VITE_DEFAULT_NETWORK=unichain-mainnet
VITE_UNICHAIN_MAINNET_POLICY_ENGINE_ADDRESS=$ENGINE_ADDR
VITE_UNICHAIN_MAINNET_HOOK_ADDRESS=$HOOK_ADDR
VITE_UNICHAIN_MAINNET_POLICY_ID=$POLICY_ID
VITE_UNICHAIN_MAINNET_POOL_ID=$POOL_ID
VITE_UNICHAIN_MAINNET_EPOCH=$CURRENT_EPOCH
VITE_UNICHAIN_MAINNET_WORLD_ADAPTER_ID=$WORLD_ADAPTER_ID
VITE_UNICHAIN_MAINNET_SELF_ADAPTER_ID=$SELF_ADAPTER_ID
ENVVARS
fi
