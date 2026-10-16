const express = require('express');
const { z } = require('zod');
const Alarm = require('../models/Alarm');
const Note = require('../models/Note');
const User = require('../models/User');
const ChallengeSession = require('../models/ChallengeSession');
const { requireAuth } = require('../middleware/auth');
const { aiLimiter } = require('../middleware/limits');
const { objectId, body, params } = require('../middleware/validate');
const { notFoundError, conflict, badRequest, unauthorized } = require('../middleware/errors');
const { DIFFICULTIES, TOPICS } = require('../config/constants');
const gemini = require('../services/gemini');
const { getQuestions, getNoteQuestions } = require('../services/questions');
const voice = require('../services/voice');
const { isDismissed, VOICE_PASS_SCORE } = require('../policy/dismissal');

const router = express.Router();
router.use(requireAuth);
const smallJson = express.json({ limit: '32kb' });
// ~90s of 16 kHz mono WAV is about 3 MB; base64 inflates that by a third.
const voiceJson = express.json({ limit: '6mb' });

const idParams = z.object({ id: objectId });
const ALARM_KIND = { MCQ: 'mcq', Voice: 'voice', Random: 'random' };
const AUDIO_TYPES = ['audio/wav', 'audio/mpeg', 'audio/mp3', 'audio/aac', 'audio/ogg', 'audio/flac', 'audio/aiff', 'audio/m4a', 'audio/mp4'];
const GEMINI_MIME = { 'audio/mp4': 'audio/m4a' };

const startSchema = z.strictObject({
  alarmId: objectId.optional(),
  kind: z.enum(['mcq', 'voice', 'random']).optional(),
  topic: z.enum(TOPICS).optional(),
  noteId: objectId.optional(),
  difficulty: z.enum(DIFFICULTIES).optional(),
  count: z.number().int().min(1).max(4).optional(),
});
const answerSchema = z.strictObject({
  questionId: objectId,
  selected: z.number().int().min(0).max(3),
});
const voiceSchema = z.strictObject({
  seconds: z.number().min(0).max(300),
  audio: z
    .strictObject({ mimeType: z.enum(AUDIO_TYPES), base64: z.string().min(1).max(8_500_000) })
    .optional(),
  transcript: z.string().max(5000).optional(),
});

// The client only ever sees this view: answerIndex and explanations of
// unsolved questions never leave the server.
function publicSession(s) {
  const base = {
    id: s.id,
    kind: s.kind,
    topic: s.topic,
    difficulty: s.difficulty,
    status: s.status,
    startedAt: s.startedAt,
  };
  const detail =
    s.kind === 'mcq'
      ? {
          total: s.questions.length,
          questions: s.questions.map((q) => ({
            id: q.id,
            text: q.text,
            options: q.options,
            solved: q.solved,
            attempts: q.attempts,
          })),
        }
      : { prompt: s.voicePrompt, passScore: VOICE_PASS_SCORE[s.difficulty] };
  return { ...base, ...detail, ...(s.result ? { result: s.toJSON().result } : {}) };
}

async function loadActive(id, userId, kind) {
  const session = await ChallengeSession.findOne({ _id: id, userId });
  if (!session) throw notFoundError('Challenge');
  if (session.status !== 'active') throw conflict('This challenge is already finished');
  if (kind && session.kind !== kind) throw conflict(`This is a ${session.kind} challenge`);
  return session;
}

const mcqFeedback = (accuracy) =>
  accuracy === 100
    ? "Flawless. Thy mind is as sharp as Brunelleschi's compass."
    : 'Well fought. Revisit the questions you stumbled upon to strengthen thy recall.';

router.post('/start', aiLimiter, smallJson, async (req, res) => {
  const input = body(startSchema, req);
  const user = await User.findById(req.userId).select('settings');
  if (!user) throw unauthorized();

  let cfg = { ...input };
  let alarmId;
  if (input.alarmId) {
    const alarm = await Alarm.findOne({ _id: input.alarmId, userId: req.userId });
    if (!alarm) throw notFoundError('Alarm');
    alarmId = alarm._id;
    cfg = {
      // The app may downgrade to multiple choice (e.g. microphone switched off) but never upgrade.
      kind: input.kind === 'mcq' ? 'mcq' : ALARM_KIND[alarm.type],
      topic: alarm.topic,
      noteId: alarm.noteId ? String(alarm.noteId) : undefined,
      difficulty: alarm.difficulty,
      count: alarm.questions,
    };
  }
  cfg.kind ??= 'mcq';
  cfg.difficulty ??= user.settings.difficulty;
  cfg.topic ??= user.settings.topics[0] ?? 'JavaScript';
  cfg.count ??= 3;

  let kind = cfg.kind === 'random' ? (Math.random() < 0.5 ? 'mcq' : 'voice') : cfg.kind;
  // Quizzes built from the user's notes are multiple choice, and voice needs the AI.
  if (cfg.noteId || (kind === 'voice' && !voice.voiceAvailable())) kind = 'mcq';

  const common = { userId: req.userId, alarmId, difficulty: cfg.difficulty };

  if (kind === 'voice') {
    const prompt = await voice.pickPrompt({ topic: cfg.topic, difficulty: cfg.difficulty });
    const session = await ChallengeSession.create({ ...common, kind, topic: cfg.topic, voicePrompt: prompt });
    return res.status(201).json({ session: publicSession(session) });
  }

  let questions = [];
  let note;
  if (cfg.noteId) {
    note = await Note.findOne({ _id: cfg.noteId, userId: req.userId });
    if (note) {
      questions = await getNoteQuestions({
        noteId: note._id,
        userId: req.userId,
        difficulty: cfg.difficulty,
        count: cfg.count,
      });
    }
  }
  // A deleted or empty note must never leave the alarm unable to ring a quiz.
  if (!questions.length) {
    note = undefined;
    questions = await getQuestions({ topic: cfg.topic, difficulty: cfg.difficulty, count: cfg.count });
  }

  const session = await ChallengeSession.create({
    ...common,
    kind: 'mcq',
    topic: note ? note.title : cfg.topic,
    noteId: note?._id,
    questions: questions.map((q) => ({
      text: q.text,
      options: q.options,
      answerIndex: q.answerIndex,
      explanation: q.explanation,
    })),
  });
  res.status(201).json({ session: publicSession(session) });
});

