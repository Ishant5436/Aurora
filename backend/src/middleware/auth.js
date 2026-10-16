const jwt = require('jsonwebtoken');
const env = require('../config/env');
const { unauthorized } = require('./errors');

function signToken(userId) {
  return jwt.sign({}, env.JWT_SECRET, {
    subject: String(userId),
    expiresIn: env.JWT_EXPIRES_IN,
    algorithm: 'HS256',
  });
}

function readUserId(req) {
  const header = req.get('authorization');
  if (!header) return null;
  const [scheme, token] = header.split(' ');
  if (scheme?.toLowerCase() !== 'bearer' || !token) throw unauthorized('Malformed Authorization header');
  try {
    const payload = jwt.verify(token, env.JWT_SECRET, { algorithms: ['HS256'] });
    return payload.sub;
  } catch {
    throw unauthorized('Invalid or expired token');
  }
}

function requireAuth(req, _res, next) {
  const userId = readUserId(req);
  if (!userId) throw unauthorized();
  req.userId = userId;
  next();
}

// Used by register: an existing guest token upgrades that account in place.
function optionalAuth(req, _res, next) {
  req.userId = readUserId(req) ?? undefined;
  next();
}

module.exports = { signToken, requireAuth, optionalAuth };
