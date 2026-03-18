import {keccak256, toHex, type Hex} from 'viem';

export function hashHumanId(humanId: string, salt: string): Hex {
  const normalized = humanId.trim();
  if (!normalized) {
    throw new Error('Human ID cannot be empty');
  }
  return keccak256(toHex(`${salt}:${normalized}`));
}
