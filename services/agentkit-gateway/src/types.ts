import type {Hex} from 'viem';

export type AgentLinkProofV1 = {
  humanIdHash: Hex;
  issuedAt: bigint;
  validUntil: bigint;
  relayNonce: bigint;
  sourceBridgeId: Hex;
  signature: Hex;
};

export type AgentLinkConditionV1 = {
  requireLinkedHuman: boolean;
  policyContext: Hex;
  maxProofAge: bigint;
  requiredSourceBridgeId: Hex;
};

export type ProofRequestInput = {
  agentAddress: Hex;
  policyId: bigint;
  epoch: number;
  policyContext: Hex;
};

export type ProofIssueResult = {
  proofPayload: Hex;
  nullifier: Hex;
  humanIdHash: Hex;
  issuedAt: number;
  validUntil: number;
  relayNonce: bigint;
  discounted: boolean;
  discountRemaining: number;
};

export type StatusResult = {
  agentAddress: Hex;
  humanIdHash: Hex | null;
  discountUsesConsumed: number;
  discountUsesRemaining: number;
};

export type VerifiedHumanResult = {
  humanId: string;
  agentAddress: Hex;
};

export type AgentIdentityRecord = {
  agentAddress: Hex;
  humanIdHash: Hex;
  relayNonce: bigint;
  discountUsesConsumed: number;
};

export interface AgentIdentityStore {
  getByAgentAddress(agentAddress: Hex): Promise<AgentIdentityRecord | null>;
  upsertAgentIdentity(agentAddress: Hex, humanIdHash: Hex): Promise<AgentIdentityRecord>;
  updateAfterProofIssue(args: {
    agentAddress: Hex;
    humanIdHash: Hex;
    nextRelayNonce: bigint;
    discounted: boolean;
  }): Promise<AgentIdentityRecord>;
  recordProofIssue(args: {
    agentAddress: Hex;
    humanIdHash: Hex;
    policyId: bigint;
    epoch: number;
    nullifier: Hex;
    expiresAtUnix: number;
    discounted: boolean;
  }): Promise<void>;
}
