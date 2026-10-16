const { Schema, model } = require('mongoose');
const { DIFFICULTIES, TOPICS, SOUNDS, THEMES } = require('../config/constants');

const settingsSchema = new Schema(
  {
    volume: { type: Number, min: 0, max: 100, default: 70 },
    sound: { type: String, enum: SOUNDS, default: SOUNDS[0] },
    difficulty: { type: String, enum: DIFFICULTIES, default: 'Medium' },
    topics: { type: [{ type: String, enum: TOPICS }], default: ['JavaScript', 'Algorithms'] },
    haptics: { type: Boolean, default: true },
    animations: { type: Boolean, default: true },
    notifications: { type: Boolean, default: true },
    theme: { type: String, enum: THEMES, default: 'dark' },
  },
  { _id: false },
);

const userSchema = new Schema(
  {
    // Guests are keyed by a random client-generated id; registering upgrades
    // the same document so alarms and history survive.
    deviceId: { type: String, unique: true, sparse: true },
    email: { type: String, unique: true, sparse: true, lowercase: true, trim: true },
    passwordHash: { type: String, select: false },
    displayName: { type: String, trim: true, maxlength: 60, default: 'Guest Scholar' },
    isGuest: { type: Boolean, default: true },
    settings: { type: settingsSchema, default: () => ({}) },
  },
  {
    timestamps: true,
    toJSON: {
      virtuals: true,
      versionKey: false,
      transform(_doc, ret) {
        delete ret._id;
        delete ret.passwordHash;
        delete ret.deviceId;
        return ret;
      },
    },
  },
);

module.exports = model('User', userSchema);
