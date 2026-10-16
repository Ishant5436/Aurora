const express = require('express');
const { z } = require('zod');
const Alarm = require('../models/Alarm');
const Note = require('../models/Note');
const { requireAuth } = require('../middleware/auth');
const { objectId, body, params } = require('../middleware/validate');
const { notFoundError, conflict, badRequest } = require('../middleware/errors');
const { DIFFICULTIES, CHALLENGE_TYPES, TOPICS } = require('../config/constants');

const MAX_ALARMS = 50;

const router = express.Router();
router.use(requireAuth, express.json({ limit: '32kb' }));

const shape = {
  hour: z.number().int().min(0).max(23),
  minute: z.number().int().min(0).max(59),
  label: z.string().trim().max(40),
  days: z.array(z.number().int().min(0).max(6)).max(7),
  enabled: z.boolean(),
  difficulty: z.enum(DIFFICULTIES),
  type: z.enum(CHALLENGE_TYPES),
  questions: z.number().int().min(1).max(4),
  topic: z.enum(TOPICS),
  noteId: objectId.nullable(),
};
const createSchema = z.strictObject(shape).partial().required({ hour: true, minute: true });
const updateSchema = z.strictObject(shape).partial();
const idParams = z.object({ id: objectId });

const normalise = (data) => (data.days ? { ...data, days: [...new Set(data.days)].sort((a, b) => a - b) } : data);

async function assertNoteOwned(noteId, userId) {
  if (noteId && !(await Note.exists({ _id: noteId, userId }))) {
    throw badRequest('That note does not exist');
  }
}

router.get('/', async (req, res) => {
  const alarms = await Alarm.find({ userId: req.userId }).sort({ hour: 1, minute: 1 });
  res.json({ alarms: alarms.map((a) => a.toJSON()) });
});

router.post('/', async (req, res) => {
  const data = normalise(body(createSchema, req));
  await assertNoteOwned(data.noteId, req.userId);
  if ((await Alarm.countDocuments({ userId: req.userId })) >= MAX_ALARMS) {
    throw conflict(`You can have at most ${MAX_ALARMS} alarms`);
  }
  const alarm = await Alarm.create({ ...data, userId: req.userId });
  res.status(201).json({ alarm: alarm.toJSON() });
});

router.get('/:id', async (req, res) => {
  const { id } = params(idParams, req);
  const alarm = await Alarm.findOne({ _id: id, userId: req.userId });
  if (!alarm) throw notFoundError('Alarm');
  res.json({ alarm: alarm.toJSON() });
});

router.patch('/:id', async (req, res) => {
  const { id } = params(idParams, req);
  const data = normalise(body(updateSchema, req));
  await assertNoteOwned(data.noteId, req.userId);
  const alarm = await Alarm.findOneAndUpdate(
    { _id: id, userId: req.userId },
    { $set: data },
    { returnDocument: 'after', runValidators: true },
  );
  if (!alarm) throw notFoundError('Alarm');
  res.json({ alarm: alarm.toJSON() });
});

router.delete('/:id', async (req, res) => {
  const { id } = params(idParams, req);
  const deleted = await Alarm.findOneAndDelete({ _id: id, userId: req.userId });
  if (!deleted) throw notFoundError('Alarm');
  res.status(204).end();
});

module.exports = router;
