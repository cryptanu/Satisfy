#!/usr/bin/env bash
set -euo pipefail

OUTPUT_PATH="${1:-${OUTPUT_PATH:-/tmp/satisfy-realdata-fixture.json}}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_cmd jq
require_cmd base64

required_vars=(
  REALDATA_USER
  REALDATA_WORLD_CONDITION
  REALDATA_WORLD_PROOF_PAYLOAD
  REALDATA_SELF_CONDITION
  REALDATA_SELF_ATTESTATION_PAYLOAD
  REALDATA_SELF_ATTESTATION_SIGNATURE
  REALDATA_SELF_PROOF_PAYLOAD
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "missing required variable: $var_name" >&2
    exit 1
  fi
done

jq -n \
  --arg user "$REALDATA_USER" \
  --arg worldCondition "$REALDATA_WORLD_CONDITION" \
  --arg worldProofPayload "$REALDATA_WORLD_PROOF_PAYLOAD" \
  --arg selfCondition "$REALDATA_SELF_CONDITION" \
  --arg selfAttestationPayload "$REALDATA_SELF_ATTESTATION_PAYLOAD" \
  --arg selfAttestationSignature "$REALDATA_SELF_ATTESTATION_SIGNATURE" \
  --arg selfProofPayload "$REALDATA_SELF_PROOF_PAYLOAD" \
  '{
    user: $user,
    worldCondition: $worldCondition,
    worldProofPayload: $worldProofPayload,
    selfCondition: $selfCondition,
    selfAttestationPayload: $selfAttestationPayload,
    selfAttestationSignature: $selfAttestationSignature,
    selfProofPayload: $selfProofPayload
  }' > "$OUTPUT_PATH"

FIXTURE_B64=$(base64 < "$OUTPUT_PATH" | tr -d '\n')

echo "Fixture JSON written to: $OUTPUT_PATH"
echo
echo "Set this secret in CI:"
echo "REALDATA_FIXTURE_JSON_B64=$FIXTURE_B64"
