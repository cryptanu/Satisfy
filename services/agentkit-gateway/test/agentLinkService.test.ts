import {describe, expect, it} from 'vitest';
import type {Hex} from 'viem';

import {AgentLinkService} from '../src/services/agentLinkService.js';
import {computeNullifier} from '../src/utils/agentLinkEncoding.js';
import {hashHumanId} from '../src/utils/humanHash.js';
import type {AgentIdentityRecord, AgentIdentityStore} from '../src/types.js';

class InMemoryStore implements AgentIdentityStore {
  private readonly identities = new Map<string, AgentIdentityRecord>();
  public lastProofIssue:
    | {
        humanIdHash: Hex;
      }
    | null = null;

  async getByAgentAddress(agentAddress: Hex): Promise<AgentIdentityRecord | null> {
    return this.identities.get(agentAddress.toLowerCase()) ?? null;
  }

  async upsertAgentIdentity(agentAddress: Hex, humanIdHash: Hex): Promise<AgentIdentityRecord> {
    const key = agentAddress.toLowerCase();
    const current = this.identities.get(key);
    const next: AgentIdentityRecord = current
      ? {...current, humanIdHash}
      : {
          agentAddress: agentAddress.toLowerCase() as Hex,
          humanIdHash,
          relayNonce: 0n,
          discountUsesConsumed: 0,
        };
    this.identities.set(key, next);
    return next;
  }

  async updateAfterProofIssue(args: {
    agentAddress: Hex;
    humanIdHash: Hex;
    nextRelayNonce: bigint;
    discounted: boolean;
  }): Promise<AgentIdentityRecord> {
    const key = args.agentAddress.toLowerCase();
    const current = this.identities.get(key);
    if (!current) throw new Error('missing identity');

    const next: AgentIdentityRecord = {
      ...current,
      humanIdHash: args.humanIdHash,
      relayNonce: args.nextRelayNonce,
      discountUsesConsumed: args.discounted
        ? current.discountUsesConsumed + 1
        : current.discountUsesConsumed,
    };
    this.identities.set(key, next);
    return next;
  }

  async recordProofIssue(args: {
    agentAddress: Hex;
    humanIdHash: Hex;
    policyId: bigint;
    epoch: number;
    nullifier: Hex;
    expiresAtUnix: number;
    discounted: boolean;
  }): Promise<void> {
    this.lastProofIssue = {humanIdHash: args.humanIdHash};
  }
}

const env = {
  PORT: 8787,
  DATABASE_URL: 'file:./db.sqlite',
  WORLD_APP_ID: 'app_staging',
  WORLD_ACTION: 'proof',
  AGENTBOOK_NETWORK: 'world',
  AGENTKIT_MAX_AGE_SECONDS: 300,
  AGENT_LINK_SIGNER_PK: '0x59c6995e998f97a5a0044966f0945382d3f5db5f6e25c7f3ad2ce9f6f8a6f9e1',
  AGENT_LINK_SOURCE_BRIDGE_ID:
    '0x18f4f0be41b5f7444f4a3071a90d6f0b55ec1db36dbb11f4ca09f444f2dd58d2',
  HUMAN_ID_SALT: 'test-salt',
  PROOF_TTL_SECONDS: 300,
  X402_NETWORK: 'base-sepolia',
  X402_PAY_TO: '0x1111111111111111111111111111111111111111',
  X402_PRICE_USDC: 0.05,
  X402_DISCOUNT_PERCENT: 50,
  X402_DISCOUNT_USES: 5,
  DEFAULT_POLICY_CONTEXT: '0x0000000000000000000000000000000000000000000000000000000000000000',
} as const;

describe('AgentLinkService', () => {
  it('computes deterministic nullifier from policyId/epoch/human hash/context', async () => {
    const humanHash = hashHumanId('human-1', env.HUMAN_ID_SALT);
    const policyContext =
      '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' as Hex;

    const n1 = computeNullifier(1n, 7, humanHash, policyContext);
    const n2 = computeNullifier(1n, 7, humanHash, policyContext);
    expect(n1).toEqual(n2);
  });

  it('applies 50% discount for first 5 issues and then falls back', async () => {
    const store = new InMemoryStore();
    const service = new AgentLinkService(env, store);
    const agentAddress = '0x2222222222222222222222222222222222222222' as Hex;
    const policyContext =
      '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' as Hex;

    for (let i = 0; i < 5; i += 1) {
      const issued = await service.issueProof({
        agentAddress,
        policyId: 1n,
        epoch: 1,
        policyContext,
        humanId: 'human-x',
      });
      expect(issued.discounted).toBe(true);
    }

    const sixth = await service.issueProof({
      agentAddress,
      policyId: 1n,
      epoch: 1,
      policyContext,
      humanId: 'human-x',
    });
    expect(sixth.discounted).toBe(false);
    expect(sixth.discountRemaining).toBe(0);
  });

  it('stores only hashed human identifier', async () => {
    const store = new InMemoryStore();
    const service = new AgentLinkService(env, store);
    const agentAddress = '0x3333333333333333333333333333333333333333' as Hex;
    const policyContext =
      '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' as Hex;

    const issued = await service.issueProof({
      agentAddress,
      policyId: 3n,
      epoch: 2,
      policyContext,
      humanId: 'raw-human-identifier',
    });

    expect(issued.humanIdHash).toMatch(/^0x[0-9a-f]{64}$/);
    expect(store.lastProofIssue?.humanIdHash).toEqual(issued.humanIdHash);
  });
});
