#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

UNICHAIN_NETWORK="${UNICHAIN_NETWORK:-sepolia}"

case "$UNICHAIN_NETWORK" in
  sepolia)
    NETWORK_LABEL="Unichain Sepolia"
    CHAIN_ID="1301"
    DEFAULT_RPC_URL="https://sepolia.unichain.org"
    EXPLORER_URL="https://sepolia.uniscan.xyz"
    FRONTEND_MODE="unichain-sepolia"
    ;;
  mainnet)
    NETWORK_LABEL="Unichain Mainnet"
    CHAIN_ID="130"
    DEFAULT_RPC_URL="https://mainnet.unichain.org"
    EXPLORER_URL="https://uniscan.xyz"
    FRONTEND_MODE="unichain-mainnet"
    ;;
  *)
    echo "Unsupported UNICHAIN_NETWORK='$UNICHAIN_NETWORK'. Use 'sepolia' or 'mainnet'." >&2
    exit 1
    ;;
esac

RPC_URL="${RPC_URL:-$DEFAULT_RPC_URL}"
DEPLOYER_PK="${DEPLOYER_PK:-}"
MIN_REQUIRED_WEI="${MIN_REQUIRED_WEI:-1000000000000000}" # 0.001 ETH floor

if [[ -z "$DEPLOYER_PK" ]]; then
  echo "DEPLOYER_PK is required." >&2
  exit 1
fi

WORLD_ADAPTER_ID="${WORLD_ADAPTER_ID:-$(cast keccak "WORLD_ID")}" 
SELF_ADAPTER_ID="${SELF_ADAPTER_ID:-$(cast keccak "SELF")}" 
POOL_ID="${POOL_ID:-$(cast keccak "HUMAN_DAO_POOL")}" 

WORLD_GROUP_ID="${WORLD_GROUP_ID:-1}"
WORLD_POLICY_CONTEXT="${WORLD_POLICY_CONTEXT:-$(cast keccak "WORLD_POLICY_CONTEXT_V1")}" 
WORLD_EXTERNAL_NULLIFIER="${WORLD_EXTERNAL_NULLIFIER:-0x0000000000000000000000000000000000000000000000000000000000000000}"
WORLD_MAX_PROOF_AGE="${WORLD_MAX_PROOF_AGE:-86400}"

POLICY_MIN_AGE="${POLICY_MIN_AGE:-18}"
POLICY_REQUIRE_CONTRIBUTOR="${POLICY_REQUIRE_CONTRIBUTOR:-true}"
POLICY_REQUIRE_DAO_MEMBER="${POLICY_REQUIRE_DAO_MEMBER:-false}"
POLICY_MAX_ATTESTATION_AGE="${POLICY_MAX_ATTESTATION_AGE:-86400}"
POLICY_SOURCE_CHAIN_ID="${POLICY_SOURCE_CHAIN_ID:-0}"
POLICY_SOURCE_BRIDGE_ID="${POLICY_SOURCE_BRIDGE_ID:-0x0000000000000000000000000000000000000000000000000000000000000000}"

POLICY_START_TIME="${POLICY_START_TIME:-0}"
POLICY_END_TIME="${POLICY_END_TIME:-0}"
POLICY_ACTIVE="${POLICY_ACTIVE:-true}"

DEPLOY_WORLD_MOCK_VERIFIER="${DEPLOY_WORLD_MOCK_VERIFIER:-false}"
WORLD_VERIFIER_ADDRESS="${WORLD_VERIFIER_ADDRESS:-}"

TIMELOCK_MIN_DELAY="${TIMELOCK_MIN_DELAY:-3600}"

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

SAFE_ADDRESS="${SAFE_ADDRESS:-}"
if [[ -n "$SAFE_ADDRESS" ]]; then
  DEFAULT_GOV_ADDR="$SAFE_ADDRESS"
else
  DEFAULT_GOV_ADDR="$DEPLOYER_ADDR"
fi

INITIAL_HOOK_CALLER="${INITIAL_HOOK_CALLER:-$DEPLOYER_ADDR}"
AUTOMATION_OWNER="${AUTOMATION_OWNER:-$DEFAULT_GOV_ADDR}"
TIMELOCK_ADMIN="${TIMELOCK_ADMIN:-$DEFAULT_GOV_ADDR}"
TIMELOCK_PROPOSER="${TIMELOCK_PROPOSER:-$DEFAULT_GOV_ADDR}"
TIMELOCK_EXECUTOR="${TIMELOCK_EXECUTOR:-$DEFAULT_GOV_ADDR}"
ROLE_ADMIN="${ROLE_ADMIN:-}"
REACTIVE_EXECUTOR="${REACTIVE_EXECUTOR:-$DEPLOYER_ADDR}"
EMERGENCY_ACTOR="${EMERGENCY_ACTOR:-$DEFAULT_GOV_ADDR}"
SELF_TRUSTED_SIGNER="${SELF_TRUSTED_SIGNER:-$DEPLOYER_ADDR}"

