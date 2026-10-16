const express = require('express');
const bcrypt = require('bcryptjs');
const { z } = require('zod');
const User = require('../models/User');
const { signToken, requireAuth, optionalAuth } = require('../middleware/auth');
const { body } = require('../middleware/validate');
const { unauthorized, conflict } = require('../middleware/errors');

const router = express.Router();
router.use(express.json({ limit: '32kb' }));

// Compared against when the email is unknown so login timing does not reveal
// which addresses are registered.
const DUMMY_HASH = bcrypt.hashSync('not-a-real-password', 10);

const email = z.email().max(254).transform((v) => v.toLowerCase());
const password = z.string().min(8).max(128);

const guestSchema = z.strictObject({ deviceId: z.string().min(16).max(128) });
const registerSchema = z.strictObject({
  email,
  password,
  displayName: z.string().trim().min(1).max(60).optional(),
});
const loginSchema = z.strictObject({ email, password: z.string().min(1).max(128) });

const session = (user) => ({ token: signToken(user.id), user: user.toJSON() });

// Guests are keyed by a random id the app generates once and keeps on the device.
router.post('/guest', async (req, res) => {
  const { deviceId } = body(guestSchema, req);
  let user = await User.findOne({ deviceId });
  if (!user) {
    try {
      user = await User.create({ deviceId });
    } catch (err) {
      if (err?.code !== 11000) throw err;
      user = await User.findOne({ deviceId }); // lost a creation race
    }
  }
  res.json(session(user));
});

// With a guest token this upgrades that account in place, keeping alarms and notes.
router.post('/register', optionalAuth, async (req, res) => {
  const data = body(registerSchema, req);
  if (await User.exists({ email: data.email })) throw conflict('That email is already registered');
  const passwordHash = await bcrypt.hash(data.password, 12);

  let user = req.userId ? await User.findById(req.userId) : null;
  if (req.userId && !user) throw unauthorized();
  if (user && !user.isGuest) throw conflict('You are already signed in with an account');

  if (user) {
    user.set({ email: data.email, passwordHash, isGuest: false });
    // From here on the password is the only way in. Leaving the device id on the
    // document would keep a password-free door open to anyone who knows it.
    user.set('deviceId', undefined);
    if (data.displayName) user.displayName = data.displayName;
    await user.save();
  } else {
    user = await User.create({
      email: data.email,
      passwordHash,
      isGuest: false,
      displayName: data.displayName ?? data.email.split('@')[0],
    });
  }
  res.status(201).json(session(user));
});

router.post('/login', async (req, res) => {
  const data = body(loginSchema, req);
  const user = await User.findOne({ email: data.email }).select('+passwordHash');
  const ok = await bcrypt.compare(data.password, user?.passwordHash ?? DUMMY_HASH);
  if (!user || !ok) throw unauthorized('Incorrect email or password');
  res.json(session(user));
});

router.get('/me', requireAuth, async (req, res) => {
  const user = await User.findById(req.userId);
  if (!user) throw unauthorized();
  res.json({ user: user.toJSON() });
});

module.exports = router;
