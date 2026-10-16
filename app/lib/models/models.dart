import 'constants.dart';

int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;
String _str(Object? v, String fallback) => v is String ? v : fallback;
bool _bool(Object? v, bool fallback) => v is bool ? v : fallback;

class SettingsModel {
  const SettingsModel({
    required this.volume,
    required this.sound,
    required this.difficulty,
    required this.topics,
    required this.haptics,
    required this.animations,
    required this.notifications,
    required this.microphone,
    required this.theme,
  });

  factory SettingsModel.defaults() => const SettingsModel(
        volume: 70,
        sound: 'Cathedral Bells',
        difficulty: 'Medium',
        topics: ['JavaScript', 'Algorithms'],
        haptics: true,
        animations: true,
        notifications: true,
        microphone: false,
        theme: 'dark',
      );

  factory SettingsModel.fromJson(Map<String, dynamic> j) {
    final d = SettingsModel.defaults();
    return SettingsModel(
      volume: _int(j['volume'], d.volume),
      sound: _str(j['sound'], d.sound),
      difficulty: _str(j['difficulty'], d.difficulty),
      topics: j['topics'] is List ? (j['topics'] as List).whereType<String>().toList() : d.topics,
      haptics: _bool(j['haptics'], d.haptics),
      animations: _bool(j['animations'], d.animations),
      notifications: _bool(j['notifications'], d.notifications),
      microphone: _bool(j['microphone'], d.microphone),
      theme: _str(j['theme'], d.theme),
    );
  }

  final int volume;
  final String sound;
  final String difficulty;
  final List<String> topics;
  final bool haptics;
  final bool animations;
  final bool notifications;
  final bool microphone;
  final String theme;

  bool get isDark => theme == 'dark';

  Map<String, dynamic> toJson() => {
        'volume': volume,
        'sound': sound,
        'difficulty': difficulty,
        'topics': topics,
        'haptics': haptics,
        'animations': animations,
        'notifications': notifications,
        'microphone': microphone,
        'theme': theme,
      };

  SettingsModel copyWith({
    int? volume,
    String? sound,
    String? difficulty,
    List<String>? topics,
    bool? haptics,
    bool? animations,
    bool? notifications,
    bool? microphone,
    String? theme,
  }) {
    return SettingsModel(
      volume: volume ?? this.volume,
      sound: sound ?? this.sound,
      difficulty: difficulty ?? this.difficulty,
      topics: topics ?? this.topics,
      haptics: haptics ?? this.haptics,
      animations: animations ?? this.animations,
      notifications: notifications ?? this.notifications,
      microphone: microphone ?? this.microphone,
      theme: theme ?? this.theme,
    );
  }
}

class AlarmModel {
  const AlarmModel({
    required this.id,
    required this.hour,
    required this.minute,
    this.label = 'Alarm',
    this.days = const [],
    this.enabled = true,
    this.difficulty = 'Medium',
    this.type = 'MCQ',
    this.questions = 3,
    this.topic = 'JavaScript',
    this.noteId,
  });

  factory AlarmModel.fromJson(Map<String, dynamic> j) {
    return AlarmModel(
      id: _str(j['id'], ''),
      hour: _int(j['hour'], 6),
      minute: _int(j['minute'], 0),
      label: _str(j['label'], 'Alarm'),
      days: j['days'] is List ? (j['days'] as List).whereType<num>().map((n) => n.toInt()).toList() : const [],
      enabled: _bool(j['enabled'], true),
      difficulty: _str(j['difficulty'], 'Medium'),
      type: _str(j['type'], 'MCQ'),
      questions: _int(j['questions'], 3),
      topic: _str(j['topic'], 'JavaScript'),
      noteId: j['noteId'] is String ? j['noteId'] as String : null,
    );
  }

  final String id;
  final int hour;
  final int minute;
  final String label;

  /// 0 = Sunday ... 6 = Saturday. Empty means the alarm rings once.
  final List<int> days;
  final bool enabled;
  final String difficulty;
  final String type;
  final int questions;
  final String topic;
  final String? noteId;

  String get timeLabel => '${pad2(hour)}:${pad2(minute)}';
  bool get hasNote => noteId != null;
  bool get isOneShot => days.isEmpty;

  /// Quizzes built from notes are always multiple choice.
  String get effectiveType => hasNote ? 'MCQ' : type;

  /// Body for create and patch requests (no id).
  Map<String, dynamic> toApiJson() => {
        'hour': hour,
        'minute': minute,
        'label': label,
        'days': days,
        'enabled': enabled,
        'difficulty': difficulty,
        'type': type,
        'questions': questions,
        'topic': topic,
        'noteId': noteId,
      };

  /// Full form used by the offline cache.
  Map<String, dynamic> toJson() => {'id': id, ...toApiJson()};

