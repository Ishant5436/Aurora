const path = require('node:path');
// Tests must be hermetic: they never read a developer's real .env file.
if (process.env.NODE_ENV !== 'test') {
  require('dotenv').config({ path: path.join(__dirname, '../../.env'), quiet: true });
}
const { z } = require('zod');

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(1).max(65535).default(4000),
  MONGODB_URI: z
    .string()
    .min(1, 'MONGODB_URI is required (your MongoDB Atlas connection string)'),
  JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
  JWT_EXPIRES_IN: z.string().default('30d'),
  CORS_ORIGIN: z.string().default('*'),
  TRUST_PROXY: z.coerce.number().int().min(0).default(0),

  // Gemini powers question generation and voice grading. Everything degrades
  // gracefully to the built-in question bank when no key is configured.
  GEMINI_API_KEY: z
    .string()
    .optional()
    .transform((v) => v?.trim() || undefined),
  GEMINI_MODEL: z.string().default('gemini-3.5-flash-lite'),
  // Used first for requests that carry audio or a PDF. The default handles both
  // reliably; point this at a stronger model if you want, since a model that is
  // overloaded falls back to GEMINI_MODEL automatically.
  GEMINI_MULTIMODAL_MODEL: z.string().default('gemini-3.5-flash-lite'),
  // Optional last resort tried after every other model has failed.
  GEMINI_FALLBACK_MODEL: z
    .string()
    .optional()
    .transform((v) => v?.trim() || undefined),
  // Pauses between retries of a transient Gemini failure, in milliseconds.
  GEMINI_BACKOFF_MS: z
    .string()
    .default('500,1500')
    .transform((v) =>
      v
        .split(',')
        .map((s) => Number(s.trim()))
        .filter((n) => Number.isFinite(n) && n >= 0),
    ),
  GEMINI_BASE_URL: z.string().default('https://generativelanguage.googleapis.com'),

  // Without Gemini, voice scoring is a duration heuristic that is trivially
  // gameable, so it is off by default in production.
  ALLOW_MOCK_VOICE: z.enum(['true', 'false']).optional(),
});

const parsed = schema.safeParse(process.env);
if (!parsed.success) {
  const lines = parsed.error.issues.map((i) => `  - ${i.path.join('.')}: ${i.message}`);
  console.error(`Invalid environment configuration:\n${lines.join('\n')}\nSee backend/.env.example`);
  process.exit(1);
}

const env = parsed.data;
if (env.NODE_ENV === 'production' && env.JWT_SECRET.startsWith('change-me')) {
  console.error('Refusing to start in production with the placeholder JWT_SECRET from .env.example');
  process.exit(1);
}
env.ALLOW_MOCK_VOICE =
  env.ALLOW_MOCK_VOICE === undefined ? env.NODE_ENV !== 'production' : env.ALLOW_MOCK_VOICE === 'true';

module.exports = env;
