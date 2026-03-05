# Satisfy Frontend

Contract-integrated React frontend for the Satisfy protocol.

## What It Does

- Connect wallet
- Build and edit a `ProofBundle`
- Call `SatisfyPolicyEngine.satisfies(...)` for policy checks
- Call `SatisfyHook.beforeSwap(...)` for hook-gated execution

## Prerequisites

- Node.js 20+
- Running chain endpoint (Anvil recommended)
- Deployed Satisfy contracts

## Setup

```bash
cp .env.example .env.local
npm install
npm run dev
```

Open: `http://localhost:3000`

## Environment Variables

- `VITE_RPC_URL`
- `VITE_CHAIN_ID`
- `VITE_POLICY_ENGINE_ADDRESS`
- `VITE_HOOK_ADDRESS`
- `VITE_POLICY_ID`
- `VITE_POOL_ID`
- `VITE_EPOCH`
- `VITE_USER_ADDRESS`

Optional defaults for pre-filling proof fields:

- `VITE_WORLD_ADAPTER_ID`
- `VITE_WORLD_PROOF_PAYLOAD`
- `VITE_SELF_ADAPTER_ID`
- `VITE_SELF_PROOF_PAYLOAD`
- `VITE_NULLIFIER`

## Local Flow with This Repo

1. Run protocol E2E deployment script from repo root:

```bash
./script/anvil_e2e.sh
```

2. Copy deployed addresses into `frontend/.env.local`.
3. Start frontend and connect wallet.
4. Check `satisfies()` then send `beforeSwap`.

## Notes

- `beforeSwap` will revert unless the connected account is an authorized hook caller.
- Proof payloads must be valid ABI-encoded bytes from your credential pipeline.
