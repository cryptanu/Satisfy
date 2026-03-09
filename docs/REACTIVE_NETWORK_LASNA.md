# Reactive Network Lasna Integration

This flow keeps Satisfy core contracts on Unichain and uses Reactive Network Lasna
to monitor source events and execute callbacks into Unichain.

## Why This Exists

The protocol state machine stays on Unichain.
Lasna is only the event/reaction plane that converts observed events into callback execution.
This gives event-driven automation without migrating core contracts off Unichain.

## Components

- Source chain (Unichain): `SelfAttestationRegistry`, `SatisfyReactiveGateway`
- Destination callback (Unichain): `SatisfyReactiveCallbackReceiver`
- Reactive contract (Lasna): `SatisfyLasnaReactiveProcessor`

## What Happens

1. `SatisfyLasnaReactiveProcessor` subscribes to:
   - `AttestationRevoked(bytes32,address)`
   - `TrustedSignerUpdated(address,bool)`
2. On matching logs, it emits Reactive `Callback(...)` events.
3. Unichain callback proxy calls `SatisfyReactiveCallbackReceiver`.
4. Receiver calls `SatisfyReactiveGateway.executeFromReactiveCallback(...)`.
5. Gateway dispatches into automation reactive functions with replay protection.

### Security Boundaries

- Receiver only accepts calls from configured callback sender.
- Receiver checks callback `rvmId` against configured reactive owner.
- Gateway only accepts authorized callback contracts.
- Gateway enforces replay protection on callback digest.
- Automation module enforces replay protection per `jobId`.

## Deploy

Prereq: deploy core contracts first (e.g. `deployments/unichain-sepolia.json` exists).

```bash
source .env.unichain
DEPLOYER_PK=0x... \
LASNA_DEPLOYER_PK=0x... \
./script/deploy_reactive_pipeline.sh deployments/unichain-sepolia.json
```

Defaults:

- Lasna RPC: `https://lasna-rpc.rnk.dev`
- Lasna chainId: `5318007`
- Processor deploy value: `0.01ether`
- Callback gas limit: `500000`

## Optional Overrides

- `LASNA_RPC_URL`
- `LASNA_CHAIN_ID`
- `LASNA_DEPLOYER_PK`
- `LASNA_PROCESSOR_VALUE`
- `REACTIVE_CALLBACK_GAS_LIMIT`
- `REACTIVE_CALLBACK_SENDER`
- `REVOCATION_ROTATE_EPOCH`
- `SIGNER_DISABLE_PAUSE`

## Artifact Update

`deploy_reactive_pipeline.sh` updates the source deployment artifact with:

- `.reactiveNetwork.lasnaProcessor`
- `.reactiveNetwork.destinationCallbackReceiver`
- `.reactiveNetwork.destinationCallbackSender`
- `.reactiveNetwork.reactiveOwner`

## Post-Deploy Validation

Given `deployments/unichain-sepolia.json`:

```bash
jq '.reactiveNetwork' deployments/unichain-sepolia.json
```

Check callback receiver authorization on gateway:

```bash
cast call <REACTIVE_GATEWAY> "authorizedReactiveCallbacks(address)(bool)" <CALLBACK_RECEIVER> --rpc-url https://sepolia.unichain.org
```

Check receiver callback sender:

```bash
cast call <CALLBACK_RECEIVER> "callbackSender()(address)" --rpc-url https://sepolia.unichain.org
```

Check receiver reactive owner:

```bash
cast call <CALLBACK_RECEIVER> "reactiveOwner()(address)" --rpc-url https://sepolia.unichain.org
```

## Notes

- Core protocol stays on Unichain.
- Lasna is used for event-plane automation, not primary protocol deployment.
