#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOYMENT_FILE="${1:-${DEPLOYMENT_FILE:-}}"

if [[ -z "$DEPLOYMENT_FILE" ]]; then
  echo "Usage: ./script/unichain_smoke.sh deployments/unichain-sepolia.json" >&2
  exit 1
fi
if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
  echo "deployment artifact not found: $DEPLOYMENT_FILE" >&2
  exit 1
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_cmd jq
require_cmd cast

RPC_URL="${RPC_URL:-$(jq -r '.rpcUrl' "$DEPLOYMENT_FILE")}"
ENGINE="$(jq -r '.policyEngine' "$DEPLOYMENT_FILE")"
HOOK="$(jq -r '.hook' "$DEPLOYMENT_FILE")"
WORLD_ADAPTER_ID="$(jq -r '.worldAdapterId' "$DEPLOYMENT_FILE")"
SELF_ADAPTER_ID="$(jq -r '.selfAdapterId' "$DEPLOYMENT_FILE")"
SELF_REGISTRY="$(jq -r '.selfRegistry' "$DEPLOYMENT_FILE")"
AUTOMATION="$(jq -r '.automationModule' "$DEPLOYMENT_FILE")"
TIMELOCK="$(jq -r '.timelock' "$DEPLOYMENT_FILE")"
REACTIVE_GATEWAY="$(jq -r '.reactiveGateway // empty' "$DEPLOYMENT_FILE")"
REACTIVE_WORKER_SIGNER="$(jq -r '.reactiveWorkerSigner // empty' "$DEPLOYMENT_FILE")"
REACTIVE_CALLBACK_RECEIVER="$(jq -r '.reactiveNetwork.destinationCallbackReceiver // empty' "$DEPLOYMENT_FILE")"
POLICY_ID="$(jq -r '.policyId' "$DEPLOYMENT_FILE")"
POOL_ID="$(jq -r '.poolId' "$DEPLOYMENT_FILE")"
EPOCH="$(jq -r '.epoch' "$DEPLOYMENT_FILE")"
ROLE_ADMIN_EXPECTED="$(jq -r '.governance.roleAdmin' "$DEPLOYMENT_FILE")"
REACTIVE_EXECUTOR_EXPECTED="$(jq -r '.governance.reactiveExecutor // empty' "$DEPLOYMENT_FILE")"
REACTIVE_GATEWAY_OWNER_EXPECTED="$(jq -r '.governance.reactiveGatewayOwner // empty' "$DEPLOYMENT_FILE")"
TIMELOCK_PROPOSER="$(jq -r '.governance.timelock.proposer' "$DEPLOYMENT_FILE")"
TIMELOCK_EXECUTOR="$(jq -r '.governance.timelock.executor' "$DEPLOYMENT_FILE")"

SMOKE_USER="${SMOKE_USER:-${SATISFY_USER:-}}"
WORLD_PROOF_PAYLOAD="${WORLD_PROOF_PAYLOAD:-}"
SELF_PROOF_PAYLOAD="${SELF_PROOF_PAYLOAD:-}"
NULLIFIER="${NULLIFIER:-$(cast keccak "smoke-nullifier-$(date +%s)")}" 
EXPECT_SATISFIES="${EXPECT_SATISFIES:-true}"

SELF_ATTESTATION_PAYLOAD="${SELF_ATTESTATION_PAYLOAD:-}"
SELF_ATTESTATION_SIGNATURE="${SELF_ATTESTATION_SIGNATURE:-}"
RELAYER_PK="${RELAYER_PK:-${DEPLOYER_PK:-}}"

log() {
  echo "[unichain-smoke] $*"
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

call_view() {
  local to="$1"
  local sig="$2"
  shift 2
  cast call "$to" "$sig" "$@" --rpc-url "$RPC_URL"
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "$(to_lower "$actual")" != "$(to_lower "$expected")" ]]; then
    echo "$label mismatch" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

log "RPC: $RPC_URL"
log "Artifact: $DEPLOYMENT_FILE"

log "Checking governance ownership and role wiring"
assert_eq "$(call_view "$ENGINE" "owner()(address)")" "$AUTOMATION" "PolicyEngine owner"
assert_eq "$(call_view "$HOOK" "owner()(address)")" "$AUTOMATION" "Hook owner"
assert_eq "$(call_view "$SELF_REGISTRY" "owner()(address)")" "$AUTOMATION" "SelfRegistry owner"
assert_eq "$(call_view "$AUTOMATION" "roleAdmin()(address)")" "$ROLE_ADMIN_EXPECTED" "Automation roleAdmin"

