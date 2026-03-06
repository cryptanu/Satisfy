# Unichain Deployment Guide

This project deploys to Unichain using `script/deploy_unichain.sh`.

## Networks

- `sepolia` (chain ID `1301`)
- `mainnet` (chain ID `130`)

## 1. Prepare Environment

```bash
cp script/.env.unichain.example .env.unichain
```

Edit `.env.unichain` and set at least:

- `DEPLOYER_PK`
- `UNICHAIN_NETWORK`

Optional:

- `WORLD_ISSUER`
- `SELF_ISSUER`
- `INITIAL_HOOK_CALLER`
- policy parameters and pool id

## 2. Deploy

```bash
source .env.unichain
./script/deploy_unichain.sh
```

or explicitly:

```bash
source .env.unichain
UNICHAIN_NETWORK=sepolia ./script/deploy_unichain.sh
```

## Troubleshooting

### `insufficient funds for gas * price + value`

Your deployer wallet does not have enough native Unichain ETH for deployment.

Check address + balance:

```bash
cast wallet address --private-key "$DEPLOYER_PK"
cast balance "$(cast wallet address --private-key "$DEPLOYER_PK")" --rpc-url "$RPC_URL" --ether
```

Then fund that same address on the selected Unichain network and rerun.

## 3. Outputs

The script writes:

- `deployments/unichain-sepolia.json` or `deployments/unichain-mainnet.json`

It also prints frontend env assignments you can paste into `frontend/.env.local`.

## 4. Frontend Integration

After deploy:

```bash
cp frontend/.env.example frontend/.env.local
npm --prefix frontend install
npm --prefix frontend run dev
```

In UI, pick matching network mode and run `satisfies()` / `beforeSwap`.
