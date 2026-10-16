const { Schema, model } = require('mongoose');
const { DIFFICULTIES, TOPICS } = require('../config/constants');

// A reusable question bank. Gemini-generated questions are cached here so an
// alarm going off never waits on (or pays for) a fresh model call.
const questionSchema = new Schema(
  {
    textHash: { type: String, required: true, unique: true },
    // Built-in questions have a topic; questions generated from a user's notes
    // belong to that note (and its owner) instead.
    topic: { type: String, enum: TOPICS, required: function () { return !this.noteId; } },
    noteId: { type: Schema.Types.ObjectId, ref: 'Note', index: true },
    userId: { type: Schema.Types.ObjectId, ref: 'User' },
    difficulty: { type: String, enum: DIFFICULTIES, required: true },
    text: { type: String, required: true },
    options: {
      type: [String],
      validate: { validator: (v) => v.length === 4, message: 'A question needs exactly 4 options' },
    },
    answerIndex: { type: Number, min: 0, max: 3, required: true },
    explanation: { type: String, default: '' },
    source: { type: String, enum: ['seed', 'gemini', 'note'], required: true },
  },
  { timestamps: true },
);

questionSchema.index({ topic: 1, difficulty: 1 });

module.exports = model('Question', questionSchema);
