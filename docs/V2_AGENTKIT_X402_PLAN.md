# Satisfy V2 AgentKit + x402 Implementation Plan

## Summary

Satisfy V2 adds human-linked agent access to policy-gated markets while preserving V1.
The branch for this work is `v2` (forked from `main` at `a33f857`).

Key goals:

- Keep V1 deployment/flows untouched.
- Ship V2 in parallel with dedicated deploy artifacts and frontend mode.
- Support a single policy shape with dual access branches:
  - Branch A: `World + Self`
  - Branch B: `AgentLink`
- Add payment-protected proof issuance using x402 with AgentKit verification.

## Milestones

### M1 On-chain V2

- Add DNF policy support (`OR` of `AND` groups) with backward-compatible V1 create path.
- Add context-aware adapter verification for strict nullifier checks.
- Add `AgentLinkAdapter` with:
  - signed proof verification
  - freshness checks
  - policy context binding
  - strict nullifier binding:
    - `bundle.nullifier == keccak256(policyId, epoch, humanIdHash, policyContext)`
- Add contract tests for DNF behavior and AgentLink replay/expiry/nullifier constraints.

### M2 Backend V2

- Add `services/agentkit-gateway` service:
  - Node + Hono + Prisma + SQLite
  - AgentKit verification with AgentBook lookup pinned to World
  - x402 payment protection (Base-only), discount mode `50%` for first `5` uses
- Endpoints:
  - `POST /v1/agent-link/proof`
  - `GET /v1/agent-link/status`
- Privacy:
  - store only hashed human identifiers (salted), never raw human IDs
- Add backend tests for verification, discount transitions, and persistence constraints.

### M3 Frontend V2

- Add Agent Console flow in existing frontend:
  - fetch agent proof payload from backend
  - build V2 proof bundle
  - run `satisfies()` and `beforeSwap()` from agent wallet
- Preserve existing V1 manual proof console and network presets.

### M4 Deploy + Demo

- Add parallel V2 deployment scripts/artifacts.
- Add V2 smoke/e2e path for Sepolia.
- Add demo runbook with live path and replay fallback.

## Public Interface Additions

- Contract API:
  - `createPolicyV2(...)`
  - group-level getters for V2 policy inspection
- Adapter structures:
  - `AgentLinkProofV1`
  - `AgentLinkConditionV1`
- Backend API:
  - `POST /v1/agent-link/proof`
  - `GET /v1/agent-link/status`

## Test Expectations

- Pass local test suite per milestone before moving to next milestone.
- Add coverage for:
  - DNF evaluation correctness
  - context-aware adapter checks
  - AgentLink signature/expiry/replay/nullifier rules
  - AgentKit verification path
  - x402 discount usage accounting
  - hash-only identity persistence guarantees

## Assumptions

- V2 is parallel and rollback-safe.
- AgentBook lookup network is pinned to World.
- x402 payment acceptance is Base-only.
- Branch naming is exactly `v2`.