if [[ -n "$REACTIVE_GATEWAY" && "$REACTIVE_GATEWAY" != "null" ]]; then
  reactive_executor_role="$(call_view "$AUTOMATION" "REACTIVE_EXECUTOR_ROLE()(bytes32)")"
  if [[ -z "$REACTIVE_EXECUTOR_EXPECTED" || "$REACTIVE_EXECUTOR_EXPECTED" == "null" ]]; then
    REACTIVE_EXECUTOR_EXPECTED="$REACTIVE_GATEWAY"
  fi
  reactive_executor_ok="$(call_view "$AUTOMATION" "hasRole(bytes32,address)(bool)" "$reactive_executor_role" "$REACTIVE_EXECUTOR_EXPECTED")"
  if [[ "$reactive_executor_ok" != "true" ]]; then
    echo "automation reactive executor is not authorized: $REACTIVE_EXECUTOR_EXPECTED" >&2
    exit 1
  fi

  assert_eq "$(call_view "$REACTIVE_GATEWAY" "automationModule()(address)")" "$AUTOMATION" "ReactiveGateway automationModule"

  if [[ -n "$REACTIVE_GATEWAY_OWNER_EXPECTED" && "$REACTIVE_GATEWAY_OWNER_EXPECTED" != "null" ]]; then
    assert_eq "$(call_view "$REACTIVE_GATEWAY" "owner()(address)")" "$REACTIVE_GATEWAY_OWNER_EXPECTED" "ReactiveGateway owner"
  fi

  if [[ -n "$REACTIVE_WORKER_SIGNER" && "$REACTIVE_WORKER_SIGNER" != "null" ]]; then
    worker_ok="$(call_view "$REACTIVE_GATEWAY" "trustedWorkers(address)(bool)" "$REACTIVE_WORKER_SIGNER")"
    if [[ "$worker_ok" != "true" ]]; then
      echo "reactive worker signer is not trusted: $REACTIVE_WORKER_SIGNER" >&2
      exit 1
    fi
  fi

  if [[ -n "$REACTIVE_CALLBACK_RECEIVER" && "$REACTIVE_CALLBACK_RECEIVER" != "null" ]]; then
    callback_ok="$(call_view "$REACTIVE_GATEWAY" "authorizedReactiveCallbacks(address)(bool)" "$REACTIVE_CALLBACK_RECEIVER")"
    if [[ "$callback_ok" != "true" ]]; then
      echo "reactive callback receiver is not authorized on gateway: $REACTIVE_CALLBACK_RECEIVER" >&2
      exit 1
    fi
  fi
fi

if [[ "$TIMELOCK" != "null" && "$TIMELOCK" != "" ]]; then
  if [[ "$TIMELOCK_PROPOSER" != "null" && "$TIMELOCK_PROPOSER" != "" ]]; then
    proposer_ok="$(call_view "$TIMELOCK" "proposers(address)(bool)" "$TIMELOCK_PROPOSER")"
    if [[ "$proposer_ok" != "true" ]]; then
      echo "timelock proposer is not authorized: $TIMELOCK_PROPOSER" >&2
      exit 1
    fi
  fi

  if [[ "$TIMELOCK_EXECUTOR" != "null" && "$TIMELOCK_EXECUTOR" != "" ]]; then
    executor_ok="$(call_view "$TIMELOCK" "executors(address)(bool)" "$TIMELOCK_EXECUTOR")"
    if [[ "$executor_ok" != "true" ]]; then
      echo "timelock executor is not authorized: $TIMELOCK_EXECUTOR" >&2
      exit 1
    fi
  fi
fi

if [[ -n "$SELF_ATTESTATION_PAYLOAD" || -n "$SELF_ATTESTATION_SIGNATURE" ]]; then
  if [[ -z "$SELF_ATTESTATION_PAYLOAD" || -z "$SELF_ATTESTATION_SIGNATURE" ]]; then
    echo "SELF_ATTESTATION_PAYLOAD and SELF_ATTESTATION_SIGNATURE must both be set." >&2
    exit 1
  fi
  if [[ -z "$RELAYER_PK" ]]; then
    echo "RELAYER_PK (or DEPLOYER_PK) is required when submitting attestation." >&2
    exit 1
  fi

  log "Submitting attestation fixture to SelfAttestationRegistry"
  cast send \
    "$SELF_REGISTRY" \
    "submitAttestation((bytes32,address,uint8,bool,bool,uint64,uint64,bytes32,uint64,bytes32,bytes32,uint32,uint256),bytes)" \
    "$SELF_ATTESTATION_PAYLOAD" \
    "$SELF_ATTESTATION_SIGNATURE" \
    --rpc-url "$RPC_URL" \
    --private-key "$RELAYER_PK" >/dev/null
fi

if [[ -n "$SMOKE_USER" && -n "$WORLD_PROOF_PAYLOAD" && -n "$SELF_PROOF_PAYLOAD" ]]; then
  PROOFS="[(${WORLD_ADAPTER_ID},${WORLD_PROOF_PAYLOAD}),(${SELF_ADAPTER_ID},${SELF_PROOF_PAYLOAD})]"
  BUNDLE="(${PROOFS},${NULLIFIER},${EPOCH})"

  log "Calling satisfies() with fixture bundle"
  SATISFIED=$(call_view "$ENGINE" "satisfies(uint256,address,((bytes32,bytes)[],bytes32,uint64))(bool)" "$POLICY_ID" "$SMOKE_USER" "$BUNDLE")

  if [[ "$EXPECT_SATISFIES" == "true" && "$SATISFIED" != "true" ]]; then
    echo "satisfies() expected true but got: $SATISFIED" >&2
    exit 1
  fi

  if [[ "$EXPECT_SATISFIES" == "false" && "$SATISFIED" != "false" ]]; then
    echo "satisfies() expected false but got: $SATISFIED" >&2
    exit 1
  fi

  log "satisfies() => $SATISFIED"
else
  log "Skipped satisfies() check. Set SMOKE_USER, WORLD_PROOF_PAYLOAD, and SELF_PROOF_PAYLOAD to enable it."
fi

log "Smoke checks passed"
log "PolicyId: $POLICY_ID"
log "PoolId:   $POOL_ID"
log "Epoch:    $EPOCH"
