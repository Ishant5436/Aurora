import '../models/models.dart';

/// The next moment [alarm] should ring, strictly after [now]; null if disabled.
///
/// Alarms with no repeat days ring at the next occurrence of their clock time.
/// Day numbers follow the backend: 0 = Sunday ... 6 = Saturday, whereas Dart's
/// DateTime.weekday is Monday = 1 ... Sunday = 7, hence `% 7`.
DateTime? nextOccurrence(AlarmModel alarm, DateTime now) {
  if (!alarm.enabled) return null;
  // DateTime(y, m, d + n) normalises overflow and stays correct across DST.
  for (var offset = 0; offset < 8; offset++) {
    final candidate = DateTime(now.year, now.month, now.day + offset, alarm.hour, alarm.minute);
    if (!candidate.isAfter(now)) continue;
    if (alarm.days.isEmpty || alarm.days.contains(candidate.weekday % 7)) return candidate;
  }
  return null;
}

/// Maps a Mongo ObjectId string to the positive 28-bit int the alarm plugin
/// needs. The last bytes of an ObjectId are a per-process counter, so ids that
/// one user creates never collide in practice.
int alarmIntId(String id) {
  final tail = id.length >= 7 ? id.substring(id.length - 7) : id;
  return int.tryParse(tail, radix: 16) ?? id.hashCode & 0x0fffffff;
}
