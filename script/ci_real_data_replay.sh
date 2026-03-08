#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_cmd forge

if [[ -n "${REALDATA_FIXTURE_JSON_B64:-}" ]]; then
  require_cmd jq

  tmp_fixture="$(mktemp)"
  trap 'rm -f "$tmp_fixture"' EXIT

  printf '%s' "$REALDATA_FIXTURE_JSON_B64" | base64 --decode > "$tmp_fixture"

  export REALDATA_USER="$(jq -r '.user' "$tmp_fixture")"
  export REALDATA_WORLD_CONDITION="$(jq -r '.worldCondition' "$tmp_fixture")"
  export REALDATA_WORLD_PROOF_PAYLOAD="$(jq -r '.worldProofPayload' "$tmp_fixture")"
  export REALDATA_SELF_CONDITION="$(jq -r '.selfCondition' "$tmp_fixture")"
  export REALDATA_SELF_ATTESTATION_PAYLOAD="$(jq -r '.selfAttestationPayload' "$tmp_fixture")"
  export REALDATA_SELF_ATTESTATION_SIGNATURE="$(jq -r '.selfAttestationSignature' "$tmp_fixture")"
  export REALDATA_SELF_PROOF_PAYLOAD="$(jq -r '.selfProofPayload' "$tmp_fixture")"
fi

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
    echo "missing required real-data variable: $var_name" >&2
    exit 1
  fi
done

export REALDATA_FIXTURES_ENABLED=true

(cd "$ROOT_DIR" && forge test --offline --match-contract RealDataReplayTest)
