#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEPLOY_V2_AGENTKIT=true \
ARTIFACT_SUFFIX="${ARTIFACT_SUFFIX:--v2-agentkit}" \
"$ROOT_DIR/script/deploy_unichain.sh"
