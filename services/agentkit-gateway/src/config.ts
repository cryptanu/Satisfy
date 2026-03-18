import 'dotenv/config';

import {z} from 'zod';

const envSchema = z.object({
  PORT: z.coerce.number().int().positive().default(8787),
  DATABASE_URL: z.string().min(1).default('file:./agentkit-gateway.db'),
  WORLD_APP_ID: z.string().min(1),
  WORLD_ACTION: z.string().min(1),
  AGENTBOOK_NETWORK: z.enum(['world', 'base']).default('world'),
  AGENTKIT_MAX_AGE_SECONDS: z.coerce.number().int().positive().default(300),
  AGENT_LINK_SIGNER_PK: z.string().regex(/^0x[0-9a-fA-F]{64}$/),
  AGENT_LINK_SOURCE_BRIDGE_ID: z.string().regex(/^0x[0-9a-fA-F]{64}$/),
  HUMAN_ID_SALT: z.string().min(1),
  PROOF_TTL_SECONDS: z.coerce.number().int().positive().default(300),
  X402_NETWORK: z.string().default('base-sepolia'),
  X402_PAY_TO: z.string().regex(/^0x[0-9a-fA-F]{40}$/),
  X402_PRICE_USDC: z.coerce.number().positive().default(0.05),
  X402_DISCOUNT_PERCENT: z.coerce.number().int().min(1).max(100).default(50),
  X402_DISCOUNT_USES: z.coerce.number().int().min(1).default(5),
  DEFAULT_POLICY_CONTEXT: z.string().regex(/^0x[0-9a-fA-F]{64}$/).default(
    '0x0000000000000000000000000000000000000000000000000000000000000000',
  ),
});

export type GatewayEnv = z.infer<typeof envSchema>;

let parsed: GatewayEnv | null = null;

export function getEnv(): GatewayEnv {
  if (parsed) return parsed;
  parsed = envSchema.parse(process.env);
  return parsed;
}
