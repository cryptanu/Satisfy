# Satisfy AgentKit Gateway

Backend service that issues `AgentLinkProofV1` payloads for Satisfy V2.

Core behavior:

- Verifies agent-human linkage with World AgentKit.
- Protects proof issuance route with x402 payment middleware.
- Applies discount mode: `50%` for first `5` proof issues per agent identity.
- Stores only hashed human identifiers (salted hash), never raw human IDs.
- Returns ABI-encoded proof payload + nullifier for on-chain V2 policy checks.

## Endpoints

- `POST /v1/agent-link/proof`
  - Body:
    - `agentAddress` (`0x...`)
    - `policyId` (`uint256`)
    - `epoch` (`uint64`)
    - `policyContext` (`bytes32`, optional)
  - Response includes:
    - `proofPayload` (ABI-encoded `AgentLinkProofV1`)
    - `nullifier`
    - `humanIdHash`
    - `conditionPayload` (ABI-encoded `AgentLinkConditionV1`)
    - discount metadata

- `GET /v1/agent-link/status?agentAddress=0x...`
  - Returns discount usage and hashed identity status.

## Local Setup

```bash
cd services/agentkit-gateway
cp .env.example .env
npm install
npx prisma generate
npx prisma migrate dev --name init
npm run dev
```

## Notes

- Set `AGENTKIT_DEV_BYPASS=1` and send `x-dev-human-id` header for local non-production testing.
- `AGENTBOOK_NETWORK` is pinned to `world` by default.
- x402 network defaults to Base (`base-sepolia` in example env).
