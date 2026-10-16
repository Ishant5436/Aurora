const mongoose = require('mongoose');
const { z } = require('zod');

const objectId = z.string().refine((v) => mongoose.isValidObjectId(v), 'Invalid id');

// Validates req.body / req.params against a zod schema and returns the parsed
// value. ZodError is turned into a 400 by the central error handler.
const body = (schema, req) => schema.parse(req.body ?? {});
const params = (schema, req) => schema.parse(req.params);

module.exports = { objectId, body, params };
