const { Schema, model } = require('mongoose');

// One spoken-interview question written from the notes, plus the points a strong
// answer should cover. The key points are what the AI grades against, so they
// are never sent to the app (and `interview` is excluded from queries by default).
const interviewSchema = new Schema(
  {
    prompt: { type: String, required: true },
    keyPoints: { type: [String], default: [] },
  },
  { _id: false },
);

// Metadata for an uploaded study note. The raw upload is never stored: only what
// was derived from it is kept, namely the quiz (Question documents carrying this
// noteId) and the interview prompts below.
const noteSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    title: { type: String, required: true, trim: true, maxlength: 80 },
    sourceType: { type: String, enum: ['text', 'file'], required: true },
    questionCount: { type: Number, default: 0 },
    interviewCount: { type: Number, default: 0 },
    interview: { type: [interviewSchema], default: [], select: false },
  },
  {
    timestamps: true,
    toJSON: {
      virtuals: true,
      versionKey: false,
      transform(_doc, ret) {
        delete ret._id;
        delete ret.userId;
        delete ret.interview;
        return ret;
      },
    },
  },
);

module.exports = model('Note', noteSchema);
