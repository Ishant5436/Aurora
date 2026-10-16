const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { configureEnv } = require('./helpers');

configureEnv({ GEMINI_API_KEY: 'test-key', GEMINI_BASE_URL: 'https://gemini.test' });
const gemini = require('../src/services/gemini');

const reply = (text, init = { status: 200 }) =>
  new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text }] } }] }), {
    ...init,
    headers: { 'content-type': 'application/json' },
  });

describe('Gemini API wrapper', () => {
  const realFetch = global.fetch;
  let calls;

  beforeEach(() => {
    calls = [];
  });
  afterEach(() => {
    global.fetch = realFetch;
  });
  const stub = (responder) => {
    global.fetch = async (url, init) => {
      calls.push({ url: String(url), headers: init.headers, body: JSON.parse(init.body) });
      return responder();
    };
  };

  it('sends the key as a header, asks for JSON, and puts media before the prompt', async () => {
    stub(() => reply('{"ok":true}'));
    const out = await gemini.generateJson({
      model: 'some-model',
      prompt: 'Grade this',
      files: [{ mimeType: 'audio/wav', base64: 'AAAA' }],
    });
    assert.deepEqual(out, { ok: true });
    const [call] = calls;
    assert.equal(call.url, 'https://gemini.test/v1beta/models/some-model:generateContent');
    assert.equal(call.headers['x-goog-api-key'], 'test-key');
    assert.ok(!call.url.includes('test-key'), 'the key must never appear in the URL');
    assert.equal(call.body.generationConfig.responseMimeType, 'application/json');
    const parts = call.body.contents[0].parts;
    assert.deepEqual(parts[0], { inline_data: { mime_type: 'audio/wav', data: 'AAAA' } });
    assert.deepEqual(parts[1], { text: 'Grade this' });
  });

  it('tolerates a markdown-fenced JSON reply and skips thought parts', async () => {
    global.fetch = async () =>
      new Response(
        JSON.stringify({
          candidates: [{ content: { parts: [{ text: 'thinking...', thought: true }, { text: '```json\n{"a":1}\n```' }] } }],
        }),
        { status: 200 },
      );
    assert.deepEqual(await gemini.generateJson({ model: 'm', prompt: 'p' }), { a: 1 });
  });

  it('raises GeminiError for HTTP failures, empty replies and invalid JSON', async () => {
    stub(() => new Response('quota exceeded', { status: 429 }));
    await assert.rejects(gemini.generateJson({ model: 'm', prompt: 'p' }), (e) => e.name === 'GeminiError' && e.status === 429);

    global.fetch = async () => new Response(JSON.stringify({ candidates: [] }), { status: 200 });
    await assert.rejects(gemini.generateJson({ model: 'm', prompt: 'p' }), /empty response/);

    stub(() => reply('definitely not json'));
    await assert.rejects(gemini.generateJson({ model: 'm', prompt: 'p' }), /not valid JSON/);
  });

  const modelOf = (call) => call.url.match(/models\/([^:]+):/)[1];

  it('retries a transient 503 and then succeeds', async () => {
    let n = 0;
    stub(() => (++n < 3 ? new Response('busy', { status: 503 }) : reply('{"ok":true}')));
    const out = await gemini.generateJson({ model: 'primary', prompt: 'p', backoffMs: [0, 0] });
    assert.deepEqual(out, { ok: true });
    assert.deepEqual(calls.map(modelOf), ['primary', 'primary', 'primary']);
  });

  it('does not retry or fall back on a request error such as a bad key', async () => {
    stub(() => new Response('API key not valid', { status: 403 }));
    await assert.rejects(
      gemini.generateJson({ model: 'primary', fallbackModels: ['backup'], prompt: 'p', backoffMs: [0, 0] }),
      (e) => e.status === 403,
    );
    assert.equal(calls.length, 1);
  });

  it('falls back to the next model once the first stays overloaded', async () => {
    stub(() => (modelOf(calls.at(-1)) === 'primary' ? new Response('busy', { status: 503 }) : reply('{"from":"backup"}')));
    const out = await gemini.generateJson({
      model: 'primary',
      fallbackModels: ['backup'],
      prompt: 'p',
      backoffMs: [0, 0],
    });
    assert.deepEqual(out, { from: 'backup' });
    assert.deepEqual(calls.map(modelOf), ['primary', 'primary', 'primary', 'backup']);
  });

  it('moves straight to the next model when a model id is unknown', async () => {
    stub(() => (modelOf(calls.at(-1)) === 'typo-model' ? new Response('not found', { status: 404 }) : reply('{"ok":1}')));
    await gemini.generateJson({ model: 'typo-model', fallbackModels: ['backup'], prompt: 'p', backoffMs: [0, 0] });
    assert.deepEqual(calls.map(modelOf), ['typo-model', 'backup']);
  });

  it('raises the last error when every model is down', async () => {
    stub(() => new Response('{"error":{"message":"high demand"}}', { status: 503 }));
    await assert.rejects(
      gemini.generateJson({ model: 'a', fallbackModels: ['b'], prompt: 'p', backoffMs: [0, 0] }),
      (e) => e.status === 503 && /high demand/.test(gemini.describeError(e)),
    );
    assert.equal(calls.length, 6, 'three attempts on each of the two models');
  });

  it('builds a de-duplicated model chain', () => {
    assert.deepEqual(gemini.modelChain('a', 'a', 'b'), { model: 'a', fallbackModels: ['b'] });
    assert.deepEqual(gemini.modelChain('only'), { model: 'only', fallbackModels: [] });
  });

  it('wraps network failures', async () => {
    global.fetch = async () => {
      throw new TypeError('fetch failed');
    };
    await assert.rejects(gemini.generateJson({ model: 'm', prompt: 'p' }), (e) => e.name === 'GeminiError');
  });
});
