# Aurora

An alarm clock that makes you think. When the alarm rings, the only way to
silence it is to answer questions, either multiple choice or by explaining a
concept out loud to an AI examiner. You can also upload your own notes (pasted
text, PDF, `.txt` or `.md`) and Aurora turns them into the quiz that wakes you.

The look (a Renaissance "Lumen Hora" theme with dark and light modes) and the
screen flow come from a Lovable web prototype. This repo is the real thing:

| Part | Stack |
| --- | --- |
| `app/` | Flutter (iOS and Android) |
| `backend/` | Node.js, Express 5, Mongoose, MongoDB Atlas |
| AI | Google Gemini (questions, voice grading, notes to quiz) |

## What it does

- **Real alarms** scheduled with the OS (the `alarm` plugin), so they ring when
  the app is in the background or closed. On Android that includes a full-screen
  pop-up over the lock screen; on iOS it is sound plus a notification, and the
  app must not have been force-quit. The notification cannot be swiped away to
  skip the quiz.
- **Multiple choice trials**, 1 to 4 questions. Questions come from a MongoDB
  question bank that Gemini keeps topped up, with a built-in seed bank as the
  offline fallback.
- **Voice interview**: a real interview of 1 to 4 spoken questions (the alarm's
  question count). Each answer is recorded (up to 90 seconds) and graded by
  Gemini against a pass mark that depends on difficulty, and a question must
  pass before the next one is asked.
- **Notes to quiz and interview**: upload notes once. Gemini writes a 12 question
  quiz plus 6 interview questions (with the key points a good answer covers).
  Only those are stored, never the upload itself.
- **Exactly what you selected**: an alarm has a type (multiple choice, voice
  interview or random), a source (a topic, or one of your notes), a difficulty and
  a question count. The quiz uses precisely those and nothing else. See
  "Your selection is the only source" below.
- **No way to skip**: there is no emergency dismiss. A real alarm stops only when
  its challenge is passed. (A preview started from the home screen can be exited.)
- **Offline first**: alarms and settings are cached on the device and scheduled
  with the OS before any network call, so alarms ring without signal. Answering
  the quiz still needs the server, see "Because there is no skip" below.
- Guest accounts by default, optional email and password to keep data across devices.

## Run it

### 1. Backend

```bash
cd backend
npm install
cp .env.example .env      # then edit .env
npm run dev               # http://localhost:4000, GET /health to check
npm test                  # needs a local `mongod` on PATH; nothing is downloaded
```

In `.env` you need two values:

- `MONGODB_URI`: for **MongoDB Atlas**, create a free cluster, add a database
  user, add your IP under *Network Access*, then *Connect > Drivers* and copy
  the connection string (put your database name before the `?`). For a local
  MongoDB use `mongodb://127.0.0.1:27017/aurora`.
- `JWT_SECRET`: at least 32 random characters, e.g. `openssl rand -hex 32`.

`GEMINI_API_KEY` is optional but unlocks the AI features (get one in Google AI
Studio). Without it the server uses the built-in question bank, voice grading
falls back to a dev-only duration heuristic (disabled in production), and
uploading notes returns 503. Model ids are set in `.env`
(`GEMINI_MODEL`, `GEMINI_MULTIMODAL_MODEL`) so they can change without code edits.
Busy models are handled for you: transient errors are retried with a short
backoff and a model that stays overloaded falls back to the lighter one, so a
Gemini spike does not stop an alarm from getting its quiz.

### 2. App

```bash
cd app
flutter pub get
flutter run                                   # iOS simulator: talks to localhost:4000
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000   # a real phone
flutter test
```

The Android emulator reaches your computer at `10.0.2.2`, which is the default
on Android. Release builds must use an `https` API URL.

## How alarms work

The app asks the server for your alarms, caches them, and schedules the **next
occurrence** of each enabled alarm with the OS. After every ring, launch,
resume or change it re-schedules, which is how repeating alarms work (the
plugin has no native repeat). When one rings, the app opens the ring screen and
the alarm keeps sounding until the quiz is solved.

Be aware of the platform limits:

- **iOS** alarms depend on the app not being force-quit. If it is, only a
  fallback notification fires. Opening the app at least once a day helps.
- **Android** vendors with aggressive battery savers may delay alarms; see
  dontkillmyapp.com. Android 13+ asks for notification permission at launch.
- The Android build has **not been compiled or run** in this repo's development
  environment (no Android SDK there). The iOS build and simulator run have.

## API

All routes are under `/api`, JSON in and out, `Authorization: Bearer <jwt>`.

