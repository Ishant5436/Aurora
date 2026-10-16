const { Schema, model } = require('mongoose');

// Metadata for an uploaded study note. The raw upload is never stored: only the
// questions generated from it (Question documents carrying this noteId) are kept.
const noteSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    title: { type: String, required: true, trim: true, maxlength: 80 },
    sourceType: { type: String, enum: ['text', 'file'], required: true },
    questionCount: { type: Number, default: 0 },
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

module.exports = model('Note', noteSchema);