ACTUAL_CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"
if [[ "$ACTUAL_CHAIN_ID" != "$CHAIN_ID" ]]; then
  echo "RPC chain-id mismatch. Expected $CHAIN_ID for '$UNICHAIN_NETWORK' but got $ACTUAL_CHAIN_ID." >&2
  echo "Set the correct RPC_URL or UNICHAIN_NETWORK and retry." >&2
  exit 1
fi

DEPLOYER_BALANCE_WEI="$(cast balance "$DEPLOYER_ADDR" --rpc-url "$RPC_URL")"
DEPLOYER_BALANCE_ETH="$(cast balance "$DEPLOYER_ADDR" --rpc-url "$RPC_URL" --ether)"
if (( DEPLOYER_BALANCE_WEI < MIN_REQUIRED_WEI )); then
  echo "Insufficient deployer balance on network '$UNICHAIN_NETWORK'." >&2
  echo "Address: $DEPLOYER_ADDR" >&2
  echo "Balance: $DEPLOYER_BALANCE_WEI wei (~$DEPLOYER_BALANCE_ETH ETH)" >&2
  echo "Required floor: $MIN_REQUIRED_WEI wei" >&2
  echo "Fund this address with native gas token on the selected network and rerun." >&2
  exit 1
fi

log "Network: $UNICHAIN_NETWORK ($NETWORK_LABEL, chainId=$CHAIN_ID)"
log "RPC URL: $RPC_URL"
log "Deployer: $DEPLOYER_ADDR"
log "Deployer balance: ${DEPLOYER_BALANCE_ETH} ETH"
if [[ -n "$SAFE_ADDRESS" ]]; then
  log "Safe address: $SAFE_ADDRESS (used as governance default)"
fi

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

LAST_DEPLOYED_ADDR=""

