const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { configureEnv, startMongod } = require('./helpers');

// No Gemini key and no dev voice heuristic: the server cannot run a voice
// interview. That is exactly the situation in which it used to quietly fall back
// to multiple choice, so it is the right place to prove that no longer happens.
configureEnv({ ALLOW_MOCK_VOICE: 'false' });

describe('Selected options are never substituted (no AI, no mock voice)', () => {
  let mongo;
  let api;
  let Note;
  let Question;

  before(async () => {
    mongo = await startMongod();
    const { connectDb, initModels } = require('../src/config/db');
    const { createApp } = require('../src/app');
    const { ensureSeeded } = require('../src/services/questions');
    Note = require('../src/models/Note');
    Question = require('../src/models/Question');
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
    const header = `Bearer ${res.body.token}`;
    return { id: res.body.user.id, auth: (req) => req.set('Authorization', header) };
  }

  // Notes are normally created by the AI; here they are inserted directly.
  async function makeNote(user, { questions = 6 } = {}) {
    const note = await Note.create({
      userId: user.id,
      title: 'My Notes',
      sourceType: 'text',
      questionCount: questions,
    });
    await Question.insertMany(
      Array.from({ length: questions }, (_, i) => ({
        textHash: `${note._id}:${i}`,
        difficulty: 'Medium',
        text: `Note question ${i}`,
        options: ['a', 'b', 'c', 'd'],
        answerIndex: 0,
        source: 'note',
        noteId: note._id,
        userId: user.id,
      })),
    );
    return note;
  }

  const makeAlarm = async (user, payload) =>
    (await user.auth(api.post('/api/alarms')).send({ hour: 6, minute: 0, ...payload })).body.alarm;
  const start = (user, alarm) => user.auth(api.post('/api/challenges/start')).send({ alarmId: alarm.id });

  it('a voice alarm is an error when voice cannot run, never a multiple-choice quiz', async () => {
    const user = await signIn('strict-voice');
    const alarm = await makeAlarm(user, { type: 'Voice', topic: 'Networking' });
    const res = await start(user, alarm);
    assert.equal(res.status, 503);
    assert.equal(res.body.error.code, 'service_unavailable');
    assert.match(res.body.error.message, /voice interview/i);
  });

  it('a random alarm only ever chooses a type it can actually run', async () => {
    const user = await signIn('strict-random');
    const alarm = await makeAlarm(user, { type: 'Random', topic: 'Python', questions: 2 });
    for (let i = 0; i < 6; i++) {
      const res = await start(user, alarm);
      assert.equal(res.status, 201);
      assert.equal(res.body.session.kind, 'mcq');
    }
  });

  it('a notes alarm quizzes only on those notes, whatever topic is also set', async () => {
    const user = await signIn('strict-notes');
    const note = await makeNote(user);
    const alarm = await makeAlarm(user, { type: 'MCQ', questions: 3, topic: 'Python', noteId: note.id });

    const res = await start(user, alarm);
    assert.equal(res.status, 201);
    assert.equal(res.body.session.topic, 'My Notes');
    assert.equal(res.body.session.questions.length, 3);
    assert.ok(res.body.session.questions.every((q) => q.text.startsWith('Note question')));
  });

  it('an alarm whose notes have gone is an error, not a quiz on something else', async () => {
    const user = await signIn('strict-gone');
    const note = await makeNote(user);
    const alarm = await makeAlarm(user, { type: 'MCQ', noteId: note.id, topic: 'JavaScript' });
    await Note.deleteOne({ _id: note._id }); // gone behind the alarm's back

    const res = await start(user, alarm);
    assert.equal(res.status, 409);
    assert.equal(res.body.error.code, 'source_missing');
  });

  it('an alarm whose notes hold no quiz questions is an error too', async () => {
    const user = await signIn('strict-empty');
    const note = await makeNote(user, { questions: 0 });
    const alarm = await makeAlarm(user, { type: 'MCQ', noteId: note.id });

    const res = await start(user, alarm);
    assert.equal(res.status, 409);
    assert.equal(res.body.error.code, 'source_empty');
  });
});
