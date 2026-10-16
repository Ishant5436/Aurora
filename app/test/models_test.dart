import 'package:aurora/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AlarmModel', () {
    final json = {
      'id': 'a1',
      'hour': 7,
      'minute': 5,
      'label': 'Interview Prep',
      'days': [1, 3, 5],
      'enabled': false,
      'difficulty': 'Hard',
      'type': 'Voice',
      'questions': 1,
      'topic': 'System Design',
      'noteId': null,
    };

    test('parses the backend JSON', () {
      final a = AlarmModel.fromJson(json);
      expect(a.id, 'a1');
      expect(a.timeLabel, '07:05');
      expect(a.days, [1, 3, 5]);
      expect(a.enabled, isFalse);
      expect(a.type, 'Voice');
      expect(a.hasNote, isFalse);
      expect(a.isOneShot, isFalse);
    });

    test('survives a cache round trip and omits the id from API bodies', () {
      final a = AlarmModel.fromJson(json);
      final again = AlarmModel.fromJson(a.toJson());
      expect(again.toJson(), a.toJson());
      expect(a.toApiJson().containsKey('id'), isFalse);
    });

    test('tolerates missing and mistyped fields', () {
      final a = AlarmModel.fromJson({'id': 'x', 'hour': 'oops', 'days': 'nope'});
      expect(a.hour, 6);
      expect(a.days, isEmpty);
      expect(a.isOneShot, isTrue);
    });

    test('a note forces multiple choice and clearNote reverts it', () {
      final a = AlarmModel.fromJson(json).copyWith(noteId: 'n1');
      expect(a.hasNote, isTrue);
      expect(a.effectiveType, 'MCQ');
      final cleared = a.copyWith(clearNote: true);
      expect(cleared.noteId, isNull);
      expect(cleared.effectiveType, 'Voice');
    });
  });

  group('SettingsModel', () {
    test('falls back to defaults for missing keys', () {
      final s = SettingsModel.fromJson({'theme': 'light', 'volume': 40});
      expect(s.isDark, isFalse);
      expect(s.volume, 40);
      expect(s.sound, 'Cathedral Bells');
      expect(s.topics, ['JavaScript', 'Algorithms']);
    });

    test('toJson round trips', () {
      final s = SettingsModel.defaults().copyWith(haptics: false, topics: ['React']);
      expect(SettingsModel.fromJson(s.toJson()).toJson(), s.toJson());
    });
  });

  group('challenge payloads', () {
    test('an MCQ session carries questions but no answers', () {
      final s = ChallengeSession.fromJson({
        'id': 's1',
        'kind': 'mcq',
        'topic': 'Algorithms',
        'difficulty': 'Easy',
        'total': 1,
        'questions': [
          {'id': 'q1', 'text': 'Pick one', 'options': ['a', 'b', 'c', 'd'], 'solved': false, 'attempts': 0},
        ],
      });
      expect(s.isVoice, isFalse);
      expect(s.questions.single.options, hasLength(4));
    });

    test('a voice session carries the prompt and pass mark', () {
      final s = ChallengeSession.fromJson({
        'id': 's2',
        'kind': 'voice',
        'topic': 'Databases',
        'difficulty': 'Medium',
        'prompt': 'Explain indexes',
        'passScore': 70,
      });
      expect(s.isVoice, isTrue);
      expect(s.prompt, 'Explain indexes');
      expect(s.passScore, 70);
    });

    test('results format their duration', () {
      final r = ChallengeResult.fromJson(
        {'success': true, 'accuracy': 50, 'attempts': 3, 'seconds': 125, 'feedback': 'ok'},
      );
      expect(r.timeLabel, '2m 5s');
      expect(r.success, isTrue);
    });
  });
}
