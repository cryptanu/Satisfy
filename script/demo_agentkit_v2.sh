#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOYMENT_FILE="${1:-${DEPLOYMENT_FILE:-$ROOT_DIR/deployments/unichain-sepolia-v2-agentkit.json}}"

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
require_cmd curl

AGENT_GATEWAY_URL="${AGENT_GATEWAY_URL:-http://127.0.0.1:8787}"
SMOKE_USER="${SMOKE_USER:-${SATISFY_USER:-}}"
if [[ -z "$SMOKE_USER" ]]; then
  echo "SMOKE_USER (or SATISFY_USER) is required." >&2
  exit 1
fi

POLICY_ID="$(jq -r '.policyId' "$DEPLOYMENT_FILE")"
EPOCH="$(jq -r '.epoch' "$DEPLOYMENT_FILE")"
POLICY_CONTEXT="${AGENT_POLICY_CONTEXT:-$(jq -r '.verifierConfig.agentPolicyContext // empty' "$DEPLOYMENT_FILE")}"
if [[ -z "$POLICY_CONTEXT" || "$POLICY_CONTEXT" == "null" ]]; then
  POLICY_CONTEXT="0x0000000000000000000000000000000000000000000000000000000000000000"
fi

echo "[demo-v2] Requesting AgentLink proof from gateway"
PROOF_RESPONSE="$(curl -sfS -X POST "$AGENT_GATEWAY_URL/v1/agent-link/proof" \
  -H 'content-type: application/json' \
  -d "{
    \"agentAddress\": \"$SMOKE_USER\",
    \"policyId\": \"$POLICY_ID\",
    \"epoch\": $EPOCH,
    \"policyContext\": \"$POLICY_CONTEXT\"
  }")"

AGENT_PROOF_PAYLOAD="$(printf '%s' "$PROOF_RESPONSE" | jq -r '.proofPayload')"
NULLIFIER="$(printf '%s' "$PROOF_RESPONSE" | jq -r '.nullifier')"

if [[ -z "$AGENT_PROOF_PAYLOAD" || "$AGENT_PROOF_PAYLOAD" == "null" ]]; then
  echo "gateway did not return proofPayload" >&2
  echo "$PROOF_RESPONSE" >&2
  exit 1
fi

echo "[demo-v2] Received proof payload + nullifier"
echo "AGENT_PROOF_PAYLOAD=$AGENT_PROOF_PAYLOAD"
echo "NULLIFIER=$NULLIFIER"

export AGENT_PROOF_PAYLOAD
export NULLIFIER
export SMOKE_USER

echo "[demo-v2] Running on-chain smoke satisfies() check with agent proof"
"$ROOT_DIR/script/unichain_smoke.sh" "$DEPLOYMENT_FILE"
