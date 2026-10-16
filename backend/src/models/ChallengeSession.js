const { Schema, model } = require('mongoose');
const { DIFFICULTIES } = require('../config/constants');

// answerIndex lives only on the server. The client receives questions through
// publicSession() in routes/challenges.js, which strips it. Otherwise anyone
// could read the answer out of the network response and cheat their own alarm.
const sessionQuestionSchema = new Schema({
  text: { type: String, required: true },
  options: [String],
  answerIndex: { type: Number, required: true },
  explanation: { type: String, default: '' },
  attempts: { type: Number, default: 0 },
  solved: { type: Boolean, default: false },
  solvedFirstTry: { type: Boolean, default: false },
});

// Only scores are stored for voice, never audio or transcripts.
const voiceAttemptSchema = new Schema(
  {
    score: { type: Number, min: 0, max: 100, required: true },
    feedback: { type: String, default: '' },
    seconds: { type: Number, min: 0, default: 0 },
    mock: { type: Boolean, default: false },
    at: { type: Date, default: Date.now },
  },
  { _id: false },
);

// One spoken question. keyPoints come from the user's own notes (empty for a
// built-in topic) and, like answerIndex above, never leave the server.
const voiceQuestionSchema = new Schema({
  prompt: { type: String, required: true },
  keyPoints: { type: [String], default: [] },
  attempts: { type: [voiceAttemptSchema], default: [] },
  bestScore: { type: Number, default: 0 },
  solved: { type: Boolean, default: false },
});

const resultSchema = new Schema(
  {
    success: Boolean,
    accuracy: Number,
    attempts: Number,
    seconds: Number,
    feedback: String,
  },
  { _id: false },
);

const sessionSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    alarmId: { type: Schema.Types.ObjectId, ref: 'Alarm' },
    kind: { type: String, enum: ['mcq', 'voice'], required: true },
    // A built-in topic, or the note title when the quiz comes from user notes.
    topic: { type: String, required: true },
    noteId: { type: Schema.Types.ObjectId, ref: 'Note' },
    difficulty: { type: String, enum: DIFFICULTIES, required: true },
    status: { type: String, enum: ['active', 'completed'], default: 'active' },
    questions: [sessionQuestionSchema],
    voiceQuestions: [voiceQuestionSchema],
    startedAt: { type: Date, default: Date.now },
    completedAt: Date,
    result: resultSchema,
  },
  { timestamps: true },
);

sessionSchema.index({ userId: 1, startedAt: -1 });

module.exports = model('ChallengeSession', sessionSchema);
