#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEPLOYMENT_FILE="${1:-${DEPLOYMENT_FILE:-}}"

if [[ -z "$DEPLOYMENT_FILE" ]]; then
  echo "Usage: ./script/sync_frontend_artifact.sh deployments/unichain-sepolia.json" >&2
  exit 1
fi

if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
  echo "deployment artifact not found: $DEPLOYMENT_FILE" >&2
  exit 1
fi

DEST_DIR="$ROOT_DIR/frontend/public/deployments"
mkdir -p "$DEST_DIR"

BASENAME="$(basename "$DEPLOYMENT_FILE")"
cp "$DEPLOYMENT_FILE" "$DEST_DIR/$BASENAME"

echo "Copied deployment artifact to frontend/public/deployments/$BASENAME"

if [[ "$BASENAME" == "unichain-sepolia.json" ]]; then
  echo "Set in frontend/.env.local:"
  echo "VITE_UNICHAIN_SEPOLIA_DEPLOYMENT_ARTIFACT=/deployments/$BASENAME"
elif [[ "$BASENAME" == "unichain-mainnet.json" ]]; then
  echo "Set in frontend/.env.local:"
  echo "VITE_UNICHAIN_MAINNET_DEPLOYMENT_ARTIFACT=/deployments/$BASENAME"
fi
