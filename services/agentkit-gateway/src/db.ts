import {PrismaClient} from '@prisma/client';

import {getEnv} from './config.js';

const env = getEnv();

export const prisma = new PrismaClient({
  datasources: {
    db: {
      url: env.DATABASE_URL,
    },
  },
});
