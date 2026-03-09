# Reactive Hosted Worker Pipeline

`script/reactive_event_executor.sh` is the worker process for the reactive pipeline.

It does not call `SatisfyAutomationModule` directly. Instead it:

1. watches selected on-chain events,
2. builds a signed `JobV1`,
3. sends it to `SatisfyReactiveGateway.execute(...)`,
4. gateway verifies worker trust + nonce + digest replay protection,
5. gateway dispatches to automation reactive functions.

## Trigger Sources

- `SelfAttestationRegistry.AttestationRevoked`
  - action: rotate epoch (`ACTION_SET_EPOCH`) when `REVOCATION_ROTATE_EPOCH=true`
- `SelfAttestationRegistry.TrustedSignerUpdated(..., allowed=false)`
  - action: pause enforcement (`ACTION_PAUSE_ALL`) when `SIGNER_DISABLE_PAUSE=true`
- optional timer
  - action: rotate epoch every `EPOCH_ROTATION_SECONDS`

## When To Use This

Use this script as an off-chain fallback daemon.
If you deploy `SatisfyLasnaReactiveProcessor` via `deploy_reactive_pipeline.sh`,
Reactive Network handles event reads/callback dispatch on-chain and this script is optional.

This fallback pipeline requires:

- target-chain RPC (`unichain-sepolia` artifact by default),
- a trusted worker signer on `SatisfyReactiveGateway`,
- a relayer key to submit `execute(...)` transactions.

## Run

```bash
source .env.unichain
export REACTIVE_WORKER_PK=0x...
export REACTIVE_RELAYER_PK=0x...
./script/reactive_event_executor.sh deployments/unichain-sepolia.json
```

Or via make:

```bash
REACTIVE_WORKER_PK=0x... REACTIVE_RELAYER_PK=0x... make reactive-worker
```

## Useful Env Vars

- `RPC_URL` (defaults from deployment artifact)
- `REACTIVE_WORKER_PK` (signs jobs; required unless `EXECUTOR_DRY_RUN=true`)
- `REACTIVE_RELAYER_PK` or `RELAYER_PK` (submits transactions; defaults to worker key)
- `JOB_VALIDITY_SECONDS` (default `3600`)
- `POLL_INTERVAL_SECONDS` (default `15`)
- `EPOCH_ROTATION_SECONDS` (default `0`, disabled)
- `REVOCATION_ROTATE_EPOCH` (default `true`)
- `SIGNER_DISABLE_PAUSE` (default `true`)
- `STATE_FILE` (default `.reactive_worker_state.json`)
- `START_BLOCK` (default `latest` on first run)
- `RUN_ONCE=true` (single scan pass)
- `EXECUTOR_DRY_RUN=true` (log actions only, no signatures/tx)

## Notes

- Worker checks that its signer is trusted by the gateway before submitting jobs.
- Gateway enforces per-worker monotonic nonces and consumed digest protection.
- Automation module also enforces `jobId` replay protection (`executedJob`) at action level.
- Cursor state is persisted to avoid reprocessing old logs after restart.
