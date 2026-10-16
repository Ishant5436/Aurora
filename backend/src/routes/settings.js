const express = require('express');
const { z } = require('zod');
const User = require('../models/User');
const { requireAuth } = require('../middleware/auth');
const { body } = require('../middleware/validate');
const { unauthorized } = require('../middleware/errors');
const { DIFFICULTIES, TOPICS, SOUNDS, THEMES } = require('../config/constants');

const router = express.Router();
router.use(requireAuth, express.json({ limit: '32kb' }));

const patchSchema = z
  .strictObject({
    volume: z.number().int().min(0).max(100),
    sound: z.enum(SOUNDS),
    difficulty: z.enum(DIFFICULTIES),
    topics: z.array(z.enum(TOPICS)).max(TOPICS.length),
    haptics: z.boolean(),
    animations: z.boolean(),
    notifications: z.boolean(),
    theme: z.enum(THEMES),
  })
  .partial();

router.get('/', async (req, res) => {
  const user = await User.findById(req.userId);
  if (!user) throw unauthorized();
  res.json({ settings: user.toJSON().settings });
});

// Accepts any subset of settings and updates only those keys.
router.put('/', async (req, res) => {
  const patch = body(patchSchema, req);
  if (patch.topics) patch.topics = [...new Set(patch.topics)];
  const $set = Object.fromEntries(Object.entries(patch).map(([k, v]) => [`settings.${k}`, v]));
  const user = await User.findByIdAndUpdate(req.userId, { $set }, { returnDocument: 'after', runValidators: true });
  if (!user) throw unauthorized();
  res.json({ settings: user.toJSON().settings });
});

module.exports = router;
