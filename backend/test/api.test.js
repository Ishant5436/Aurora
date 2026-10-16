const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const request = require('supertest');
const { configureEnv, startMongod } = require('./helpers');

configureEnv(); // Gemini is deliberately off: this file covers the offline paths.

describe('Aurora API (no Gemini)', () => {
  let mongo;
  let api;
  let ChallengeSession;

  before(async () => {
    mongo = await startMongod();
    const { connectDb, initModels } = require('../src/config/db');
    const { createApp } = require('../src/app');
    const { ensureSeeded } = require('../src/services/questions');
    ChallengeSession = require('../src/models/ChallengeSession');
    await connectDb(mongo.uri);
    await initModels();
    await ensureSeeded();
    api = request(createApp());
  });

  after(async () => {
    await require('../src/config/db').disconnectDb();
    await mongo.stop();
  });

  async function signIn(name) {
    const res = await api.post('/api/auth/guest').send({ deviceId: `device-${name}-`.padEnd(24, 'x') });
    assert.equal(res.status, 200);
    const header = `Bearer ${res.body.token}`;
    return { id: res.body.user.id, auth: (req) => req.set('Authorization', header) };
  }

  const answerIndexOf = async (sessionId, questionId) =>
    (await ChallengeSession.findById(sessionId)).questions.id(questionId).answerIndex;

  it('reports health', async () => {
    const res = await api.get('/health');
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { ok: true, db: true, ai: false });
  });

  it('returns JSON errors for unknown routes and malformed JSON', async () => {
    const missing = await api.get('/api/nope');
    assert.equal(missing.status, 404);
    assert.equal(missing.body.error.code, 'not_found');
    const bad = await api.post('/api/auth/guest').set('Content-Type', 'application/json').send('{oops');
    assert.equal(bad.status, 400);
    assert.equal(bad.body.error.code, 'bad_json');
  });

  describe('auth', () => {
    it('creates one guest per device and serves /me without leaking secrets', async () => {
      const first = await signIn('auth-a');
      const again = await signIn('auth-a');
      assert.equal(first.id, again.id);
      const me = await first.auth(api.get('/api/auth/me'));
      assert.equal(me.status, 200);
      assert.equal(me.body.user.isGuest, true);
      assert.equal(me.body.user.settings.theme, 'dark');
      assert.equal(me.body.user.passwordHash, undefined);
      assert.equal(me.body.user.deviceId, undefined);
    });

    it('rejects missing, malformed and forged tokens', async () => {
      assert.equal((await api.get('/api/auth/me')).status, 401);
      assert.equal((await api.get('/api/auth/me').set('Authorization', 'Basic abc')).status, 401);
      assert.equal((await api.get('/api/auth/me').set('Authorization', 'Bearer not.a.token')).status, 401);
    });

    it('upgrades a guest on register, then supports login', async () => {
      const guest = await signIn('auth-upgrade');
      const reg = await guest
        .auth(api.post('/api/auth/register'))
        .send({ email: 'Scholar@Example.com', password: 'correct horse battery' });
      assert.equal(reg.status, 201);
      assert.equal(reg.body.user.id, guest.id, 'the guest document is upgraded in place');
      assert.equal(reg.body.user.isGuest, false);
      assert.equal(reg.body.user.email, 'scholar@example.com');

      const sameDevice = await api.post('/api/auth/guest').send({ deviceId: 'device-auth-upgrade-'.padEnd(24, 'x') });
      assert.notEqual(sameDevice.body.user.id, guest.id, 'a registered account is not reachable by device id alone');
      const stillValid = await guest.auth(api.get('/api/auth/me'));
      assert.equal(stillValid.status, 200, 'the existing token keeps working after the upgrade');

      const login = await api.post('/api/auth/login').send({ email: 'scholar@example.com', password: 'correct horse battery' });
      assert.equal(login.status, 200);
      assert.equal(login.body.user.id, guest.id);

      const wrong = await api.post('/api/auth/login').send({ email: 'scholar@example.com', password: 'wrong password' });
      assert.equal(wrong.status, 401);
      const unknown = await api.post('/api/auth/login').send({ email: 'nobody@example.com', password: 'whatever123' });
      assert.equal(unknown.status, 401);
      assert.equal(unknown.body.error.message, wrong.body.error.message);

      const dup = await api.post('/api/auth/register').send({ email: 'scholar@example.com', password: 'another password 1' });
      assert.equal(dup.status, 409);
    });
  });

  describe('settings', () => {
    it('applies partial updates and validates values', async () => {
      const user = await signIn('settings');
      const put = await user.auth(api.put('/api/settings')).send({ theme: 'light', volume: 40, topics: ['React', 'React'] });
      assert.equal(put.status, 200);
      assert.equal(put.body.settings.theme, 'light');
      assert.equal(put.body.settings.volume, 40);
      assert.deepEqual(put.body.settings.topics, ['React']);
      assert.equal(put.body.settings.sound, 'Cathedral Bells', 'untouched keys keep their value');

      const get = await user.auth(api.get('/api/settings'));
      assert.equal(get.body.settings.theme, 'light');

      assert.equal((await user.auth(api.put('/api/settings')).send({ sound: 'Kazoo' })).status, 400);
      assert.equal((await user.auth(api.put('/api/settings')).send({ isAdmin: true })).status, 400);
    });
  });

  describe('alarms', () => {
    it('supports CRUD scoped to the owner', async () => {
      const owner = await signIn('alarm-owner');
      const other = await signIn('alarm-other');

      const created = await owner
        .auth(api.post('/api/alarms'))
        .send({ hour: 6, minute: 30, label: 'Morning Study', days: [3, 1, 1, 2], type: 'MCQ', questions: 3 });
      assert.equal(created.status, 201);
      assert.deepEqual(created.body.alarm.days, [1, 2, 3]);
      assert.equal(created.body.alarm.enabled, true);
      const { id } = created.body.alarm;

      const list = await owner.auth(api.get('/api/alarms'));
      assert.equal(list.body.alarms.length, 1);
      assert.equal((await other.auth(api.get('/api/alarms'))).body.alarms.length, 0);
      assert.equal((await other.auth(api.get(`/api/alarms/${id}`))).status, 404);
      assert.equal((await other.auth(api.patch(`/api/alarms/${id}`)).send({ enabled: false })).status, 404);
      assert.equal((await other.auth(api.delete(`/api/alarms/${id}`))).status, 404);

      const patched = await owner.auth(api.patch(`/api/alarms/${id}`)).send({ enabled: false, minute: 45 });
      assert.equal(patched.status, 200);
      assert.equal(patched.body.alarm.enabled, false);
      assert.equal(patched.body.alarm.minute, 45);
      assert.equal(patched.body.alarm.hour, 6);

      assert.equal((await owner.auth(api.delete(`/api/alarms/${id}`))).status, 204);
      assert.equal((await owner.auth(api.get(`/api/alarms/${id}`))).status, 404);
    });

    it('validates input and rejects unknown fields and foreign notes', async () => {
      const user = await signIn('alarm-validate');
      const post = (payload) => user.auth(api.post('/api/alarms')).send(payload);
      assert.equal((await post({ hour: 25, minute: 0 })).status, 400);
      assert.equal((await post({ minute: 0 })).status, 400);
      assert.equal((await post({ hour: 6, minute: 0, userId: 'x' })).status, 400);
      assert.equal((await post({ hour: 6, minute: 0, type: 'Karaoke' })).status, 400);
      assert.equal((await post({ hour: 6, minute: 0, noteId: new mongoose.Types.ObjectId().toString() })).status, 400);
      assert.equal((await user.auth(api.get('/api/alarms/not-an-id'))).status, 400);
    });
  });

  describe('multiple choice challenge', () => {
    it('runs the full flow without ever revealing answers early', async () => {
      const user = await signIn('mcq');
      const stranger = await signIn('mcq-stranger');
      const alarm = (
        await user
          .auth(api.post('/api/alarms'))
          .send({ hour: 7, minute: 0, type: 'MCQ', questions: 2, topic: 'Algorithms', difficulty: 'Easy' })
      ).body.alarm;

      const start = await user.auth(api.post('/api/challenges/start')).send({ alarmId: alarm.id });
      assert.equal(start.status, 201);
      const session = start.body.session;
      assert.equal(session.kind, 'mcq');
      assert.equal(session.total, 2);
      assert.equal(session.questions.length, 2);
      assert.equal(session.questions[0].options.length, 4);
      assert.ok(!JSON.stringify(start.body).includes('answerIndex'), 'the answer must stay on the server');

      const complete = () => user.auth(api.post(`/api/challenges/${session.id}/complete`)).send({});
      assert.equal((await complete()).status, 409, 'cannot finish before solving everything');
      assert.equal((await stranger.auth(api.get(`/api/challenges/${session.id}`))).status, 404);

      const answer = (qid, selected) =>
        user.auth(api.post(`/api/challenges/${session.id}/answer`)).send({ questionId: qid, selected });

      const [q1, q2] = session.questions;
      const right1 = await answerIndexOf(session.id, q1.id);
      const wrong = await answer(q1.id, (right1 + 1) % 4);
      assert.equal(wrong.body.correct, false);
      assert.equal(wrong.body.explanation, undefined, 'a wrong guess reveals nothing');
      assert.equal(wrong.body.remaining, 2);

      const fixed = await answer(q1.id, right1);
      assert.equal(fixed.body.correct, true);
      assert.equal(typeof fixed.body.explanation, 'string');
      assert.equal(fixed.body.attempts, 2);
      assert.equal((await answer(q1.id, right1)).status, 409, 'solved questions cannot be answered again');

      const right2 = await answerIndexOf(session.id, q2.id);
      assert.equal((await answer(q2.id, right2)).body.remaining, 0);

      const done = await complete();
      assert.equal(done.status, 200);
      assert.deepEqual(
        { success: done.body.result.success, accuracy: done.body.result.accuracy, attempts: done.body.result.attempts },
        { success: true, accuracy: 50, attempts: 3 },
      );
      assert.equal((await complete()).status, 409, 'a finished challenge cannot be finished twice');
    });

    it('falls back to a topic quiz when the note is missing, and can be abandoned', async () => {
      const user = await signIn('mcq-fallback');
      const start = await user
        .auth(api.post('/api/challenges/start'))
        .send({ noteId: new mongoose.Types.ObjectId().toString(), count: 2 });
      assert.equal(start.status, 201);
      assert.equal(start.body.session.kind, 'mcq');
      assert.equal(start.body.session.questions.length, 2);

      const { id, questions } = start.body.session;
      const abandon = await user.auth(api.post(`/api/challenges/${id}/abandon`)).send({});
      assert.equal(abandon.body.status, 'abandoned');
      const late = await user.auth(api.post(`/api/challenges/${id}/answer`)).send({ questionId: questions[0].id, selected: 0 });
      assert.equal(late.status, 409);
    });
  });

  describe('voice challenge (dev heuristic)', () => {
    it('grades attempts, enforces the pass mark and completes with the best one', async () => {
      const user = await signIn('voice');
      const start = await user.auth(api.post('/api/challenges/start')).send({ kind: 'voice', difficulty: 'Medium' });
      assert.equal(start.status, 201);
      const session = start.body.session;
      assert.equal(session.kind, 'voice');
      assert.equal(typeof session.prompt, 'string');
      assert.equal(session.passScore, 70);

      const speak = (seconds) => user.auth(api.post(`/api/challenges/${session.id}/voice`)).send({ seconds });
      const complete = () => user.auth(api.post(`/api/challenges/${session.id}/complete`)).send({});
      assert.equal((await complete()).status, 409, 'an answer is required first');

      const short = await speak(5);
      assert.equal(short.body.mock, true);
      assert.equal(short.body.passed, false);
      const long = await speak(10);
      assert.equal(long.body.passed, true);

      const done = await complete();
      assert.equal(done.body.result.success, true);
      assert.equal(done.body.result.accuracy, long.body.score);
      assert.equal(done.body.result.attempts, 2);
    });

    it('rejects an audio attachment with an unsupported type', async () => {
      const user = await signIn('voice-bad-audio');
      const { session } = (await user.auth(api.post('/api/challenges/start')).send({ kind: 'voice' })).body;
      const res = await user
        .auth(api.post(`/api/challenges/${session.id}/voice`))
        .send({ seconds: 3, audio: { mimeType: 'video/mp4', base64: 'AAAA' } });
      assert.equal(res.status, 400);
    });
  });

  describe('notes without Gemini', () => {
    it('explains that notes need the AI service and validates uploads', async () => {
      const user = await signIn('notes-offline');
      const noAi = await user.auth(api.post('/api/notes')).send({ text: 'a'.repeat(300) });
      assert.equal(noAi.status, 503);
      assert.equal(noAi.body.error.code, 'service_unavailable');

      const both = await user
        .auth(api.post('/api/notes'))
        .send({ text: 'a'.repeat(300), file: { mimeType: 'application/pdf', base64: 'AAAA' } });
      assert.equal(both.status, 400);

      assert.equal((await user.auth(api.get('/api/notes'))).body.notes.length, 0);
      assert.equal((await user.auth(api.delete(`/api/notes/${new mongoose.Types.ObjectId()}`))).status, 404);
      assert.equal((await api.get('/api/notes')).status, 401);
    });
  });
});
