import {requirePayment} from 'x402-hono';
import type {MiddlewareHandler} from 'hono';

import type {GatewayEnv} from '../config.js';

export function createProofPaymentMiddleware(env: GatewayEnv): MiddlewareHandler {
  const requirements = [
    {
      network: env.X402_NETWORK,
      maxAmountRequired: `${env.X402_PRICE_USDC}`,
      asset: 'USDC',
      payTo: env.X402_PAY_TO,
    },
  ];

  return requirePayment(requirements, {
    mode: {
      type: 'discount',
      percent: env.X402_DISCOUNT_PERCENT,
      uses: env.X402_DISCOUNT_USES,
    },
    verifyFailureHook: (_result: unknown, c: {json: (body: unknown, status?: number) => Response}) =>
      c.json(
        {
          error: 'Proof issuance requires verified-human eligibility for discount mode.',
        },
        401,
      ),
  }) as MiddlewareHandler;
}
