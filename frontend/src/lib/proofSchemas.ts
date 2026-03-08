import {decodeAbiParameters, type Hex} from 'viem';

const worldProofSchema = [
  {
    type: 'tuple',
    components: [
      {name: 'root', type: 'uint256'},
      {name: 'nullifierHash', type: 'uint256'},
      {name: 'proof', type: 'uint256[8]'},
      {name: 'issuedAt', type: 'uint64'},
      {name: 'validUntil', type: 'uint64'},
      {name: 'signal', type: 'bytes32'},
      {name: 'externalNullifier', type: 'bytes32'},
    ],
  },
] as const;

const selfProofSchema = [
  {
    type: 'tuple',
    components: [
      {name: 'attestationId', type: 'bytes32'},
      {name: 'context', type: 'bytes32'},
    ],
  },
] as const;

export function validateWorldIdProofPayload(payload: Hex): void {
  const [decoded] = decodeAbiParameters(worldProofSchema, payload);
  if (decoded.validUntil <= decoded.issuedAt) {
    throw new Error('WorldIdProofV1 invalid time range: validUntil must be > issuedAt');
  }
}

export function validateSelfAttestationProofPayload(payload: Hex): void {
  const [decoded] = decodeAbiParameters(selfProofSchema, payload);
  if (decoded.attestationId === '0x0000000000000000000000000000000000000000000000000000000000000000') {
    throw new Error('SelfAttestationProofV1 attestationId cannot be zero');
  }
  if (decoded.context === '0x0000000000000000000000000000000000000000000000000000000000000000') {
    throw new Error('SelfAttestationProofV1 context cannot be zero');
  }
}
