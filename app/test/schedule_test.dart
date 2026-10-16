import 'package:aurora/models/models.dart';
import 'package:aurora/services/alarm_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

AlarmModel alarm({int hour = 6, int minute = 30, List<int> days = const [], bool enabled = true}) => AlarmModel(
      id: '65a1b2c3d4e5f60718293a4b',
      hour: hour,
      minute: minute,
      days: days,
      enabled: enabled,
    );

void main() {
  // Friday 16 October 2026, 10:00 local time.
  final friday = DateTime(2026, 10, 16, 10, 0);

  group('nextOccurrence', () {
    test('is null for a disabled alarm', () {
      expect(nextOccurrence(alarm(enabled: false), friday), isNull);
    });

    test('a one-shot alarm later today rings today', () {
      expect(nextOccurrence(alarm(hour: 18, minute: 0), friday), DateTime(2026, 10, 16, 18, 0));
    });

    test('a one-shot alarm whose time has passed rings tomorrow', () {
      expect(nextOccurrence(alarm(), friday), DateTime(2026, 10, 17, 6, 30));
    });

    test('an alarm at exactly the current minute is not the next one', () {
      final now = DateTime(2026, 10, 16, 6, 30);
      expect(nextOccurrence(alarm(), now), DateTime(2026, 10, 17, 6, 30));
    });

    test('Monday (1) from a Friday lands on the 19th', () {
      expect(nextOccurrence(alarm(days: [1]), friday), DateTime(2026, 10, 19, 6, 30));
    });

    test('Friday (5) after its time rings next Friday', () {
      expect(nextOccurrence(alarm(days: [5]), friday), DateTime(2026, 10, 23, 6, 30));
    });

    test('Friday (5) before its time rings today', () {
      expect(nextOccurrence(alarm(hour: 18, minute: 0, days: [5]), friday), DateTime(2026, 10, 16, 18, 0));
    });

    test('Sunday is day 0, not 7', () {
      expect(nextOccurrence(alarm(days: [0]), friday), DateTime(2026, 10, 18, 6, 30));
    });

    test('picks the soonest of several days', () {
      expect(nextOccurrence(alarm(days: [3, 6]), friday), DateTime(2026, 10, 17, 6, 30));
    });

    test('rolls over a month and year boundary', () {
      expect(
        nextOccurrence(alarm(hour: 6, minute: 0), DateTime(2026, 12, 31, 23, 0)),
        DateTime(2027, 1, 1, 6, 0),
      );
    });
  });

  group('alarmIntId', () {
    test('is stable, positive and fits the plugin id range', () {
      final id = alarmIntId('65a1b2c3d4e5f60718293a4b');
      expect(id, alarmIntId('65a1b2c3d4e5f60718293a4b'));
      expect(id, int.parse('8293a4b', radix: 16));
      expect(id, greaterThan(0));
      expect(id, lessThan(1 << 28));
    });

    test('differs for ids created one after another', () {
      expect(alarmIntId('65a1b2c3d4e5f60718293a4b'), isNot(alarmIntId('65a1b2c3d4e5f60718293a4c')));
    });

    test('never throws on an unexpected id', () {
      expect(alarmIntId('not-hex'), isNonNegative);
      expect(alarmIntId(''), isNonNegative);
    });
  });
}
