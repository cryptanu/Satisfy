# Satisfy Frontend

Unichain-integrated React frontend for Satisfy.

## What It Does

- Connect wallet
- Switch/add Unichain network in wallet
- Build and edit a `ProofBundle`
- Call `SatisfyPolicyEngine.satisfies(...)` for policy checks
- Call `SatisfyHook.beforeSwap(...)` for hook-gated execution

## Prerequisites

- Node.js 20+
- Deployed Satisfy contracts (preferably via `script/deploy_unichain.sh`)
- Wallet with Unichain Sepolia/Mainnet support

## Setup

```bash
cp .env.example .env.local
npm install
npm run dev
```

## Network Modes

- `unichain-sepolia`
- `unichain-mainnet`
- `custom`

Defaults are controlled by `VITE_DEFAULT_NETWORK` and per-network env keys.

## Environment Variables

Core:

- `VITE_DEFAULT_NETWORK`
- `VITE_UNICHAIN_SEPOLIA_RPC_URL`
- `VITE_UNICHAIN_MAINNET_RPC_URL`

Per-network deployment values:

- `VITE_UNICHAIN_SEPOLIA_POLICY_ENGINE_ADDRESS`
- `VITE_UNICHAIN_SEPOLIA_HOOK_ADDRESS`
- `VITE_UNICHAIN_SEPOLIA_POLICY_ID`
- `VITE_UNICHAIN_SEPOLIA_POOL_ID`
- `VITE_UNICHAIN_SEPOLIA_EPOCH`
- `VITE_UNICHAIN_SEPOLIA_USER_ADDRESS`
- `VITE_UNICHAIN_SEPOLIA_WORLD_ADAPTER_ID`
- `VITE_UNICHAIN_SEPOLIA_SELF_ADAPTER_ID`

- `VITE_UNICHAIN_MAINNET_POLICY_ENGINE_ADDRESS`
- `VITE_UNICHAIN_MAINNET_HOOK_ADDRESS`
- `VITE_UNICHAIN_MAINNET_POLICY_ID`
- `VITE_UNICHAIN_MAINNET_POOL_ID`
- `VITE_UNICHAIN_MAINNET_EPOCH`
- `VITE_UNICHAIN_MAINNET_USER_ADDRESS`
- `VITE_UNICHAIN_MAINNET_WORLD_ADAPTER_ID`
- `VITE_UNICHAIN_MAINNET_SELF_ADAPTER_ID`

Optional proof defaults:

- `VITE_WORLD_PROOF_PAYLOAD`
- `VITE_SELF_PROOF_PAYLOAD`
- `VITE_NULLIFIER`

## Recommended Flow

1. Deploy contracts to Unichain:

```bash
source ../.env.unichain
UNICHAIN_NETWORK=sepolia ../script/deploy_unichain.sh
```

2. Copy emitted frontend env values into `frontend/.env.local`.
3. Start frontend and choose `Unichain Sepolia` mode.
4. Connect wallet and click `Switch Wallet Network`.
5. Run `satisfies()` and then `beforeSwap`.

## Notes

- `beforeSwap` reverts unless connected account is an authorized hook caller.
- Proof payloads must be valid ABI-encoded bytes from your credential pipeline.