| Route | Purpose |
| --- | --- |
| `POST /auth/guest` `{deviceId}` | Create or resume a guest account |
| `POST /auth/register`, `/auth/login`, `GET /auth/me` | Email accounts; register upgrades the guest in place |
| `GET, PUT /settings` | Sound, difficulty, topics, theme and more |
| `GET, POST /alarms`, `GET, PATCH, DELETE /alarms/:id` | Alarm CRUD, scoped to the owner |
| `GET, POST /notes`, `DELETE /notes/:id` | Upload notes (text or base64 file) and manage them; a note an alarm uses cannot be deleted (409) |
| `POST /challenges/start` | Open a quiz or interview from an alarm (type, source, difficulty and count all come from the alarm) |
| `POST /challenges/:id/answer` | Check one answer; reveals the explanation only when correct |
| `POST /challenges/:id/voice` | Grade one spoken answer, for the question named by `questionId` |
| `POST /challenges/:id/complete` | Finish with a result; refused until every question is answered |

Correct answers (and the key points a spoken answer is graded against) never
leave the server, so the app cannot be cheated by reading the network traffic.
Audio is graded and discarded; only the score and feedback are stored.

## Your selection is the only source

The server never swaps what an alarm asked for:

- A **topic** alarm uses only that topic at that difficulty. If the bank is short
  and the AI cannot fill the gap, the quiz is shorter, never about something else.
  Spoken questions fall back to built-in prompts for the same topic only.
- A **notes** alarm uses only those notes, for both multiple choice and the voice
  interview. Notes that no longer exist, or hold nothing to ask, are an error that
  tells you to edit the alarm; they never turn into a topic quiz. Notes an alarm
  uses cannot be deleted.
- A **voice** alarm is never turned into multiple choice, even when the
  microphone is not allowed or the AI is down. Those are errors you can fix, not a
  quiet change of quiz. **Random** alarms choose between the two types, and only
  between types that can actually run for that source.

## Because there is no skip

An alarm that cannot be silenced is only as good as the things it depends on:

- Multiple choice needs the server to be reachable, and a voice interview also
  needs the internet and microphone access (the app asks when you save the
  alarm, and checks again in Settings). If the phone is offline when an alarm
  rings, reconnect and tap try again.
- If the AI examiner is briefly unavailable, retry; there is no fail-open path.
- Force-closing the app on Android does not silence a ringing alarm; stopping it
  from the system settings does.

## Make it stricter or gentler

`backend/src/policy/dismissal.js` decides what actually dismisses an alarm:
the voice pass mark per difficulty, and whether first-try accuracy matters for
multiple choice. It ships with sensible defaults and a note on the trade-offs.

## Layout

```
backend/            Express API, Mongoose models, Gemini wrapper, tests
  src/policy/       The dismissal rules you may want to tune
app/                Flutter client (lib/, test/, ios/, android/)
tools/              generate_sounds.js: synthesises the bundled alarm tones
```

Drop a `florence.jpg` into `app/assets/images/` to show the original cathedral
artwork on the home and splash screens; a drawn silhouette is used otherwise.
The three alarm tones in `app/assets/audio/` are synthesised placeholders
(`node tools/generate_sounds.js`); replace them with real recordings freely.

## Verification status

- Backend: 42 tests against a real temporary `mongod`, covering auth, alarm
  ownership, answer secrecy, multi-question voice interviews, strict sources (no
  substitution of topic, difficulty, type or notes), notes to quiz and interview,
  and Gemini retry and fallback. The tests never read your `.env`.
- Gemini and Atlas: also run live against a real Atlas cluster and the real
  Gemini API. AI-generated questions, notes to quiz and interview questions
  (pasted text and a PDF), and voice interviews from both a topic and notes with
  real spoken audio all worked, as did the strict topic and difficulty quiz.
  `gemini-3.8-flash` returned intermittent "high demand" errors in an earlier run,
  which is why the default model is `gemini-3.5-flash-lite` and why retry and
  fallback exist.
- App: static analysis is clean, with 37 tests: scheduling maths, parsing, the
  full ring, quiz, dismiss flow against a fake server, that a ringing alarm has no
  way out, that previews can be exited, that a voice alarm opens a voice
  interview with nothing downgraded, offline start from the cache, and a layout
  check of every screen at three phone widths (320 to 412) and two text sizes.
  The layout test scales text to approximate the real fonts, because the test
  environment draws every glyph one em wide.
- iOS: built for the simulator, launched on an iPhone 17 Pro, and confirmed to
  sign in and sync against a real local backend. The UI was not driven by hand,
  and alarm ringing, the microphone and PDF picking have not been exercised on a
  device.
