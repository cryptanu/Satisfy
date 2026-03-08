# Satisfy Frontend

React + Vite frontend for Satisfy policy checks and hook execution.

## Features

- Connect wallet
- Switch/add Unichain networks
- Build `ProofBundle` inputs
- Call `SatisfyPolicyEngine.satisfies(...)`
- Call `SatisfyHook.beforeSwap(...)`
- Validate payload schemas for:
  - `WorldIdProofV1`
  - `SelfAttestationProofV1`
- Optionally auto-load addresses/IDs from deployment artifacts

## Setup

```bash
cp .env.example .env.local
npm install
npm run dev
```

## Deployment Artifact Import

1. Copy deployment artifact into frontend static assets:

```bash
../script/sync_frontend_artifact.sh ../deployments/unichain-sepolia.json
```

2. Set in `.env.local`:

```bash
VITE_UNICHAIN_SEPOLIA_DEPLOYMENT_ARTIFACT=/deployments/unichain-sepolia.json
```

Then selecting `Unichain Sepolia` mode loads addresses/IDs from the artifact.

## Important Env Keys

- `VITE_DEFAULT_NETWORK`
- `VITE_UNICHAIN_SEPOLIA_RPC_URL`
- `VITE_UNICHAIN_MAINNET_RPC_URL`
- `VITE_UNICHAIN_SEPOLIA_DEPLOYMENT_ARTIFACT`
- `VITE_UNICHAIN_MAINNET_DEPLOYMENT_ARTIFACT`

Per-network manual overrides are still supported via policy engine/hook/pool/policy env keys.

## Runtime Notes

- `beforeSwap` requires your connected account to be an authorized hook caller.
- Proof payloads are ABI-encoded bytes; malformed payloads are rejected by frontend schema checks for known adapter IDs.
