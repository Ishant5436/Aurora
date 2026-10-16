const crypto = require('node:crypto');
const mongoose = require('mongoose');
const { z } = require('zod');
const Question = require('../models/Question');
const gemini = require('./gemini');
const env = require('../config/env');
const { DIFFICULTIES } = require('../config/constants');
const { QUESTIONS } = require('../data/questionBank');
const { HttpError } = require('../middleware/errors');

const CACHE_TARGET = 24; // cached questions we try to keep per topic + difficulty

const oid = (v) => new mongoose.Types.ObjectId(String(v));

const hashText = (text) =>
  crypto.createHash('sha1').update(text.toLowerCase().replace(/\s+/g, ' ').trim()).digest('hex');

// Shape every generated question must satisfy before it is stored.
const generatedQuestion = z
  .object({
    text: z.string().min(10).max(400),
    options: z.array(z.string().min(1).max(200)).length(4),
    answerIndex: z.number().int().min(0).max(3),
    explanation: z.string().max(400).default(''),
    difficulty: z.enum(DIFFICULTIES).optional(),
  })
  .refine((q) => new Set(q.options.map((o) => o.trim().toLowerCase())).size === 4, {
    message: 'options must be distinct',
  });

// Language models over-pick certain answer positions, so we shuffle ourselves.
function shuffleWithAnswer(q) {
  const order = [0, 1, 2, 3];
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  return { ...q, options: order.map((i) => q.options[i]), answerIndex: order.indexOf(q.answerIndex) };
}

async function upsertQuestions(docs) {
  if (!docs.length) return;
  await Question.bulkWrite(
    docs.map(({ textHash, ...rest }) => ({
      updateOne: { filter: { textHash }, update: { $setOnInsert: rest }, upsert: true },
    })),
    { ordered: false },
  );
}

async function ensureSeeded() {
  await upsertQuestions(QUESTIONS.map((q) => ({ ...q, textHash: hashText(q.text), source: 'seed' })));
}

async function sample(match, size, exclude = []) {
  if (size <= 0) return [];
  return Question.aggregate([
    { $match: { ...match, _id: { $nin: exclude } } },
    { $sample: { size } },
  ]);
}

const inflight = new Map();
function generateBuiltin({ topic, difficulty, count }) {
  const key = `${topic}|${difficulty}`;
  if (inflight.has(key)) return inflight.get(key);
  const promise = (async () => {
    const prompt = [
      'You write multiple-choice quiz questions for software engineers.',
      `Write ${count} questions about "${topic}" at ${difficulty} difficulty.`,
      'Rules: exactly 4 distinct options, exactly one correct, plausible distractors,',
      'no "all of the above", every question fully self-contained.',
      'Return JSON: {"questions":[{"text":string,"options":[string,string,string,string],',
      '"answerIndex":0-3,"explanation":"one sentence"}]}',
    ].join(' ');
    const raw = await gemini.generateJson({ ...gemini.modelChain(env.GEMINI_MODEL), prompt, temperature: 0.8 });
    const { questions } = z.object({ questions: z.array(generatedQuestion).min(1) }).parse(raw);
    await upsertQuestions(
      questions.map(shuffleWithAnswer).map((q) => ({
        text: q.text,
        options: q.options,
        answerIndex: q.answerIndex,
        explanation: q.explanation,
        topic,
        difficulty,
        source: 'gemini',
        textHash: hashText(q.text),
      })),
    );
  })().finally(() => inflight.delete(key));
  inflight.set(key, promise);
  return promise;
}

// Keeps the cache warm in the background so the next alarm never waits on Gemini.
function topUp(topic, difficulty) {
  if (!gemini.isConfigured()) return;
  Question.countDocuments({ topic, difficulty })
    .then((n) => (n < CACHE_TARGET ? generateBuiltin({ topic, difficulty, count: 8 }) : null))
    .catch((err) => console.warn('[questions] cache top-up failed:', err.message));
}

async function getQuestions({ topic, difficulty, count }) {
  let picked = await sample({ topic, difficulty }, count);

  if (picked.length < count && gemini.isConfigured()) {
    try {
      await generateBuiltin({ topic, difficulty, count: Math.max(count, 6) });
      picked = await sample({ topic, difficulty }, count);
    } catch (err) {
      console.warn('[questions] generation failed, using cached questions:', gemini.describeError(err));
    }
  }

  // Never widen to another topic or difficulty: the alarm asked for exactly this
  // source. If the bank is short and the AI cannot fill the gap, the quiz is
  // shorter than requested rather than quietly about something else.
  if (picked.length === 0) {
    throw new HttpError(
      503,
      'no_questions',
      `No ${difficulty} questions about ${topic} are available right now. Please try again in a moment.`,
    );
  }
  topUp(topic, difficulty);
  return picked;
}

// Returns [] when the note has no questions, so callers can fall back to a topic.
async function getNoteQuestions({ noteId, userId, difficulty, count }) {
  const match = { noteId: oid(noteId), userId: oid(userId) };
  let picked = await sample({ ...match, difficulty }, count);
  if (picked.length < count) {
    picked = picked.concat(await sample(match, count - picked.length, picked.map((p) => p._id)));
  }
  return picked;
}

module.exports = {
  ensureSeeded,
  getQuestions,
  getNoteQuestions,
  upsertQuestions,
  shuffleWithAnswer,
  generatedQuestion,
  hashText,
};
