const { rateLimit, ipKeyGenerator } = require('express-rate-limit');
const env = require('../config/env');

const base = {
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skip: () => env.NODE_ENV === 'test',
  message: { error: { code: 'rate_limited', message: 'Too many requests. Please slow down.' } },
};

const apiLimiter = rateLimit({ ...base, windowMs: 60_000, limit: 240 });

// Guest, register and login all hit this: brute-forcing passwords gets expensive.
const authLimiter = rateLimit({ ...base, windowMs: 15 * 60_000, limit: 40 });

// Anything that can call Gemini costs money, so cap it per signed-in user.
const aiLimiter = rateLimit({
  ...base,
  windowMs: 60_000,
  limit: 20,
  keyGenerator: (req) => req.userId ?? ipKeyGenerator(req.ip),
});

module.exports = { apiLimiter, authLimiter, aiLimiter };
