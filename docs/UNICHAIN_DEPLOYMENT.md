# Unichain Deployment Guide

Primary deployment target is Unichain Sepolia (`chainId=1301`).

## Networks

- `sepolia` (`https://sepolia.unichain.org`)
- `mainnet` (`https://mainnet.unichain.org`)

## 1. Prepare Environment

```bash
cp script/.env.unichain.example .env.unichain
```

Set at minimum:

- `DEPLOYER_PK`
- `UNICHAIN_NETWORK`
- `WORLD_VERIFIER_ADDRESS` (or `DEPLOY_WORLD_MOCK_VERIFIER=true` for test-only)
- `SELF_TRUSTED_SIGNER`
- `POLICY_SOURCE_CHAIN_ID` (optional source-chain constraint for Self adapter)
- `POLICY_SOURCE_BRIDGE_ID` (optional source-bridge constraint for Self adapter)

Governance/timelock controls:

- `SAFE_ADDRESS` (optional default for governance actor addresses)
- `TIMELOCK_MIN_DELAY`
- `TIMELOCK_ADMIN`
- `TIMELOCK_PROPOSER`
- `TIMELOCK_EXECUTOR`
- `REACTIVE_WORKER_SIGNER`
- `REACTIVE_GATEWAY_OWNER`
- `EMERGENCY_ACTOR`

Role holders default to deployed timelock if omitted:

- `POLICY_MANAGER`
- `ADAPTER_MANAGER`
- `HOOK_MANAGER`

## 2. Deploy

```bash
source .env.unichain
UNICHAIN_NETWORK=sepolia ./script/deploy_unichain.sh
```

## 3. What Gets Deployed

- `SatisfyPolicyEngine`
- `WorldIdAdapter`
- `SelfAttestationRegistry`
- `SelfAdapter`
- `SatisfyHook`
- `SatisfyTimelock`
- `SatisfyReactiveGateway`
- `SatisfyAutomationModule`

Then the script:

- registers adapters
- authorizes hook as consumer
- creates default policy
- binds pool to policy
- transfers ownership of engine/hook/adapters/registry to automation module

## 4. Deployment Artifact

Generated file:

- `deployments/unichain-sepolia.json`
- `deployments/unichain-mainnet.json`

Includes:

- contract addresses
- role/timelock config
- verifier/registry config
- adapter IDs, pool ID, policy ID, epoch

## 5. Frontend Sync

```bash
./script/sync_frontend_artifact.sh deployments/unichain-sepolia.json
```

Then set:

```bash
VITE_UNICHAIN_SEPOLIA_DEPLOYMENT_ARTIFACT=/deployments/unichain-sepolia.json
```

## 6. Post-Deploy Smoke Checks

Run ownership/role assertions from the deployment artifact:

```bash
./script/unichain_smoke.sh deployments/unichain-sepolia.json
```

To replay fixture data as part of smoke:

- provide `SMOKE_USER`, `WORLD_PROOF_PAYLOAD`, `SELF_PROOF_PAYLOAD`
- optionally submit attestation first with:
  - `SELF_ATTESTATION_PAYLOAD`
  - `SELF_ATTESTATION_SIGNATURE`
  - `RELAYER_PK`

## 7. Reactive Hosted Worker Pipeline

After deployment, run the worker loop to trigger reactive lifecycle updates from on-chain events.
The worker signs jobs and relays them through `SatisfyReactiveGateway`.

```bash
source .env.unichain
export REACTIVE_WORKER_PK=0x...
export REACTIVE_RELAYER_PK=0x...
./script/reactive_event_executor.sh deployments/unichain-sepolia.json
```

Details: [`docs/REACTIVE_EXECUTOR.md`](docs/REACTIVE_EXECUTOR.md)

## 8. Reactive Network Lasna Integration

To use Reactive Network as the event execution plane (without moving core contracts off Unichain):

```bash
source .env.unichain
DEPLOYER_PK=0x... \
LASNA_DEPLOYER_PK=0x... \
./script/deploy_reactive_pipeline.sh deployments/unichain-sepolia.json
```

This deploys:

- `SatisfyReactiveCallbackReceiver` on Unichain
- `SatisfyLasnaReactiveProcessor` on Lasna testnet (`https://lasna-rpc.rnk.dev`)

and wires `SatisfyReactiveGateway.setReactiveCallback(...)`.

Reference: [`docs/REACTIVE_NETWORK_LASNA.md`](docs/REACTIVE_NETWORK_LASNA.md)

## 9. Troubleshooting

### `DEPLOYER_PK is required`

Export your deployer private key before running deploy script.

### `insufficient funds for gas * price + value`

Your deployer address on selected Unichain network lacks native ETH.

Check:

```bash
cast wallet address --private-key "$DEPLOYER_PK"
cast balance "$(cast wallet address --private-key "$DEPLOYER_PK")" --rpc-url "$RPC_URL" --ether
```

Fund that exact address and retry.

### `nonce too low`

Use latest nonce as explicit start:

```bash
FORCE_NONCE_START=$(cast nonce "$DEPLOYER_ADDRESS" --rpc-url "$RPC_URL" --block latest)
UNICHAIN_NETWORK=sepolia FORCE_NONCE_START=$FORCE_NONCE_START ./script/deploy_unichain.sh
```
