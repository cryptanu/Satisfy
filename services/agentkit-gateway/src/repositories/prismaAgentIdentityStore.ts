import type {PrismaClient} from '@prisma/client';
import type {Hex} from 'viem';

import type {AgentIdentityRecord, AgentIdentityStore} from '../types.js';

function toRecord(input: {
  agentAddress: string;
  humanIdHash: string;
  relayNonce: bigint;
  discountUsesConsumed: number;
}): AgentIdentityRecord {
  return {
    agentAddress: input.agentAddress.toLowerCase() as Hex,
    humanIdHash: input.humanIdHash.toLowerCase() as Hex,
    relayNonce: input.relayNonce,
    discountUsesConsumed: input.discountUsesConsumed,
  };
}

export class PrismaAgentIdentityStore implements AgentIdentityStore {
  constructor(private readonly prisma: PrismaClient) {}

  async getByAgentAddress(agentAddress: Hex): Promise<AgentIdentityRecord | null> {
    const item = await this.prisma.agentIdentity.findUnique({
      where: {agentAddress: agentAddress.toLowerCase()},
    });
    return item ? toRecord(item) : null;
  }

  async upsertAgentIdentity(agentAddress: Hex, humanIdHash: Hex): Promise<AgentIdentityRecord> {
    const normalizedAgent = agentAddress.toLowerCase();
    const normalizedHumanHash = humanIdHash.toLowerCase();

    const item = await this.prisma.agentIdentity.upsert({
      where: {agentAddress: normalizedAgent},
      update: {humanIdHash: normalizedHumanHash},
      create: {
        agentAddress: normalizedAgent,
        humanIdHash: normalizedHumanHash,
      },
    });

    return toRecord(item);
  }

  async updateAfterProofIssue(args: {
    agentAddress: Hex;
    humanIdHash: Hex;
    nextRelayNonce: bigint;
    discounted: boolean;
  }): Promise<AgentIdentityRecord> {
    const item = await this.prisma.agentIdentity.update({
      where: {agentAddress: args.agentAddress.toLowerCase()},
      data: {
        humanIdHash: args.humanIdHash.toLowerCase(),
        relayNonce: args.nextRelayNonce,
        discountUsesConsumed: args.discounted ? {increment: 1} : undefined,
      },
    });

    return toRecord(item);
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
    await this.prisma.proofIssue.create({
      data: {
        agentAddress: args.agentAddress.toLowerCase(),
        humanIdHash: args.humanIdHash.toLowerCase(),
        policyId: args.policyId.toString(),
        epoch: args.epoch,
        nullifier: args.nullifier.toLowerCase(),
        expiresAt: new Date(args.expiresAtUnix * 1000),
        discounted: args.discounted,
      },
    });
  }
}
