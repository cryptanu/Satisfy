import {Hono} from 'hono';

import {getEnv} from './config.js';
import {prisma} from './db.js';
import {PrismaAgentIdentityStore} from './repositories/prismaAgentIdentityStore.js';
import {createAgentLinkRouter} from './routes/agentLink.js';
import {AgentLinkService} from './services/agentLinkService.js';

export function createApp() {
  const env = getEnv();
  const store = new PrismaAgentIdentityStore(prisma);
  const service = new AgentLinkService(env, store);

  const app = new Hono();

  app.get('/healthz', (c) => c.json({ok: true, service: 'agentkit-gateway'}));
  app.route('/v1/agent-link', createAgentLinkRouter(env, service));

  return app;
}
