# Satisfy Runbook (Unichain Sepolia)

This runbook demonstrates the hardened Satisfy flow end-to-end.

## 1. Compile + Test

```bash
forge build --offline
forge test --offline
```

Expected:

- adapter verification matrix tests pass
- governance/timelock role tests pass
- hook/policy pause and replay tests pass

## 2. Local E2E (Anvil)

```bash
./script/anvil_e2e.sh
```

Expected checkpoints:

- contracts deploy
- policy + pool configured
- `satisfies()` returns `true`
- first `beforeSwap` succeeds
- replayed `beforeSwap` fails
- epoch rotation invalidates old bundle
- emergency pause blocks enforcement

## 3. Deploy to Unichain Sepolia

```bash
cp script/.env.unichain.example .env.unichain
source .env.unichain
UNICHAIN_NETWORK=sepolia ./script/deploy_unichain.sh
```

Expected outputs:

- engine, hook, adapters, registry, timelock, automation addresses
- policy/pool binding summary
- ownership transfer to automation module
- deployment artifact at `deployments/unichain-sepolia.json`

## 4. Submit Testnet Self Attestation (Relay Mock)

```bash
RPC_URL=https://sepolia.unichain.org \
RELAYER_PK=0x... \
RELAY_SIGNER_PK=0x... \
SELF_REGISTRY=0x... \
SUBJECT=0x... \
CONTEXT=0x... \
./script/relay_self_attestation_mock.sh
```

Expected output includes:

- `SELF_ATTESTATION_ID`
- `SELF_CONTEXT`
- `VITE_SELF_PROOF_PAYLOAD`

Relay payload now includes bridge reference fields:

- `sourceChainId`
- `sourceBridgeId`
- `sourceTxHash`
- `sourceLogIndex`

## 5. Unichain Smoke Validation

```bash
./script/unichain_smoke.sh deployments/unichain-sepolia.json
```

This verifies:

- ownership handoff to automation module
- timelock proposer/executor wiring
- optional `satisfies()` fixture replay when proof env vars are provided

## 6. Frontend Wiring

```bash
./script/sync_frontend_artifact.sh deployments/unichain-sepolia.json
cp frontend/.env.example frontend/.env.local
```

Set in `frontend/.env.local`:

```bash
VITE_DEFAULT_NETWORK=unichain-sepolia
VITE_UNICHAIN_SEPOLIA_DEPLOYMENT_ARTIFACT=/deployments/unichain-sepolia.json
```

Run frontend:

```bash
npm --prefix frontend install
npm --prefix frontend run dev
```

In app:

- connect wallet
- switch to Unichain Sepolia
- paste proof payloads (world + self)
- run `satisfies()` then `beforeSwap`

## 7. CI Real-Data Replay Lane

Prepare fixture JSON from recorded provider outputs, base64 it, and store as repository secret:

- `REALDATA_FIXTURE_JSON_B64`

Helper to build fixture JSON + base64 from exported env values:

```bash
./script/build_realdata_fixture.sh
```

CI will execute:

```bash
./script/ci_real_data_replay.sh
```

This lane must pass along with standard unit/integration jobs.

Optional deployed-testnet smoke lane can also run in CI when these secrets are configured:

- `UNICHAIN_SMOKE_DEPLOYMENT_B64`
- `UNICHAIN_SMOKE_RPC_URL`
