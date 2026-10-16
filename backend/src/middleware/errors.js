const { ZodError } = require('zod');
const mongoose = require('mongoose');

class HttpError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

const badRequest = (message, details) => new HttpError(400, 'bad_request', message, details);
const unauthorized = (message = 'Authentication required') => new HttpError(401, 'unauthorized', message);
const notFoundError = (what = 'Resource') => new HttpError(404, 'not_found', `${what} not found`);
const conflict = (message) => new HttpError(409, 'conflict', message);
const unavailable = (message) => new HttpError(503, 'service_unavailable', message);

function notFoundHandler(req, _res, next) {
  next(notFoundError(`Route ${req.method} ${req.path}`));
}

// Express 5 forwards rejected promises from async handlers here automatically.
// eslint-disable-next-line no-unused-vars
function errorHandler(err, _req, res, _next) {
  let status = 500;
  let code = 'internal_error';
  let message = 'Something went wrong';
  let details;

  if (err instanceof HttpError) {
    ({ status, code, message, details } = err);
  } else if (err instanceof ZodError) {
    status = 400;
    code = 'validation_error';
    message = 'Invalid request';
    details = err.issues.map((i) => ({ path: i.path.join('.'), message: i.message }));
  } else if (err instanceof mongoose.Error.ValidationError) {
    status = 400;
    code = 'validation_error';
    message = 'Invalid data';
    details = Object.values(err.errors).map((e) => ({ path: e.path, message: e.message }));
  } else if (err instanceof mongoose.Error.CastError) {
    status = 400;
    code = 'bad_request';
    message = `Invalid ${err.path}`;
  } else if (err?.code === 11000) {
    status = 409;
    code = 'conflict';
    message = 'That value is already in use';
  } else if (err?.type === 'entity.parse.failed') {
    status = 400;
    code = 'bad_json';
    message = 'Request body is not valid JSON';
  } else if (err?.type === 'entity.too.large') {
    status = 413;
    code = 'payload_too_large';
    message = 'Request body is too large';
  }

  // HttpErrors are deliberate (services already log their cause); only surprises get a stack.
  if (status >= 500 && !(err instanceof HttpError)) console.error('[error]', err);
  res.status(status).json({ error: { code, message, ...(details ? { details } : {}) } });
}

module.exports = {
  HttpError,
  badRequest,
  unauthorized,
  notFoundError,
  conflict,
  unavailable,
  notFoundHandler,
  errorHandler,
};
