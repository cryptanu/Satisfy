#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_cmd bash
require_cmd base64

if [[ -z "${UNICHAIN_SMOKE_DEPLOYMENT_B64:-}" ]]; then
  echo "UNICHAIN_SMOKE_DEPLOYMENT_B64 is required" >&2
  exit 1
fi

tmp_artifact="$(mktemp)"
trap 'rm -f "$tmp_artifact"' EXIT

printf '%s' "$UNICHAIN_SMOKE_DEPLOYMENT_B64" | base64 --decode > "$tmp_artifact"

if [[ -n "${UNICHAIN_SMOKE_RPC_URL:-}" ]]; then
  export RPC_URL="$UNICHAIN_SMOKE_RPC_URL"
fi

if [[ -n "${UNICHAIN_SMOKE_USER:-}" ]]; then
  export SMOKE_USER="$UNICHAIN_SMOKE_USER"
fi
if [[ -n "${UNICHAIN_SMOKE_WORLD_PROOF_PAYLOAD:-}" ]]; then
  export WORLD_PROOF_PAYLOAD="$UNICHAIN_SMOKE_WORLD_PROOF_PAYLOAD"
fi
if [[ -n "${UNICHAIN_SMOKE_SELF_PROOF_PAYLOAD:-}" ]]; then
  export SELF_PROOF_PAYLOAD="$UNICHAIN_SMOKE_SELF_PROOF_PAYLOAD"
fi
if [[ -n "${UNICHAIN_SMOKE_SELF_ATTESTATION_PAYLOAD:-}" ]]; then
  export SELF_ATTESTATION_PAYLOAD="$UNICHAIN_SMOKE_SELF_ATTESTATION_PAYLOAD"
fi
if [[ -n "${UNICHAIN_SMOKE_SELF_ATTESTATION_SIGNATURE:-}" ]]; then
  export SELF_ATTESTATION_SIGNATURE="$UNICHAIN_SMOKE_SELF_ATTESTATION_SIGNATURE"
fi
if [[ -n "${UNICHAIN_SMOKE_RELAYER_PK:-}" ]]; then
  export RELAYER_PK="$UNICHAIN_SMOKE_RELAYER_PK"
fi
if [[ -n "${UNICHAIN_SMOKE_EXPECT_SATISFIES:-}" ]]; then
  export EXPECT_SATISFIES="$UNICHAIN_SMOKE_EXPECT_SATISFIES"
fi

"$ROOT_DIR/script/unichain_smoke.sh" "$tmp_artifact"
