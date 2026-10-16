// Voice grades must reach this score to dismiss the alarm. The original Lovable
// prototype used a flat 70 for every difficulty.
const VOICE_PASS_SCORE = { Easy: 60, Medium: 70, Hard: 80 };

/**
 * Decides whether a finished challenge actually dismisses the alarm.
 *
 * kind:       'mcq' | 'voice'
 * difficulty: 'Easy' | 'Medium' | 'Hard'
 * accuracy:   0-100. For MCQ it is the share of questions answered correctly on
 *             the FIRST try (every question is eventually solved before we get
 *             here). For voice it is the average of each question's best score;
 *             a spoken question only counts as answered once it reaches
 *             VOICE_PASS_SCORE, so this average is always at or above the mark.
 *
 * TODO(human): this is the policy that decides how strict your alarm is.
 * Trade-offs worth deciding:
 *   - MCQ currently always dismisses once every question is solved, so first-try
 *     accuracy is only cosmetic. Requiring e.g. 50% on Hard makes the alarm bite,
 *     but a failed run restarts with fresh questions, which can mean a very
 *     frustrating morning.
 *   - Voice uses VOICE_PASS_SCORE above. Raise or lower the numbers to taste.
 */
function isDismissed({ kind, difficulty, accuracy }) {
  if (kind === 'voice') return accuracy >= VOICE_PASS_SCORE[difficulty];
  return true;
}

module.exports = { VOICE_PASS_SCORE, isDismissed };
