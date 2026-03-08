#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${RPC_URL:-https://sepolia.unichain.org}"
RELAYER_PK="${RELAYER_PK:-${DEPLOYER_PK:-}}"
RELAY_SIGNER_PK="${RELAY_SIGNER_PK:-}"
SELF_REGISTRY="${SELF_REGISTRY:-}"
SUBJECT="${SUBJECT:-}"
AGE="${AGE:-18}"
CONTRIBUTOR="${CONTRIBUTOR:-false}"
DAO_MEMBER="${DAO_MEMBER:-false}"
CONTEXT="${CONTEXT:-}"
ISSUED_AT="${ISSUED_AT:-$(date +%s)}"
EXPIRES_AT="${EXPIRES_AT:-$(( $(date +%s) + 86400 ))}"
ATTESTATION_ID="${ATTESTATION_ID:-}"

log() {
  echo "[relay-self] $*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_cmd cast

if [[ -z "$RELAYER_PK" ]]; then
  echo "RELAYER_PK (or DEPLOYER_PK) is required." >&2
  exit 1
fi
if [[ -z "$RELAY_SIGNER_PK" ]]; then
  echo "RELAY_SIGNER_PK is required." >&2
  exit 1
fi
if [[ -z "$SELF_REGISTRY" ]]; then
  echo "SELF_REGISTRY is required." >&2
  exit 1
fi
if [[ -z "$SUBJECT" ]]; then
  echo "SUBJECT is required." >&2
  exit 1
fi
if [[ -z "$CONTEXT" ]]; then
  echo "CONTEXT is required (bytes32)." >&2
  exit 1
fi

RELAY_SIGNER_ADDR=$(cast wallet address --private-key "$RELAY_SIGNER_PK")
RELAYER_ADDR=$(cast wallet address --private-key "$RELAYER_PK")
NONCE=$(cast call "$SELF_REGISTRY" "nextNonce(address)(uint256)" "$RELAY_SIGNER_ADDR" --rpc-url "$RPC_URL")

if [[ -z "$ATTESTATION_ID" ]]; then
  ATTESTATION_ID=$(cast keccak "$(cast abi-encode --packed "f(address,uint8,bool,bool,uint64,uint64,bytes32,uint256)" "$SUBJECT" "$AGE" "$CONTRIBUTOR" "$DAO_MEMBER" "$ISSUED_AT" "$EXPIRES_AT" "$CONTEXT" "$NONCE")")
fi

PAYLOAD="($ATTESTATION_ID,$SUBJECT,$AGE,$CONTRIBUTOR,$DAO_MEMBER,$ISSUED_AT,$EXPIRES_AT,$CONTEXT,$NONCE)"
DIGEST=$(cast call "$SELF_REGISTRY" "attestationDigest((bytes32,address,uint8,bool,bool,uint64,uint64,bytes32,uint256))(bytes32)" "$PAYLOAD" --rpc-url "$RPC_URL")
SIGNATURE=$(cast wallet sign --private-key "$RELAY_SIGNER_PK" --no-hash "$DIGEST")

log "Submitting attestation"
cast send \
  "$SELF_REGISTRY" \
  "submitAttestation((bytes32,address,uint8,bool,bool,uint64,uint64,bytes32,uint256),bytes)" \
  "$PAYLOAD" \
  "$SIGNATURE" \
  --rpc-url "$RPC_URL" \
  --private-key "$RELAYER_PK" >/dev/null

SELF_PROOF_PAYLOAD=$(cast abi-encode "f((bytes32,bytes32))" "($ATTESTATION_ID,$CONTEXT)")

log "Relay submission complete"
log "Relayer:       $RELAYER_ADDR"
log "Relay signer:  $RELAY_SIGNER_ADDR"
log "AttestationId: $ATTESTATION_ID"
log "Nonce:         $NONCE"

cat <<EOFOUT

# Use these in frontend proof bundle
SELF_ATTESTATION_ID=$ATTESTATION_ID
SELF_CONTEXT=$CONTEXT
VITE_SELF_PROOF_PAYLOAD=$SELF_PROOF_PAYLOAD

# Optional traceability
SELF_PAYLOAD=$PAYLOAD
SELF_SIGNATURE=$SIGNATURE
EOFOUT
