const env = require('./config/env');
const { connectDb, initModels } = require('./config/db');
const { createApp } = require('./app');
const { ensureSeeded } = require('./services/questions');
const gemini = require('./services/gemini');

async function main() {
  const app = createApp(); // loads every model before we build indexes
  await connectDb(env.MONGODB_URI);
  await initModels();
  await ensureSeeded();

  const server = app.listen(env.PORT, () => {
    console.log(`Aurora API listening on :${env.PORT} (${env.NODE_ENV})`);
    console.log(gemini.isConfigured() ? `Gemini: ${env.GEMINI_MODEL}` : 'Gemini: not configured, using the built-in question bank');
  });

  const shutdown = () => server.close(() => process.exit(0));
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  console.error('Failed to start:', err.message);
  process.exit(1);
});
