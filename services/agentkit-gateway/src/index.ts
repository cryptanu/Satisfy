import {serve} from '@hono/node-server';

import {createApp} from './app.js';
import {getEnv} from './config.js';
import {prisma} from './db.js';

const env = getEnv();
const app = createApp();

const server = serve(
  {
    fetch: app.fetch,
    port: env.PORT,
  },
  (info) => {
    // eslint-disable-next-line no-console
    console.log(`[agentkit-gateway] listening on :${info.port}`);
  },
);

async function shutdown() {
  // eslint-disable-next-line no-console
  console.log('[agentkit-gateway] shutting down');
  await prisma.$disconnect();
  server.close();
}

process.on('SIGINT', () => {
  void shutdown();
});
process.on('SIGTERM', () => {
  void shutdown();
});
