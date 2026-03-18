import {Hono} from 'hono';
import {z} from 'zod';
import {encodeAbiParameters, type Hex} from 'viem';

import type {GatewayEnv} from '../config.js';
import {verifyAgentHuman} from '../integrations/agentkit.js';
import {createProofPaymentMiddleware} from '../integrations/payment.js';
import {AgentLinkService} from '../services/agentLinkService.js';
import {normalizeAddress, normalizeHex32} from '../utils/agentLinkEncoding.js';

const proofInputSchema = z.object({
  agentAddress: z.string().regex(/^0x[0-9a-fA-F]{40}$/),
  policyId: z.union([z.string(), z.number(), z.bigint()]),
  epoch: z.coerce.number().int().nonnegative(),
  policyContext: z.string().regex(/^0x[0-9a-fA-F]{64}$/).optional(),
});

const statusQuerySchema = z.object({
  agentAddress: z.string().regex(/^0x[0-9a-fA-F]{40}$/),
});

function toBigInt(value: string | number | bigint): bigint {
  if (typeof value === 'bigint') return value;
  return BigInt(value);
}

function encodeConditionPayload(env: GatewayEnv, policyContext: Hex): Hex {
  return encodeAbiParameters(
    [
      {
        type: 'tuple',
        components: [
          {name: 'requireLinkedHuman', type: 'bool'},
          {name: 'policyContext', type: 'bytes32'},
          {name: 'maxProofAge', type: 'uint64'},
          {name: 'requiredSourceBridgeId', type: 'bytes32'},
        ],
      },
    ],
    [
      {
        requireLinkedHuman: true,
        policyContext,
        maxProofAge: BigInt(env.AGENTKIT_MAX_AGE_SECONDS),
        requiredSourceBridgeId: normalizeHex32(env.AGENT_LINK_SOURCE_BRIDGE_ID),
      },
    ],
  );
}

export function createAgentLinkRouter(env: GatewayEnv, service: AgentLinkService) {
  const router = new Hono();

  router.use('/proof', createProofPaymentMiddleware(env));

  router.post('/proof', async (c) => {
    const parsed = proofInputSchema.safeParse(await c.req.json());
    if (!parsed.success) {
      return c.json({error: 'Invalid payload', details: parsed.error.issues}, 400);
    }

    try {
      const agentAddress = normalizeAddress(parsed.data.agentAddress);
      const verification = await verifyAgentHuman(c.req.raw, env, agentAddress);
      if (verification.agentAddress.toLowerCase() !== agentAddress.toLowerCase()) {
        return c.json({error: 'Agent address mismatch between request and AgentKit verification'}, 403);
      }

      const policyContext = normalizeHex32(parsed.data.policyContext ?? env.DEFAULT_POLICY_CONTEXT);
      const issued = await service.issueProof({
        agentAddress,
        policyId: toBigInt(parsed.data.policyId),
        epoch: parsed.data.epoch,
        policyContext,
        humanId: verification.humanId,
      });

      return c.json({
        agentAddress,
        policyId: `${toBigInt(parsed.data.policyId)}`,
        epoch: parsed.data.epoch,
        policyContext,
        proofPayload: issued.proofPayload,
        nullifier: issued.nullifier,
        humanIdHash: issued.humanIdHash,
        issuedAt: issued.issuedAt,
        validUntil: issued.validUntil,
        relayNonce: issued.relayNonce.toString(),
        discounted: issued.discounted,
        discountRemaining: issued.discountRemaining,
        conditionPayload: encodeConditionPayload(env, policyContext),
      });
    } catch (error) {
      return c.json(
        {
          error: error instanceof Error ? error.message : 'Proof issuance failed',
        },
        400,
      );
    }
  });

  router.get('/status', async (c) => {
    const parsed = statusQuerySchema.safeParse(c.req.query());
    if (!parsed.success) {
      return c.json({error: 'Invalid query', details: parsed.error.issues}, 400);
    }

    const status = await service.getStatus(parsed.data.agentAddress as Hex);
    return c.json(status);
  });

  return router;
}
