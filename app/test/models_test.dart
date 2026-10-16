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

    test('a note changes the source but never the chosen type', () {
      final a = AlarmModel.fromJson(json).copyWith(noteId: 'n1');
      expect(a.hasNote, isTrue);
      expect(a.type, 'Voice', reason: 'notes can back a voice interview too');
      final cleared = a.copyWith(clearNote: true);
      expect(cleared.noteId, isNull);
      expect(cleared.type, 'Voice');
    });

    test('only multiple choice can do without the microphone', () {
      final base = AlarmModel.fromJson(json);
      expect(base.copyWith(type: 'MCQ').usesVoice, isFalse);
      expect(base.copyWith(type: 'Voice').usesVoice, isTrue);
      expect(base.copyWith(type: 'Random').usesVoice, isTrue);
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

    test('a voice session carries its spoken questions and the pass mark', () {
      final s = ChallengeSession.fromJson({
        'id': 's2',
        'kind': 'voice',
        'topic': 'Databases',
        'difficulty': 'Medium',
        'total': 2,
        'passScore': 70,
        'questions': [
          {'id': 'v1', 'text': 'Explain indexes', 'solved': false, 'attempts': 0},
          {'id': 'v2', 'text': 'Explain transactions', 'solved': false, 'attempts': 0},
        ],
      });
      expect(s.isVoice, isTrue);
      expect(s.questions.map((q) => q.text), ['Explain indexes', 'Explain transactions']);
      expect(s.questions.first.options, isEmpty);
      expect(s.passScore, 70);
    });

    test('a graded answer says whether the question is passed and what remains', () {
      final g = VoiceGrade.fromJson(
        {'score': 82, 'feedback': 'Good', 'passed': true, 'passScore': 70, 'mock': false, 'remaining': 1},
      );
      expect(g.passed, isTrue);
      expect(g.remaining, 1);
    });

    test('notes report whether they can back a voice interview', () {
      final withInterview = NoteModel.fromJson(
        {'id': 'n1', 'title': 'Cells', 'sourceType': 'text', 'questionCount': 12, 'interviewCount': 6},
      );
      final quizOnly = NoteModel.fromJson(
        {'id': 'n2', 'title': 'Old notes', 'sourceType': 'file', 'questionCount': 12},
      );
      expect(withInterview.supportsVoice, isTrue);
      expect(quizOnly.supportsVoice, isFalse);
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
