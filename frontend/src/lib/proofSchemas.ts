import {decodeAbiParameters, encodeAbiParameters, type Hex} from 'viem';

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

const agentLinkProofSchema = [
  {
    type: 'tuple',
    components: [
      {name: 'humanIdHash', type: 'bytes32'},
      {name: 'issuedAt', type: 'uint64'},
      {name: 'validUntil', type: 'uint64'},
      {name: 'relayNonce', type: 'uint256'},
      {name: 'sourceBridgeId', type: 'bytes32'},
      {name: 'signature', type: 'bytes'},
    ],
  },
] as const;

export type WorldIdProofV1 = {
  root: bigint;
  nullifierHash: bigint;
  proof: readonly [
    bigint,
    bigint,
    bigint,
    bigint,
    bigint,
    bigint,
    bigint,
    bigint,
  ];
  issuedAt: bigint;
  validUntil: bigint;
  signal: Hex;
  externalNullifier: Hex;
};

export type SelfAttestationProofV1 = {
  attestationId: Hex;
  context: Hex;
};

export type AgentLinkProofV1 = {
  humanIdHash: Hex;
  issuedAt: bigint;
  validUntil: bigint;
  relayNonce: bigint;
  sourceBridgeId: Hex;
  signature: Hex;
};

export function decodeWorldIdProofPayload(payload: Hex): WorldIdProofV1 {
  const [decoded] = decodeAbiParameters(worldProofSchema, payload);
  return decoded;
}

export function encodeWorldIdProofPayload(proof: WorldIdProofV1): Hex {
  return encodeAbiParameters(worldProofSchema, [proof]);
}

export function decodeSelfAttestationProofPayload(payload: Hex): SelfAttestationProofV1 {
  const [decoded] = decodeAbiParameters(selfProofSchema, payload);
  return decoded;
}

export function encodeSelfAttestationProofPayload(proof: SelfAttestationProofV1): Hex {
  return encodeAbiParameters(selfProofSchema, [proof]);
}

export function decodeAgentLinkProofPayload(payload: Hex): AgentLinkProofV1 {
  const [decoded] = decodeAbiParameters(agentLinkProofSchema, payload);
  return decoded;
}

export function encodeAgentLinkProofPayload(proof: AgentLinkProofV1): Hex {
  return encodeAbiParameters(agentLinkProofSchema, [proof]);
}

export function validateWorldIdProofPayload(payload: Hex): void {
  const decoded = decodeWorldIdProofPayload(payload);
  if (decoded.validUntil <= decoded.issuedAt) {
    throw new Error('WorldIdProofV1 invalid time range: validUntil must be > issuedAt');
  }
}

export function validateSelfAttestationProofPayload(payload: Hex): void {
  const decoded = decodeSelfAttestationProofPayload(payload);
  if (decoded.attestationId === '0x0000000000000000000000000000000000000000000000000000000000000000') {
    throw new Error('SelfAttestationProofV1 attestationId cannot be zero');
  }
  if (decoded.context === '0x0000000000000000000000000000000000000000000000000000000000000000') {
    throw new Error('SelfAttestationProofV1 context cannot be zero');
  }
}

export function validateAgentLinkProofPayload(payload: Hex): void {
  const decoded = decodeAgentLinkProofPayload(payload);
  if (decoded.humanIdHash === '0x0000000000000000000000000000000000000000000000000000000000000000') {
    throw new Error('AgentLinkProofV1 humanIdHash cannot be zero');
  }
  if (decoded.validUntil <= decoded.issuedAt) {
    throw new Error('AgentLinkProofV1 invalid time range: validUntil must be > issuedAt');
  }
  if (decoded.signature === '0x' || decoded.signature.length < 132) {
    throw new Error('AgentLinkProofV1 signature is invalid');
  }
}
