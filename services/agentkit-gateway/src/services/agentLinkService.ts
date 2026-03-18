import {privateKeyToAccount, type PrivateKeyAccount} from 'viem/accounts';
import type {Hex} from 'viem';

import type {GatewayEnv} from '../config.js';
import type {
  AgentIdentityStore,
  ProofIssueResult,
  ProofRequestInput,
  StatusResult,
} from '../types.js';
import {
  buildAgentLinkStructHash,
  computeNullifier,
  normalizeAddress,
  normalizeHex32,
  encodeProofPayload,
} from '../utils/agentLinkEncoding.js';
import {hashHumanId} from '../utils/humanHash.js';

type IssueProofInput = ProofRequestInput & {
  humanId: string;
};

export class AgentLinkService {
  private readonly signer: PrivateKeyAccount;
  private readonly sourceBridgeId: Hex;

  constructor(
    private readonly env: GatewayEnv,
    private readonly store: AgentIdentityStore,
  ) {
    this.signer = privateKeyToAccount(this.env.AGENT_LINK_SIGNER_PK as Hex);
    this.sourceBridgeId = normalizeHex32(this.env.AGENT_LINK_SOURCE_BRIDGE_ID);
  }

  async issueProof(input: IssueProofInput): Promise<ProofIssueResult> {
    const agentAddress = normalizeAddress(input.agentAddress);
    const policyContext = normalizeHex32(input.policyContext);
    const humanIdHash = hashHumanId(input.humanId, this.env.HUMAN_ID_SALT);

    const identity = await this.store.upsertAgentIdentity(agentAddress, humanIdHash);
    const discounted = identity.discountUsesConsumed < this.env.X402_DISCOUNT_USES;

    const issuedAt = Math.floor(Date.now() / 1000);
    const validUntil = issuedAt + this.env.PROOF_TTL_SECONDS;
    const relayNonce = identity.relayNonce;

    const nullifier = computeNullifier(input.policyId, input.epoch, humanIdHash, policyContext);
    const structHash = buildAgentLinkStructHash({
      user: agentAddress,
      policyId: input.policyId,
      epoch: input.epoch,
      bundleNullifier: nullifier,
      humanIdHash,
      issuedAt,
      validUntil,
      relayNonce,
      policyContext,
      sourceBridgeId: this.sourceBridgeId,
    });

    const signature = await this.signer.signMessage({message: {raw: structHash}});
    const proofPayload = encodeProofPayload({
      humanIdHash,
      issuedAt: BigInt(issuedAt),
      validUntil: BigInt(validUntil),
      relayNonce,
      sourceBridgeId: this.sourceBridgeId,
      signature,
    });

    const nextRelayNonce = relayNonce + 1n;
    await this.store.updateAfterProofIssue({
      agentAddress,
      humanIdHash,
      nextRelayNonce,
      discounted,
    });
    await this.store.recordProofIssue({
      agentAddress,
      humanIdHash,
      policyId: input.policyId,
      epoch: input.epoch,
      nullifier,
      expiresAtUnix: validUntil,
      discounted,
    });

    const discountUsesConsumed = discounted
      ? identity.discountUsesConsumed + 1
      : identity.discountUsesConsumed;

    return {
      proofPayload,
      nullifier,
      humanIdHash,
      issuedAt,
      validUntil,
      relayNonce,
      discounted,
      discountRemaining: Math.max(0, this.env.X402_DISCOUNT_USES - discountUsesConsumed),
    };
  }

  async getStatus(agentAddressInput: Hex): Promise<StatusResult> {
    const agentAddress = normalizeAddress(agentAddressInput);
    const identity = await this.store.getByAgentAddress(agentAddress);
    if (!identity) {
      return {
        agentAddress,
        humanIdHash: null,
        discountUsesConsumed: 0,
        discountUsesRemaining: this.env.X402_DISCOUNT_USES,
      };
    }

    return {
      agentAddress: identity.agentAddress,
      humanIdHash: identity.humanIdHash,
      discountUsesConsumed: identity.discountUsesConsumed,
      discountUsesRemaining: Math.max(0, this.env.X402_DISCOUNT_USES - identity.discountUsesConsumed),
    };
  }
}
