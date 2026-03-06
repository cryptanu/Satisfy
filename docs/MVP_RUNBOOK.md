# MVP Runbook

This runbook shows a clean demo path focused on Unichain deployment.

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

## 3. Deploy to Unichain Sepolia

```bash
cp script/.env.unichain.example .env.unichain
source .env.unichain
UNICHAIN_NETWORK=sepolia ./script/deploy_unichain.sh
```

Expected checkpoints in output:

- contract addresses for policy engine, adapters, and hook
- `PolicyId` and `PoolId`
- generated `deployments/unichain-sepolia.json`
- frontend env block for direct copy

## 4. Frontend Wiring

```bash
cp frontend/.env.example frontend/.env.local
npm --prefix frontend install
npm --prefix frontend run dev
```

In the app:

- choose `Unichain Sepolia` mode
- connect wallet
- use deployed contract values
- call `satisfies()` then `beforeSwap`

## 5. Optional Mainnet Deployment

```bash
source .env.unichain
UNICHAIN_NETWORK=mainnet ./script/deploy_unichain.sh
```

## 6. Local-Only Protocol Simulation (Optional)

```bash
./script/anvil_e2e.sh
```

## 7. What to Show During Demo

- policy creation with composable predicates
- credential proof verification through adapters
- hook-gated execution path
- replay prevention with nullifiers
- epoch-based lifecycle control
- Unichain-native deployment and execution flow
