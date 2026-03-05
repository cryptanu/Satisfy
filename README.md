# Satisfy

**Minimum disclosure, maximum coordination.**

Satisfy is a credential-aware policy layer for Uniswap v4-style markets.
Instead of allowing participation based on wallet allowlists, Satisfy allows pools to enforce eligibility based on privacy-preserving proofs.

## Story

A DAO launches a token and promises community-first liquidity incentives.
Within minutes, sybil wallets and bots absorb emissions while real contributors get diluted.

That is address-based coordination.

Satisfy upgrades this to proof-based coordination.
Before a swap or liquidity action, the market asks:

**"What can you prove?"**

Not identity. Not private documents. Just cryptographic facts:

- unique human
- eligible contributor
- policy-compliant participant

If the proof bundle satisfies policy, the action executes. If not, it reverts.
This gives DAOs and protocols a way to coordinate fairly without surveillance.

## MVP Components

- `SatisfyPolicyEngine`
  - Adapter registry and policy registry.
  - Policy evaluation via `AND` / `OR` predicates.
  - Replay-protected proof consumption using `epoch + nullifier`.
- `SatisfyHook`
  - Pool-level policy routing (`poolId -> policyId`).
  - Hook gates for `beforeSwap` and `beforeAddLiquidity`.
- `WorldIdAdapter`
  - Signed personhood attestation verifier (MVP placeholder for zk integration).
- `SelfAdapter`
  - Signed selective-disclosure verifier (age / contributor / member claims).

## Quickstart

Prereqs:

- Foundry (`forge`, `cast`, `anvil`)
- `bash`, `curl`

Build:

```bash
forge build --offline
```

Run tests:

```bash
forge test --offline
```

Run local E2E on Anvil:

```bash
./script/anvil_e2e.sh
```

Use existing node:

```bash
RPC_URL=http://127.0.0.1:8545 START_ANVIL=0 ./script/anvil_e2e.sh
```

Override participant address:

```bash
SATISFY_USER=0x000000000000000000000000000000000000BEEF ./script/anvil_e2e.sh
```

Copy configurable defaults:

```bash
cp .env.example .env
```

## Developer UX

Use make targets:

```bash
make build
make test
make e2e
make clean
```

## Repository Layout

- `src/`
  - protocol contracts
- `test/`
  - unit + integration tests
- `script/anvil_e2e.sh`
  - full local deploy-and-execute scenario
- `frontend/`
  - React + Vite UI integrated with `satisfies()` and `beforeSwap()`
- `docs/MVP_RUNBOOK.md`
  - step-by-step demo flow and expected checkpoints
- `docs/PRODUCTION_GAPS.md`
  - explicit MVP-to-mainnet hardening checklist

## What the E2E Script Validates

- valid policy satisfaction with signed proofs
- successful `beforeSwap`
- replay rejection on reused nullifier
- epoch rotation behavior
- underage credential rejection

## Notes

This repository is an MVP intended for hackathon demonstration and integration scaffolding.
For production, replace signed-placeholder adapters with full zk verifier integrations and add governance hardening.

## License

MIT
