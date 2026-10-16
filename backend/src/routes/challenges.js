const express = require('express');
const { z } = require('zod');
const Alarm = require('../models/Alarm');
const Note = require('../models/Note');
const User = require('../models/User');
const ChallengeSession = require('../models/ChallengeSession');
const { requireAuth } = require('../middleware/auth');
const { aiLimiter } = require('../middleware/limits');
const { objectId, body, params } = require('../middleware/validate');
const {
  HttpError,
  notFoundError,
  conflict,
  badRequest,
  unauthorized,
  unavailable,
} = require('../middleware/errors');
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
  questionId: objectId,
  seconds: z.number().min(0).max(300),
  audio: z
    .strictObject({ mimeType: z.enum(AUDIO_TYPES), base64: z.string().min(1).max(8_500_000) })
    .optional(),
  transcript: z.string().max(5000).optional(),
});

// The client only ever sees this view: answerIndex, explanations of unsolved
// questions and the key points a spoken answer is graded against never leave the server.
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
      : {
          total: s.voiceQuestions.length,
          passScore: VOICE_PASS_SCORE[s.difficulty],
          questions: s.voiceQuestions.map((q) => ({
            id: q.id,
            text: q.prompt,
            solved: q.solved,
            attempts: q.attempts.length,
          })),
        };
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

// "Random" is itself one of the options an alarm can have: it picks between the
// two quiz types. A fixed type is never swapped for the other one.
function chooseKind(requested, voiceReady) {
  if (requested !== 'random') return requested;
  return voiceReady && Math.random() < 0.5 ? 'voice' : 'mcq';
}

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
      kind: ALARM_KIND[alarm.type],
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

  // The source is exactly what the alarm selected: its notes if it uses any,
  // otherwise its topic. Nothing else is ever substituted.
  let note = null;
  if (cfg.noteId) {
    note = await Note.findOne({ _id: cfg.noteId, userId: req.userId }).select('+interview');
    if (!note) {
      throw new HttpError(
        409,
        'source_missing',
        'The notes this alarm uses no longer exist. Edit the alarm to choose a source.',
      );
    }
  }

  const voiceReady = voice.voiceAvailable() && (!note || note.interview.length > 0);
  const kind = chooseKind(cfg.kind, voiceReady);

  if (kind === 'voice') {
    if (!voice.voiceAvailable()) {
      throw unavailable('The voice interview needs the AI examiner. Set GEMINI_API_KEY on the server.');
    }
    if (note && note.interview.length === 0) {
      throw conflict('These notes have no interview questions yet. Upload them again to enable voice interviews.');
    }
  }

  const common = {
    userId: req.userId,
    alarmId,
    difficulty: cfg.difficulty,
    topic: note ? note.title : cfg.topic,
    noteId: note?._id,
  };

  if (kind === 'voice') {
    const picked = note
      ? voice
          .shuffled(note.interview)
          .slice(0, cfg.count)
          .map((i) => ({ prompt: i.prompt, keyPoints: [...i.keyPoints] }))
      : await voice.pickPrompts({ topic: cfg.topic, difficulty: cfg.difficulty, count: cfg.count });
    const session = await ChallengeSession.create({ ...common, kind: 'voice', voiceQuestions: picked });
    return res.status(201).json({ session: publicSession(session) });
  }

  const questions = note
    ? await getNoteQuestions({ noteId: note._id, userId: req.userId, difficulty: cfg.difficulty, count: cfg.count })
    : await getQuestions({ topic: cfg.topic, difficulty: cfg.difficulty, count: cfg.count });
  if (!questions.length) {
    throw new HttpError(409, 'source_empty', 'These notes have no quiz questions yet.');
  }

  const session = await ChallengeSession.create({
    ...common,
    kind: 'mcq',
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

// Grades one spoken answer. A question is solved once it reaches the pass mark;
// until then it can be answered again, just like a multiple-choice question.
router.post('/:id/voice', aiLimiter, voiceJson, async (req, res) => {
  const { id } = params(idParams, req);
  const { questionId, seconds, audio, transcript } = body(voiceSchema, req);
  if (gemini.isConfigured() && !audio && !transcript) {
    throw badRequest('Send a recording (audio) or a transcript of your answer');
  }
  const session = await loadActive(id, req.userId, 'voice');
  const question = session.voiceQuestions.id(questionId);
  if (!question) throw notFoundError('Question');
  if (question.solved) throw conflict('That question is already answered');

  const result = await voice.evaluate({
    prompt: question.prompt,
    keyPoints: question.keyPoints,
    difficulty: session.difficulty,
    audio: audio ? { mimeType: GEMINI_MIME[audio.mimeType] ?? audio.mimeType, base64: audio.base64 } : undefined,
    transcript,
    seconds,
  });

  const passScore = VOICE_PASS_SCORE[session.difficulty];
  const passed = result.score >= passScore;
  question.attempts.push({ score: result.score, feedback: result.feedback, seconds, mock: result.mock });
  question.bestScore = Math.max(question.bestScore, result.score);
  if (passed) question.solved = true;
  await session.save();

  res.json({
    score: result.score,
    feedback: result.feedback,
    passed,
    passScore,
    mock: result.mock,
    attempts: question.attempts.length,
    solved: question.solved,
    remaining: session.voiceQuestions.filter((q) => !q.solved).length,
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
    if (session.voiceQuestions.some((q) => !q.solved)) throw conflict('Answer every question before finishing');
    const best = session.voiceQuestions.map((q) => q.bestScore);
    accuracy = Math.round(best.reduce((sum, s) => sum + s, 0) / best.length);
    attempts = session.voiceQuestions.reduce((sum, q) => sum + q.attempts.length, 0);
    // The most useful note is about the weakest answer.
    const weakest = session.voiceQuestions.reduce((a, b) => (b.bestScore < a.bestScore ? b : a));
    feedback = weakest.attempts.at(-1)?.feedback ?? '';
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

module.exports = router;
