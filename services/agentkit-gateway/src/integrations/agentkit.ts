import type {Hex} from 'viem';

import type {GatewayEnv} from '../config.js';
import type {VerifiedHumanResult} from '../types.js';

function toHexAddress(value: string): Hex {
  const normalized = value.toLowerCase();
  if (!/^0x[0-9a-f]{40}$/.test(normalized)) {
    throw new Error('Invalid agent address returned by AgentKit');
  }
  return normalized as Hex;
}

function extractHumanId(payload: Record<string, unknown>): string | null {
  const candidates = [
    payload.humanId,
    payload.human_id,
    (payload.human as Record<string, unknown> | undefined)?.id,
    (payload.user as Record<string, unknown> | undefined)?.humanId,
  ];

  for (const value of candidates) {
    if (typeof value === 'string' && value.length > 0) {
      return value;
    }
  }
  return null;
}

export async function verifyAgentHuman(
  request: Request,
  env: GatewayEnv,
  claimedAgentAddress: Hex,
): Promise<VerifiedHumanResult> {
  if (process.env.AGENTKIT_DEV_BYPASS === '1') {
    const devHuman = request.headers.get('x-dev-human-id');
    if (!devHuman) {
      throw new Error('AGENTKIT_DEV_BYPASS is enabled but x-dev-human-id is missing');
    }
    return {
      humanId: devHuman,
      agentAddress: claimedAgentAddress,
    };
  }

  const agentkit = await import('@worldcoin/agentkit');
  const verifyHuman = (agentkit as {verifyHuman: (...args: unknown[]) => Promise<unknown>}).verifyHuman;

  const verification = (await verifyHuman(request, {
    app_id: env.WORLD_APP_ID,
    action: env.WORLD_ACTION,
    max_age: env.AGENTKIT_MAX_AGE_SECONDS,
    signal: claimedAgentAddress,
    agentbook: {network: env.AGENTBOOK_NETWORK},
  })) as Record<string, unknown>;

  const verified =
    verification.verified === true ||
    verification.success === true ||
    (verification.result as Record<string, unknown> | undefined)?.verified === true;
  if (!verified) {
    throw new Error('AgentKit verification failed');
  }

  const humanId = extractHumanId(verification);
  if (!humanId) {
    throw new Error('AgentKit verification succeeded but human identifier was missing');
  }

  const resolvedAgent =
    (typeof verification.agentAddress === 'string' && verification.agentAddress) ||
    (typeof verification.agent_address === 'string' && verification.agent_address) ||
    claimedAgentAddress;

  return {
    humanId,
    agentAddress: toHexAddress(resolvedAgent),
  };
}