  AlarmModel copyWith({
    String? id,
    int? hour,
    int? minute,
    String? label,
    List<int>? days,
    bool? enabled,
    String? difficulty,
    String? type,
    int? questions,
    String? topic,
    String? noteId,
    bool clearNote = false,
  }) {
    return AlarmModel(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      label: label ?? this.label,
      days: days ?? this.days,
      enabled: enabled ?? this.enabled,
      difficulty: difficulty ?? this.difficulty,
      type: type ?? this.type,
      questions: questions ?? this.questions,
      topic: topic ?? this.topic,
      noteId: clearNote ? null : (noteId ?? this.noteId),
    );
  }
}

class NoteModel {
  const NoteModel({
    required this.id,
    required this.title,
    required this.sourceType,
    required this.questionCount,
    this.createdAt,
  });

  factory NoteModel.fromJson(Map<String, dynamic> j) => NoteModel(
        id: _str(j['id'], ''),
        title: _str(j['title'], 'Untitled notes'),
        sourceType: _str(j['sourceType'], 'text'),
        questionCount: _int(j['questionCount'], 0),
        createdAt: j['createdAt'] is String ? DateTime.tryParse(j['createdAt'] as String) : null,
      );

  final String id;
  final String title;
  final String sourceType;
  final int questionCount;
  final DateTime? createdAt;
}

class UserModel {
  const UserModel({
    required this.id,
    required this.displayName,
    required this.isGuest,
    required this.settings,
    this.email,
  });

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
        id: _str(j['id'], ''),
        displayName: _str(j['displayName'], 'Guest Scholar'),
        email: j['email'] is String ? j['email'] as String : null,
        isGuest: _bool(j['isGuest'], true),
        settings: j['settings'] is Map<String, dynamic>
            ? SettingsModel.fromJson(j['settings'] as Map<String, dynamic>)
            : SettingsModel.defaults(),
      );

  final String id;
  final String displayName;
  final String? email;
  final bool isGuest;
  final SettingsModel settings;
}

class QuizQuestion {
  const QuizQuestion({required this.id, required this.text, required this.options});

  factory QuizQuestion.fromJson(Map<String, dynamic> j) => QuizQuestion(
        id: _str(j['id'], ''),
        text: _str(j['text'], ''),
        options: j['options'] is List ? (j['options'] as List).whereType<String>().toList() : const [],
      );

  final String id;
  final String text;
  final List<String> options;
}

/// A challenge the server has opened for the user. Answers never appear here.
class ChallengeSession {
  const ChallengeSession({
    required this.id,
    required this.kind,
    required this.topic,
    required this.difficulty,
    this.questions = const [],
    this.prompt,
    this.passScore,
  });

  factory ChallengeSession.fromJson(Map<String, dynamic> j) => ChallengeSession(
        id: _str(j['id'], ''),
        kind: _str(j['kind'], 'mcq'),
        topic: _str(j['topic'], ''),
        difficulty: _str(j['difficulty'], 'Medium'),
        questions: j['questions'] is List
            ? (j['questions'] as List).whereType<Map<String, dynamic>>().map(QuizQuestion.fromJson).toList()
            : const [],
        prompt: j['prompt'] is String ? j['prompt'] as String : null,
        passScore: j['passScore'] is num ? (j['passScore'] as num).toInt() : null,
      );

  final String id;
  final String kind;
  final String topic;
  final String difficulty;
  final List<QuizQuestion> questions;
  final String? prompt;
  final int? passScore;

  bool get isVoice => kind == 'voice';
}

class AnswerResult {
  const AnswerResult({
    required this.correct,
    required this.solved,
    required this.attempts,
    required this.remaining,
    this.explanation,
  });

  factory AnswerResult.fromJson(Map<String, dynamic> j) => AnswerResult(
        correct: _bool(j['correct'], false),
        solved: _bool(j['solved'], false),
        attempts: _int(j['attempts'], 1),
        remaining: _int(j['remaining'], 0),
        explanation: j['explanation'] is String ? j['explanation'] as String : null,
      );

  final bool correct;
  final bool solved;
  final int attempts;
  final int remaining;
  final String? explanation;
}

class VoiceGrade {
  const VoiceGrade({
    required this.score,
    required this.feedback,
    required this.passed,
    required this.passScore,
    required this.mock,
  });

  factory VoiceGrade.fromJson(Map<String, dynamic> j) => VoiceGrade(
        score: _int(j['score'], 0),
        feedback: _str(j['feedback'], ''),
        passed: _bool(j['passed'], false),
        passScore: _int(j['passScore'], 70),
        mock: _bool(j['mock'], false),
      );

  final int score;
  final String feedback;
  final bool passed;
  final int passScore;
  final bool mock;
}

class ChallengeResult {
  const ChallengeResult({
    required this.success,
    required this.accuracy,
    required this.attempts,
    required this.seconds,
    required this.feedback,
  });

  factory ChallengeResult.fromJson(Map<String, dynamic> j) => ChallengeResult(
        success: _bool(j['success'], false),
        accuracy: _int(j['accuracy'], 0),
        attempts: _int(j['attempts'], 0),
        seconds: _int(j['seconds'], 0),
        feedback: _str(j['feedback'], ''),
      );

  final bool success;
  final int accuracy;
  final int attempts;
  final int seconds;
  final String feedback;

  String get timeLabel => '${seconds ~/ 60}m ${seconds % 60}s';
}
