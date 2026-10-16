const env = require('../config/env');

class GeminiError extends Error {
  constructor(message, { status, detail, cause, retryable = false } = {}) {
    super(message, { cause });
    this.name = 'GeminiError';
    this.status = status;
    this.detail = detail;
    this.retryable = retryable;
  }
}

// Overload and rate-limit responses clear up on their own; auth and request
// errors do not, so retrying those would only add delay.
const RETRYABLE_STATUS = new Set([429, 500, 502, 503, 504]);
const MIN_ATTEMPT_MS = 3000;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const isConfigured = () => Boolean(env.GEMINI_API_KEY);

/** One-line description for logs, including Google's own explanation. */
function describeError(err) {
  if (!(err instanceof GeminiError)) return err?.message ?? String(err);
  const detail = String(err.detail ?? '').replace(/\s+/g, ' ').slice(0, 160);
  return detail ? `${err.message} (${detail})` : err.message;
}

/** The model to try first, then the ones to fall back to, without duplicates. */
function modelChain(primary, ...others) {
  const chain = [...new Set([primary, ...others, env.GEMINI_FALLBACK_MODEL].filter(Boolean))];
  return { model: chain[0], fallbackModels: chain.slice(1) };
}

// Models sometimes wrap JSON in a markdown fence even when asked not to.
function parseJsonLoose(text) {
  const unfenced = text.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '').trim();
  try {
    return JSON.parse(unfenced);
  } catch (cause) {
    throw new GeminiError('Gemini returned text that is not valid JSON', { cause, retryable: true });
  }
}

async function requestOnce({ model, parts, temperature, timeoutMs }) {
  const url = `${env.GEMINI_BASE_URL}/v1beta/models/${encodeURIComponent(model)}:generateContent`;

  let res;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-goog-api-key': env.GEMINI_API_KEY },
      body: JSON.stringify({
        contents: [{ role: 'user', parts }],
        generationConfig: { responseMimeType: 'application/json', temperature },
      }),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (cause) {
    throw new GeminiError('Gemini request failed or timed out', { cause, retryable: true });
  }

  if (!res.ok) {
    const detail = (await res.text().catch(() => '')).slice(0, 300);
    throw new GeminiError(`Gemini responded with HTTP ${res.status}`, {
      status: res.status,
      detail,
      retryable: RETRYABLE_STATUS.has(res.status),
    });
  }

  let data;
  try {
    data = await res.json();
  } catch (cause) {
    throw new GeminiError('Gemini returned an unreadable response', { cause, retryable: true });
  }
  const text = (data?.candidates?.[0]?.content?.parts ?? [])
    .filter((p) => typeof p.text === 'string' && !p.thought)
    .map((p) => p.text)
    .join('')
    .trim();
  if (!text) throw new GeminiError('Gemini returned an empty response', { retryable: true });
  return parseJsonLoose(text);
}

/**
 * Calls the stable generateContent endpoint and returns the parsed JSON reply.
 * `files` are inline attachments ({ mimeType, base64 }) such as audio or a PDF.
 *
 * Resilience: transient failures are retried with backoff, a model that stays
 * unavailable (or is unknown) hands over to the next one in `fallbackModels`,
 * and `timeoutMs` bounds the whole call, retries and fallbacks included.
 */
async function generateJson({
  model,
  fallbackModels = [],
  prompt,
  files = [],
  temperature = 0.4,
  timeoutMs = 30_000,
  backoffMs = env.GEMINI_BACKOFF_MS,
}) {
  if (!isConfigured()) throw new GeminiError('Gemini is not configured');

  // Media first, instruction last: Google recommends this order for single attachments.
  const parts = [
    ...files.map((f) => ({ inline_data: { mime_type: f.mimeType, data: f.base64 } })),
    { text: prompt },
  ];
  const chain = [...new Set([model, ...fallbackModels])];
  const started = Date.now();
  let lastError;

  for (const [index, name] of chain.entries()) {
    for (let attempt = 0; attempt <= backoffMs.length; attempt++) {
      const remaining = timeoutMs - (Date.now() - started);
      if (remaining < MIN_ATTEMPT_MS) throw lastError ?? new GeminiError('Gemini request timed out', { retryable: true });
      try {
        return await requestOnce({ model: name, parts, temperature, timeoutMs: remaining });
      } catch (err) {
        if (!(err instanceof GeminiError)) throw err;
        lastError = err;
        if (err.status === 404) break; // unknown model id: move straight to the next one
        if (!err.retryable) throw err; // bad key or request: another attempt cannot help
        if (attempt < backoffMs.length) await sleep(backoffMs[attempt]);
      }
    }
    if (index < chain.length - 1) {
      console.warn(`[gemini] ${name} unavailable (${describeError(lastError)}); trying ${chain[index + 1]}`);
    }
  }
  throw lastError;
}

module.exports = { GeminiError, isConfigured, generateJson, parseJsonLoose, modelChain, describeError };
