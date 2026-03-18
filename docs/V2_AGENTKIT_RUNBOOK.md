# Satisfy V2 AgentKit Runbook

This runbook covers the V2 path where policy access is:

- `(World + Self)` OR `AgentLink`

and `AgentLink` proofs are issued by the AgentKit gateway.

## 1. Build + Test

```bash
forge test --offline
npm --prefix frontend run lint
npm --prefix frontend run build
npm --prefix services/agentkit-gateway install
npm --prefix services/agentkit-gateway run test
npm --prefix services/agentkit-gateway run build
```

## 2. Deploy V2 Contracts (Parallel)

```bash
source .env.unichain
UNICHAIN_NETWORK=sepolia ./script/deploy_unichain_v2.sh
```

Expected artifact:

- `deployments/unichain-sepolia-v2-agentkit.json`

Expected new fields in artifact:

- `agentAdapter`
- `agentAdapterId`
- `v2AgentKitEnabled=true`
- `verifierConfig.agentPolicyContext`

## 3. Start AgentKit Gateway

```bash
cd services/agentkit-gateway
cp .env.example .env
npx prisma generate
npx prisma migrate dev --name init
npm run dev
```

Notes:

- Set `AGENTKIT_DEV_BYPASS=1` and `x-dev-human-id` header for local testing.
- Production demos should use real AgentKit verification headers.

## 4. Sync Frontend Artifact

```bash
./script/sync_frontend_artifact.sh deployments/unichain-sepolia-v2-agentkit.json
```

Then set in `frontend/.env.local`:

```bash
VITE_DEFAULT_NETWORK=unichain-sepolia
VITE_UNICHAIN_SEPOLIA_DEPLOYMENT_ARTIFACT=/deployments/unichain-sepolia-v2-agentkit.json
VITE_AGENTKIT_GATEWAY_URL=http://127.0.0.1:8787
```

## 5. Demo Flow (Live)

1. Open frontend and connect the agent wallet.
2. In **Agent Proof Gateway**, set gateway URL, agent adapter ID, and policy context.
3. Click **Fetch AgentLink Proof**.
4. Click **Check satisfies()**.
5. Click **Submit beforeSwap**.

## 6. Scripted Proof + Smoke

```bash
AGENT_GATEWAY_URL=http://127.0.0.1:8787 \
SMOKE_USER=0x... \
./script/demo_agentkit_v2.sh deployments/unichain-sepolia-v2-agentkit.json
```

This requests a proof from gateway and runs `satisfies()` smoke with the returned payload.
