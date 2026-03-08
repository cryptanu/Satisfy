# Satisfy

**Minimum disclosure, maximum coordination.**

Satisfy is a credential-aware policy layer for Uniswap v4-style markets.
It gates participation on verifiable proofs, not wallet identity.

## Story

A DAO launches liquidity incentives and gets botted within minutes.
Address-based allowlists fail because wallets are cheap and identities are not.

Satisfy flips the question from:

- Who are you?

to:

- What can you prove?

Proofs are evaluated against policy at execution time in hook-gated flows.
If policy is satisfied, the market action executes. Otherwise it reverts.

## Production-Hardened Components

- `SatisfyPolicyEngine`
  - Adapter/policy registry, predicate logic (`AND`/`OR`), replay protection.
  - Global pause gate for emergency response.
- `SatisfyHook`
  - Pool-to-policy routing and policy enforcement at `beforeSwap` / `beforeAddLiquidity`.
  - Independent pause gate for market enforcement.
- `WorldIdAdapter`
  - On-chain verifier call path (`IWorldIdVerifier`) with strict domain-separated signal checks.
  - Freshness controls via `issuedAt`, `validUntil`, and `maxProofAge`.
- `SelfAttestationRegistry`
  - Domain-separated signer attestations with nonce replay protection.
  - Carries bridge reference metadata (`sourceChainId`, `sourceBridgeId`, `sourceTxHash`, `sourceLogIndex`).
  - Revocation and trusted signer rotation.
- `SelfAdapter`
  - Consumes only on-chain registry attestations.
  - Context binding to `(chainId, adapter, user, policyCondition)`.
- `SatisfyAutomationModule`
  - Role-gated control plane with reactive replay-protected jobs.
  - Roles:
    - `POLICY_MANAGER_ROLE`
    - `ADAPTER_MANAGER_ROLE`
    - `HOOK_MANAGER_ROLE`
    - `REACTIVE_EXECUTOR_ROLE`
    - `EMERGENCY_ROLE`
- `SatisfyTimelock`
  - Safe-compatible proposer/executor timelock.
  - Intended to be role admin for governance hardening.

## Local Quickstart

Prereqs:

- Foundry (`forge`, `cast`, `anvil`)
- `bash`

Build and test:

```bash
forge build --offline
forge test --offline
```

Run local E2E (deploy + policy + proofs + hook execution + replay + epoch + pause):

```bash
./script/anvil_e2e.sh
```

## Unichain Deployment (Primary Target)

```bash
cp script/.env.unichain.example .env.unichain
source .env.unichain
UNICHAIN_NETWORK=sepolia ./script/deploy_unichain.sh
```

Supported networks:

- `sepolia` (`chainId=1301`)
- `mainnet` (`chainId=130`)

Deployment output includes:

- core contract addresses
- governance/timelock role config
- verifier + registry config
- `deployments/unichain-<network>.json`

Safe-first default:

- set `SAFE_ADDRESS` in `.env.unichain` to use Safe as default for automation owner, timelock admin/proposer/executor, and emergency actor.

## Relay Mock (Bridged Attestation Path)

Post a testnet attestation into `SelfAttestationRegistry` using domain-separated signature + nonce protection:

```bash
RPC_URL=https://sepolia.unichain.org \
RELAYER_PK=0x... \
RELAY_SIGNER_PK=0x... \
SELF_REGISTRY=0x... \
SUBJECT=0x... \
CONTEXT=0x... \
./script/relay_self_attestation_mock.sh
```

This outputs a ready-to-use `VITE_SELF_PROOF_PAYLOAD` value for frontend tests.

## Unichain Smoke Validation

After deployment, run governance + optional fixture replay checks:

```bash
./script/unichain_smoke.sh deployments/unichain-sepolia.json
```

Optional fixture replay inputs:

- `SMOKE_USER`
- `WORLD_PROOF_PAYLOAD`
- `SELF_ATTESTATION_PAYLOAD`
- `SELF_ATTESTATION_SIGNATURE`
- `SELF_PROOF_PAYLOAD`

## Frontend

```bash
cp frontend/.env.example frontend/.env.local
npm --prefix frontend install
npm --prefix frontend run dev
```

The UI supports:

- `satisfies()`
- `beforeSwap()`
- proof payload schema validation for `WorldIdProofV1` and `SelfAttestationProofV1`

### Deployment Artifact Import

Copy deployment artifacts into frontend static assets:

```bash
./script/sync_frontend_artifact.sh deployments/unichain-sepolia.json
```

Then set:

```bash
VITE_UNICHAIN_SEPOLIA_DEPLOYMENT_ARTIFACT=/deployments/unichain-sepolia.json
```

## CI and Real-Data Replay

CI runs:

- full Foundry tests
- local anvil E2E script
- frontend lint/build
- real-data replay lane
- optional Unichain smoke lane (when Unichain smoke secrets are configured)

Real-data lane replays recorded provider fixtures from CI secrets:

```bash
./script/ci_real_data_replay.sh
```

Expected secret:

- `REALDATA_FIXTURE_JSON_B64`
- optional:
  - `UNICHAIN_SMOKE_DEPLOYMENT_B64`
  - `UNICHAIN_SMOKE_RPC_URL`
  - `UNICHAIN_SMOKE_USER`
  - `UNICHAIN_SMOKE_WORLD_PROOF_PAYLOAD`
  - `UNICHAIN_SMOKE_SELF_ATTESTATION_PAYLOAD`
  - `UNICHAIN_SMOKE_SELF_ATTESTATION_SIGNATURE`
  - `UNICHAIN_SMOKE_SELF_PROOF_PAYLOAD`
  - `UNICHAIN_SMOKE_RELAYER_PK`

Fixture schema example: [`docs/real_data_fixture.example.json`](docs/real_data_fixture.example.json).  
Encoding reference: [`docs/REAL_DATA_FIXTURE.md`](docs/REAL_DATA_FIXTURE.md).

To build a fixture JSON + base64 value locally:

```bash
./script/build_realdata_fixture.sh
```

## Repository Layout

- `src/` contracts
- `test/` unit + integration + replay tests
- `script/deploy_unichain.sh` Unichain deployment pipeline
- `script/anvil_e2e.sh` local full-path protocol test
- `script/relay_self_attestation_mock.sh` mock bridge relay submission
- `script/ci_real_data_replay.sh` CI replay lane
- `script/ci_unichain_smoke.sh` CI smoke runner for deployed Unichain artifact
- `script/build_realdata_fixture.sh` fixture bundler for CI secret generation
- `script/unichain_smoke.sh` testnet smoke assertions + fixture replay
- `frontend/` React + Vite app
- `docs/` runbooks and deployment docs

## License

MIT