deploy_contract() {
  local contract_id="$1"
  shift

  local output deployed tx_nonce
  tx_nonce="$NEXT_NONCE"
  local cmd=(
    forge create "$contract_id"
    --rpc-url "$RPC_URL"
    --chain "$CHAIN_ID"
    --gas-price "$TX_GAS_PRICE_WEI"
    --from "$DEPLOYER_ADDR"
    --nonce "$tx_nonce"
    --private-key "$DEPLOYER_PK"
    --broadcast
  )
  if (( $# > 0 )); then
    cmd+=(--constructor-args "$@")
  fi
  output=$(cd "$ROOT_DIR" && "${cmd[@]}" 2>&1)

  local forge_deployer
  forge_deployer=$(echo "$output" | strip_ansi | sed -n 's/^Deployer: //p' | tail -n1)
  if [[ -n "$forge_deployer" ]]; then
    if [[ "$(to_lower "$forge_deployer")" != "$(to_lower "$DEPLOYER_ADDR")" ]]; then
      echo "Forge deployer mismatch for $contract_id." >&2
      echo "Expected: $DEPLOYER_ADDR" >&2
      echo "Forge used: $forge_deployer" >&2
      echo "$output" >&2
      exit 1
    fi
  fi

  if echo "$output" | grep -qi "insufficient funds"; then
    echo "Deployment failed for $contract_id due to insufficient funds." >&2
    echo "Expected deployer: $DEPLOYER_ADDR" >&2
    echo "Nonce:              $tx_nonce" >&2
    echo "Current balance (expected deployer): $(cast balance "$DEPLOYER_ADDR" --rpc-url "$RPC_URL" --ether) ETH" >&2
    echo "$output" >&2
    exit 1
  fi

  if echo "$output" | grep -qi "nonce too low"; then
    echo "Deployment failed for $contract_id due to nonce mismatch." >&2
    echo "Expected deployer: $DEPLOYER_ADDR" >&2
    echo "Nonce used:        $tx_nonce" >&2
    echo "Latest nonce now:  $(cast nonce "$DEPLOYER_ADDR" --rpc-url "$RPC_URL" --block latest)" >&2
    echo "Pending nonce now: $(cast nonce "$DEPLOYER_ADDR" --rpc-url "$RPC_URL" --block pending)" >&2
    echo "Try setting FORCE_NONCE_START to latest nonce and retry." >&2
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
  LAST_DEPLOYED_ADDR="$deployed"
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

assert_owner() {
  local target="$1"
  local expected="$2"
  local label="$3"

  local actual
  actual=$(call_view "$target" "owner()(address)")
  if [[ "$(to_lower "$actual")" != "$(to_lower "$expected")" ]]; then
    echo "Owner mismatch for $label." >&2
    echo "Expected owner: $expected" >&2
    echo "Actual owner:   $actual" >&2
    exit 1
  fi
}

log "Deploying SatisfyPolicyEngine"
deploy_contract "src/SatisfyPolicyEngine.sol:SatisfyPolicyEngine" "$DEPLOYER_ADDR"
ENGINE_ADDR="$LAST_DEPLOYED_ADDR"

if [[ -n "$WORLD_VERIFIER_ADDRESS" ]]; then
  WORLD_VERIFIER_ADDR="$WORLD_VERIFIER_ADDRESS"
  log "Using provided World verifier: $WORLD_VERIFIER_ADDR"
else
  if [[ "$DEPLOY_WORLD_MOCK_VERIFIER" != "true" ]]; then
    echo "WORLD_VERIFIER_ADDRESS is required unless DEPLOY_WORLD_MOCK_VERIFIER=true." >&2
    exit 1
  fi
  log "Deploying MockWorldIdVerifier"
  deploy_contract "src/mocks/MockWorldIdVerifier.sol:MockWorldIdVerifier"
  WORLD_VERIFIER_ADDR="$LAST_DEPLOYED_ADDR"
fi

log "Deploying SelfAttestationRegistry"
deploy_contract "src/SelfAttestationRegistry.sol:SelfAttestationRegistry" "$DEPLOYER_ADDR" "$SELF_TRUSTED_SIGNER"
SELF_REGISTRY_ADDR="$LAST_DEPLOYED_ADDR"

log "Deploying WorldIdAdapter"
deploy_contract "src/adapters/WorldIdAdapter.sol:WorldIdAdapter" "$DEPLOYER_ADDR" "$WORLD_VERIFIER_ADDR" "$WORLD_GROUP_ID"
WORLD_ADAPTER_ADDR="$LAST_DEPLOYED_ADDR"

log "Deploying SelfAdapter"
deploy_contract "src/adapters/SelfAdapter.sol:SelfAdapter" "$DEPLOYER_ADDR" "$SELF_REGISTRY_ADDR"
SELF_ADAPTER_ADDR="$LAST_DEPLOYED_ADDR"

log "Deploying SatisfyHook"
deploy_contract "src/SatisfyHook.sol:SatisfyHook" "$DEPLOYER_ADDR" "$ENGINE_ADDR" "$INITIAL_HOOK_CALLER"
HOOK_ADDR="$LAST_DEPLOYED_ADDR"

log "Deploying SatisfyTimelock"
deploy_contract "src/SatisfyTimelock.sol:SatisfyTimelock" "$TIMELOCK_ADMIN" "$TIMELOCK_MIN_DELAY" "$TIMELOCK_PROPOSER" "$TIMELOCK_EXECUTOR"
TIMELOCK_ADDR="$LAST_DEPLOYED_ADDR"

if [[ -z "$ROLE_ADMIN" ]]; then
  ROLE_ADMIN="$TIMELOCK_ADDR"
fi

POLICY_MANAGER="${POLICY_MANAGER:-$TIMELOCK_ADDR}"
ADAPTER_MANAGER="${ADAPTER_MANAGER:-$TIMELOCK_ADDR}"
HOOK_MANAGER="${HOOK_MANAGER:-$TIMELOCK_ADDR}"

log "Deploying SatisfyAutomationModule"
deploy_contract \
  "src/SatisfyAutomationModule.sol:SatisfyAutomationModule" \
  "$AUTOMATION_OWNER" \
  "$ROLE_ADMIN" \
  "$POLICY_MANAGER" \
  "$ADAPTER_MANAGER" \
  "$HOOK_MANAGER" \
  "$REACTIVE_EXECUTOR" \
  "$EMERGENCY_ACTOR" \
  "$ENGINE_ADDR" \
  "$HOOK_ADDR" \
  "$WORLD_ADAPTER_ADDR" \
  "$SELF_ADAPTER_ADDR" \
  "$SELF_REGISTRY_ADDR"
AUTOMATION_MODULE_ADDR="$LAST_DEPLOYED_ADDR"

log "Registering adapters and authorizing hook"
send_tx "$ENGINE_ADDR" "registerAdapter(bytes32,address)" "$WORLD_ADAPTER_ID" "$WORLD_ADAPTER_ADDR"
send_tx "$ENGINE_ADDR" "registerAdapter(bytes32,address)" "$SELF_ADAPTER_ID" "$SELF_ADAPTER_ADDR"
send_tx "$ENGINE_ADDR" "setAuthorizedConsumer(address,bool)" "$HOOK_ADDR" true

WORLD_CONDITION=$(cast abi-encode "f((bool,bytes32,bytes32,uint64))" "(true,$WORLD_EXTERNAL_NULLIFIER,$WORLD_POLICY_CONTEXT,$WORLD_MAX_PROOF_AGE)")
SELF_CONDITION=$(cast abi-encode "f((uint8,bool,bool,uint64,uint64,bytes32))" "($POLICY_MIN_AGE,$POLICY_REQUIRE_CONTRIBUTOR,$POLICY_REQUIRE_DAO_MEMBER,$POLICY_MAX_ATTESTATION_AGE,$POLICY_SOURCE_CHAIN_ID,$POLICY_SOURCE_BRIDGE_ID)")
PREDICATES="[(${WORLD_ADAPTER_ID},${WORLD_CONDITION}),(${SELF_ADAPTER_ID},${SELF_CONDITION})]"

log "Creating default policy"
send_tx "$ENGINE_ADDR" "createPolicy(uint8,(bytes32,bytes)[],uint64,uint64,bool)" 0 "$PREDICATES" "$POLICY_START_TIME" "$POLICY_END_TIME" "$POLICY_ACTIVE"

POLICY_ID=$(call_view "$ENGINE_ADDR" "policyCount()(uint256)")

log "Binding policy to pool"
send_tx "$HOOK_ADDR" "setPoolPolicy(bytes32,uint256)" "$POOL_ID" "$POLICY_ID"

log "Transferring ownership to automation module"
send_tx "$ENGINE_ADDR" "transferOwnership(address)" "$AUTOMATION_MODULE_ADDR"
send_tx "$HOOK_ADDR" "transferOwnership(address)" "$AUTOMATION_MODULE_ADDR"
send_tx "$WORLD_ADAPTER_ADDR" "transferOwnership(address)" "$AUTOMATION_MODULE_ADDR"
send_tx "$SELF_ADAPTER_ADDR" "transferOwnership(address)" "$AUTOMATION_MODULE_ADDR"
send_tx "$SELF_REGISTRY_ADDR" "transferOwnership(address)" "$AUTOMATION_MODULE_ADDR"

assert_owner "$ENGINE_ADDR" "$AUTOMATION_MODULE_ADDR" "SatisfyPolicyEngine"
assert_owner "$HOOK_ADDR" "$AUTOMATION_MODULE_ADDR" "SatisfyHook"
assert_owner "$WORLD_ADAPTER_ADDR" "$AUTOMATION_MODULE_ADDR" "WorldIdAdapter"
assert_owner "$SELF_ADAPTER_ADDR" "$AUTOMATION_MODULE_ADDR" "SelfAdapter"
assert_owner "$SELF_REGISTRY_ADDR" "$AUTOMATION_MODULE_ADDR" "SelfAttestationRegistry"

CURRENT_EPOCH=$(call_view "$ENGINE_ADDR" "currentEpoch()(uint64)")

if [[ -n "$SAFE_ADDRESS" ]]; then
  SAFE_JSON_VALUE="\"$SAFE_ADDRESS\""
else
  SAFE_JSON_VALUE="null"
fi

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
  "hook": "$HOOK_ADDR",
  "worldAdapter": "$WORLD_ADAPTER_ADDR",
  "selfAdapter": "$SELF_ADAPTER_ADDR",
  "selfRegistry": "$SELF_REGISTRY_ADDR",
  "worldVerifier": "$WORLD_VERIFIER_ADDR",
  "timelock": "$TIMELOCK_ADDR",
  "automationModule": "$AUTOMATION_MODULE_ADDR",
  "worldAdapterId": "$WORLD_ADAPTER_ID",
  "selfAdapterId": "$SELF_ADAPTER_ID",
  "poolId": "$POOL_ID",
  "policyId": "$POLICY_ID",
  "epoch": "$CURRENT_EPOCH",
  "governance": {
    "safe": $SAFE_JSON_VALUE,
    "automationOwner": "$AUTOMATION_OWNER",
    "roleAdmin": "$ROLE_ADMIN",
    "policyManager": "$POLICY_MANAGER",
    "adapterManager": "$ADAPTER_MANAGER",
    "hookManager": "$HOOK_MANAGER",
    "reactiveExecutor": "$REACTIVE_EXECUTOR",
    "emergencyActor": "$EMERGENCY_ACTOR",
    "timelock": {
      "admin": "$TIMELOCK_ADMIN",
      "proposer": "$TIMELOCK_PROPOSER",
      "executor": "$TIMELOCK_EXECUTOR",
      "minDelay": "$TIMELOCK_MIN_DELAY"
    }
  },
  "verifierConfig": {
    "worldGroupId": "$WORLD_GROUP_ID",
    "worldPolicyContext": "$WORLD_POLICY_CONTEXT",
    "worldExternalNullifier": "$WORLD_EXTERNAL_NULLIFIER",
    "worldMaxProofAge": "$WORLD_MAX_PROOF_AGE",
    "selfTrustedSigner": "$SELF_TRUSTED_SIGNER",
    "selfMinAge": "$POLICY_MIN_AGE",
    "selfRequireContributor": "$POLICY_REQUIRE_CONTRIBUTOR",
    "selfRequireDaoMember": "$POLICY_REQUIRE_DAO_MEMBER",
    "selfMaxAttestationAge": "$POLICY_MAX_ATTESTATION_AGE",
    "selfRequiredSourceChainId": "$POLICY_SOURCE_CHAIN_ID",
    "selfRequiredSourceBridgeId": "$POLICY_SOURCE_BRIDGE_ID"
  }
}
JSON

log "Deployment complete"
log "PolicyEngine:      $ENGINE_ADDR"
log "Hook:              $HOOK_ADDR"
log "WorldAdapter:      $WORLD_ADAPTER_ADDR"
log "SelfAdapter:       $SELF_ADAPTER_ADDR"
log "SelfRegistry:      $SELF_REGISTRY_ADDR"
log "WorldVerifier:     $WORLD_VERIFIER_ADDR"
log "Timelock:          $TIMELOCK_ADDR"
log "Automation:        $AUTOMATION_MODULE_ADDR"
log "PolicyId:          $POLICY_ID"
log "PoolId:            $POOL_ID"
log "Epoch:             $CURRENT_EPOCH"
log "Artifact:          $DEPLOYMENT_FILE"

if [[ "$ROLE_ADMIN" != "$TIMELOCK_ADDR" ]]; then
  log "WARNING: roleAdmin is not timelock. Current roleAdmin=$ROLE_ADMIN"
fi

if [[ "$UNICHAIN_NETWORK" == "sepolia" ]]; then
  cat <<ENVVARS

# Frontend .env.local values for Unichain Sepolia
VITE_DEFAULT_NETWORK=$FRONTEND_MODE
VITE_UNICHAIN_SEPOLIA_POLICY_ENGINE_ADDRESS=$ENGINE_ADDR
VITE_UNICHAIN_SEPOLIA_HOOK_ADDRESS=$HOOK_ADDR
VITE_UNICHAIN_SEPOLIA_POLICY_ID=$POLICY_ID
VITE_UNICHAIN_SEPOLIA_POOL_ID=$POOL_ID
VITE_UNICHAIN_SEPOLIA_EPOCH=$CURRENT_EPOCH
VITE_UNICHAIN_SEPOLIA_AUTOMATION_MODULE_ADDRESS=$AUTOMATION_MODULE_ADDR
VITE_UNICHAIN_SEPOLIA_WORLD_ADAPTER_ID=$WORLD_ADAPTER_ID
VITE_UNICHAIN_SEPOLIA_SELF_ADAPTER_ID=$SELF_ADAPTER_ID
VITE_UNICHAIN_SEPOLIA_DEPLOYMENT_ARTIFACT=$DEPLOYMENT_FILE
ENVVARS
else
  cat <<ENVVARS

# Frontend .env.local values for Unichain Mainnet
VITE_DEFAULT_NETWORK=$FRONTEND_MODE
VITE_UNICHAIN_MAINNET_POLICY_ENGINE_ADDRESS=$ENGINE_ADDR
VITE_UNICHAIN_MAINNET_HOOK_ADDRESS=$HOOK_ADDR
VITE_UNICHAIN_MAINNET_POLICY_ID=$POLICY_ID
VITE_UNICHAIN_MAINNET_POOL_ID=$POOL_ID
VITE_UNICHAIN_MAINNET_EPOCH=$CURRENT_EPOCH
VITE_UNICHAIN_MAINNET_AUTOMATION_MODULE_ADDRESS=$AUTOMATION_MODULE_ADDR
VITE_UNICHAIN_MAINNET_WORLD_ADAPTER_ID=$WORLD_ADAPTER_ID
VITE_UNICHAIN_MAINNET_SELF_ADAPTER_ID=$SELF_ADAPTER_ID
VITE_UNICHAIN_MAINNET_DEPLOYMENT_ARTIFACT=$DEPLOYMENT_FILE
ENVVARS
fi
