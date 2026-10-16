const { Schema, model } = require('mongoose');
const { DIFFICULTIES, CHALLENGE_TYPES, TOPICS } = require('../config/constants');

const alarmSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    hour: { type: Number, required: true, min: 0, max: 23 },
    minute: { type: Number, required: true, min: 0, max: 59 },
    label: { type: String, trim: true, maxlength: 40, default: 'Alarm' },
    // 0 = Sunday to 6 = Saturday (matches the Flutter day row). Empty = one-shot.
    days: { type: [{ type: Number, min: 0, max: 6 }], default: [] },
    enabled: { type: Boolean, default: true },
    difficulty: { type: String, enum: DIFFICULTIES, default: 'Medium' },
    type: { type: String, enum: CHALLENGE_TYPES, default: 'MCQ' },
    questions: { type: Number, min: 1, max: 4, default: 3 },
    topic: { type: String, enum: TOPICS, default: 'JavaScript' },
    // When set, questions come from this uploaded note instead of `topic`.
    noteId: { type: Schema.Types.ObjectId, ref: 'Note', default: null },
  },
  {
    timestamps: true,
    toJSON: {
      virtuals: true,
      versionKey: false,
      transform(_doc, ret) {
        delete ret._id;
        delete ret.userId;
        return ret;
      },
    },
  },
);

module.exports = model('Alarm', alarmSchema);
