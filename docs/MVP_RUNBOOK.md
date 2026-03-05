# MVP Runbook

This runbook shows a clean local demo path for Satisfy.

## 1. Compile

```bash
forge build --offline
```

## 2. Run Test Suite

```bash
forge test --offline
```

Expected result:

- all suites pass
- includes unit and end-to-end Solidity tests

## 3. Run Local Anvil Scenario

```bash
./script/anvil_e2e.sh
```

Expected checkpoints in output:

- `Verifying satisfies() with valid proofs`
- `Executing beforeSwap with valid proof bundle`
- `Checking replay protection (expected revert)`
- `Rotating epoch and submitting fresh bundle`
- `Checking policy mismatch with underage self proof`
- `Scenario complete`

## 4. Optional External Node Usage

If Anvil is already running:

```bash
RPC_URL=http://127.0.0.1:8545 START_ANVIL=0 ./script/anvil_e2e.sh
```

## 5. Optional Demo User Override

```bash
SATISFY_USER=0x000000000000000000000000000000000000BEEF ./script/anvil_e2e.sh
```

## 6. What to Show During Demo

- policy creation with composable predicates
- credential proof verification through adapters
- hook-gated execution path
- replay prevention with nullifiers
- epoch-based lifecycle control
