import {
  encodeAbiParameters,
  getAddress,
  keccak256,
  parseAbiParameters,
  toHex,
  type Address,
  type Hex,
} from 'viem';

import type {AgentLinkProofV1} from '../types.js';

const PROOF_TYPE_STRING =
  'AgentLinkProofV1(address user,uint256 policyId,uint64 epoch,bytes32 bundleNullifier,bytes32 humanIdHash,uint64 issuedAt,uint64 validUntil,uint256 relayNonce,bytes32 policyContext,bytes32 sourceBridgeId)';

export const PROOF_TYPEHASH = keccak256(toHex(PROOF_TYPE_STRING));

const proofTupleSchema = parseAbiParameters(
  '(bytes32 humanIdHash,uint64 issuedAt,uint64 validUntil,uint256 relayNonce,bytes32 sourceBridgeId,bytes signature)',
);

export function normalizeAddress(value: string): Address {
  return getAddress(value);
}

export function normalizeHex32(value: string): Hex {
  const normalized = value.toLowerCase();
  if (!/^0x[0-9a-f]{64}$/.test(normalized)) {
    throw new Error(`Expected bytes32 hex, got ${value}`);
  }
  return normalized as Hex;
}

export function computeNullifier(policyId: bigint, epoch: number, humanIdHash: Hex, policyContext: Hex): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        {name: 'policyId', type: 'uint256'},
        {name: 'epoch', type: 'uint64'},
        {name: 'humanIdHash', type: 'bytes32'},
        {name: 'policyContext', type: 'bytes32'},
      ],
      [policyId, BigInt(epoch), humanIdHash, policyContext],
    ),
  );
}

export function buildAgentLinkStructHash(args: {
  user: Address;
  policyId: bigint;
  epoch: number;
  bundleNullifier: Hex;
  humanIdHash: Hex;
  issuedAt: number;
  validUntil: number;
  relayNonce: bigint;
  policyContext: Hex;
  sourceBridgeId: Hex;
}): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        {name: 'typehash', type: 'bytes32'},
        {name: 'user', type: 'address'},
        {name: 'policyId', type: 'uint256'},
        {name: 'epoch', type: 'uint64'},
        {name: 'bundleNullifier', type: 'bytes32'},
        {name: 'humanIdHash', type: 'bytes32'},
        {name: 'issuedAt', type: 'uint64'},
        {name: 'validUntil', type: 'uint64'},
        {name: 'relayNonce', type: 'uint256'},
        {name: 'policyContext', type: 'bytes32'},
        {name: 'sourceBridgeId', type: 'bytes32'},
      ],
      [
        PROOF_TYPEHASH,
        args.user,
        args.policyId,
        BigInt(args.epoch),
        args.bundleNullifier,
        args.humanIdHash,
        BigInt(args.issuedAt),
        BigInt(args.validUntil),
        args.relayNonce,
        args.policyContext,
        args.sourceBridgeId,
      ],
    ),
  );
}

export function encodeProofPayload(proof: AgentLinkProofV1): Hex {
  return encodeAbiParameters(proofTupleSchema, [proof]);
}
