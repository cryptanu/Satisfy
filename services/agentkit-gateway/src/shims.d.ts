declare module '@worldcoin/agentkit' {
  export function verifyHuman(request: Request, options: Record<string, unknown>): Promise<unknown>;
}

declare module 'x402-hono' {
  export function requirePayment(
    requirements: unknown,
    options?: Record<string, unknown>,
  ): import('hono').MiddlewareHandler;
}
