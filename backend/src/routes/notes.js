const express = require('express');
const { z } = require('zod');
const Note = require('../models/Note');
const { requireAuth } = require('../middleware/auth');
const { aiLimiter } = require('../middleware/limits');
const { objectId, body, params } = require('../middleware/validate');
const { notFoundError } = require('../middleware/errors');
const { createNoteFromUpload, deleteNote } = require('../services/notes');

const router = express.Router();
router.use(requireAuth);

const BASE64 = /^[A-Za-z0-9+/=\r\n]+$/;

// Send pasted text, or a file as base64 (PDF, .txt or .md). Exactly one of the two.
const uploadSchema = z
  .strictObject({
    title: z.string().trim().min(1).max(80).optional(),
    text: z.string().max(200_000).optional(),
    file: z
      .strictObject({
        name: z.string().max(200).optional(),
        mimeType: z.string().max(100),
        base64: z.string().min(1).max(14_500_000).regex(BASE64, 'base64 data expected'),
      })
      .optional(),
  })
  .refine((v) => Boolean(v.text) !== Boolean(v.file), { message: 'Provide either text or a file, not both' });

const idParams = z.object({ id: objectId });

router.get('/', async (req, res) => {
  const notes = await Note.find({ userId: req.userId }).sort({ createdAt: -1 });
  res.json({ notes: notes.map((n) => n.toJSON()) });
});

// Auth runs first (above) so anonymous callers cannot make us parse a 15 MB body.
router.post('/', aiLimiter, express.json({ limit: '15mb' }), async (req, res) => {
  const data = body(uploadSchema, req);
  const note = await createNoteFromUpload({ userId: req.userId, ...data });
  res.status(201).json({ note: note.toJSON() });
});

router.delete('/:id', async (req, res) => {
  const { id } = params(idParams, req);
  const note = await deleteNote({ userId: req.userId, noteId: id });
  if (!note) throw notFoundError('Note');
  res.status(204).end();
});

module.exports = router;
