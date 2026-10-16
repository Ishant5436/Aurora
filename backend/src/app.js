const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const mongoose = require('mongoose');
const env = require('./config/env');
const gemini = require('./services/gemini');
const { apiLimiter, authLimiter } = require('./middleware/limits');
const { notFoundHandler, errorHandler } = require('./middleware/errors');

function createApp() {
  const app = express();
  app.set('trust proxy', env.TRUST_PROXY);
  app.disable('x-powered-by');
  app.use(helmet());
  // Native apps ignore CORS; this only matters for Flutter web.
  app.use(cors({ origin: env.CORS_ORIGIN === '*' ? true : env.CORS_ORIGIN.split(',').map((s) => s.trim()) }));
  if (env.NODE_ENV !== 'test') app.use(morgan('tiny'));

  app.get('/health', (_req, res) => {
    res.json({ ok: true, db: mongoose.connection.readyState === 1, ai: gemini.isConfigured() });
  });

  // Each router installs its own body parser so only the upload routes accept big bodies.
  app.use('/api', apiLimiter);
  app.use('/api/auth', authLimiter, require('./routes/auth'));
  app.use('/api/settings', require('./routes/settings'));
  app.use('/api/alarms', require('./routes/alarms'));
  app.use('/api/notes', require('./routes/notes'));
  app.use('/api/challenges', require('./routes/challenges'));

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}

module.exports = { createApp };