router.get('/:id', async (req, res) => {
  const { id } = params(idParams, req);
  const session = await ChallengeSession.findOne({ _id: id, userId: req.userId });
  if (!session) throw notFoundError('Challenge');
  res.json({ session: publicSession(session) });
});

router.post('/:id/answer', smallJson, async (req, res) => {
  const { id } = params(idParams, req);
  const { questionId, selected } = body(answerSchema, req);
  const session = await loadActive(id, req.userId, 'mcq');
  const question = session.questions.id(questionId);
  if (!question) throw notFoundError('Question');
  if (question.solved) throw conflict('That question is already solved');

  question.attempts += 1;
  const correct = selected === question.answerIndex;
  if (correct) {
    question.solved = true;
    question.solvedFirstTry = question.attempts === 1;
  }
  await session.save();

  res.json({
    correct,
    solved: question.solved,
    attempts: question.attempts,
    remaining: session.questions.filter((q) => !q.solved).length,
    // Revealed only once solved, so a wrong guess teaches nothing about the answer.
    ...(correct ? { explanation: question.explanation } : {}),
  });
});

router.post('/:id/voice', aiLimiter, voiceJson, async (req, res) => {
  const { id } = params(idParams, req);
  const { seconds, audio, transcript } = body(voiceSchema, req);
  if (gemini.isConfigured() && !audio && !transcript) {
    throw badRequest('Send a recording (audio) or a transcript of your answer');
  }
  const session = await loadActive(id, req.userId, 'voice');

  const result = await voice.evaluate({
    prompt: session.voicePrompt,
    difficulty: session.difficulty,
    audio: audio ? { mimeType: GEMINI_MIME[audio.mimeType] ?? audio.mimeType, base64: audio.base64 } : undefined,
    transcript,
    seconds,
  });

  session.voiceAttempts.push({ score: result.score, feedback: result.feedback, seconds, mock: result.mock });
  await session.save();

  const passScore = VOICE_PASS_SCORE[session.difficulty];
  res.json({
    score: result.score,
    feedback: result.feedback,
    passed: result.score >= passScore,
    passScore,
    mock: result.mock,
    attempts: session.voiceAttempts.length,
  });
});

router.post('/:id/complete', smallJson, async (req, res) => {
  const { id } = params(idParams, req);
  const session = await loadActive(id, req.userId);

  let accuracy;
  let attempts;
  let feedback;
  if (session.kind === 'mcq') {
    if (session.questions.some((q) => !q.solved)) throw conflict('Solve every question before finishing');
    const firstTry = session.questions.filter((q) => q.solvedFirstTry).length;
    accuracy = Math.round((firstTry / session.questions.length) * 100);
    attempts = session.questions.reduce((sum, q) => sum + q.attempts, 0);
    feedback = mcqFeedback(accuracy);
  } else {
    if (!session.voiceAttempts.length) throw conflict('Give your answer before finishing');
    const best = session.voiceAttempts.reduce((a, b) => (b.score > a.score ? b : a));
    accuracy = Math.round(best.score);
    attempts = session.voiceAttempts.length;
    feedback = best.feedback;
  }

  const success = isDismissed({ kind: session.kind, difficulty: session.difficulty, accuracy });
  session.status = 'completed';
  session.completedAt = new Date();
  session.result = {
    success,
    accuracy,
    attempts,
    seconds: Math.max(0, Math.round((Date.now() - session.startedAt.getTime()) / 1000)),
    feedback,
  };
  await session.save();
  res.json({ result: session.toJSON().result });
});

// "Emergency dismiss": always allowed (an alarm must never trap someone), but recorded.
router.post('/:id/abandon', smallJson, async (req, res) => {
  const { id } = params(idParams, req);
  const session = await loadActive(id, req.userId);
  session.status = 'abandoned';
  session.completedAt = new Date();
  await session.save();
  res.json({ status: session.status });
});

module.exports = router;
