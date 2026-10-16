import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/alarm_scheduler.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';

enum BootStatus { booting, ready }

/// The single source of truth for the UI.
///
/// Offline-first: alarms and settings load from the on-device cache before any
/// network call, and are scheduled with the OS immediately, so an alarm rings
/// even if the phone has no signal. The server is reconciled in the background.
class AppState extends ChangeNotifier {
  AppState({required this.api, required this.store, required this.scheduler}) {
    api.onUnauthorized = _recoverSession;
  }

  final ApiClient api;
  final SessionStore store;
  final AlarmScheduler scheduler;

  BootStatus status = BootStatus.booting;
  UserModel? user;
  SettingsModel settings = SettingsModel.defaults();
  List<AlarmModel> alarms = [];
  List<NoteModel> notes = [];

  /// True while the last sync failed for lack of a connection.
  bool offline = false;

  /// One-shot message for a snackbar; the app shell consumes it.
  String? notice;

  // The ring and challenge flow.
  AlarmModel? ringingAlarm;
  bool previewMode = false;
  ChallengeSession? session;
  ChallengeResult? result;

  /// Set by the app shell so a ringing alarm can pull the UI to the ring screen.
  VoidCallback? onRing;

  StreamSubscription<String>? _ringSub;
  Future<void>? _refreshing;

  bool get hasRealRing => ringingAlarm != null && !previewMode;

  String? takeNotice() {
    final n = notice;
    notice = null;
    return n;
  }

  /// Queues a message for the snackbar.
  void showNotice(String message) {
    notice = message;
    notifyListeners();
  }

  // ---------------------------------------------------------------- startup

  Future<void> bootstrap() async {
    api.token = store.token;
    alarms = store.readAlarms();
    settings = store.readSettings();
    try {
      await scheduler.init();
    } catch (e) {
      debugPrint('[aurora] alarm scheduler unavailable: $e');
    }
    await _syncSchedule();
    _ringSub = scheduler.ringing.listen(_onRing);
    status = BootStatus.ready;
    notifyListeners();
    unawaited(refreshAll());
  }

  @override
  void dispose() {
    _ringSub?.cancel();
    super.dispose();
  }

  /// Pulls settings, alarms and notes from the server and re-arms the OS alarms.
  Future<void> refreshAll() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<void> _doRefresh() async {
    try {
      await _ensureSignedIn();
      final results = await Future.wait([api.getSettings(), api.listAlarms(), api.listNotes()]);
      settings = SettingsModel.fromJson(results[0]['settings'] as Map<String, dynamic>);
      alarms = _sorted(_parseList(results[1]['alarms'], AlarmModel.fromJson));
      notes = _parseList(results[2]['notes'], NoteModel.fromJson);
      offline = false;
      await store.writeAlarms(alarms);
      await store.writeSettings(settings);
      await _syncSchedule();
    } on ApiException catch (e) {
      if (e.isNetwork) {
        offline = true;
      } else {
        notice = e.message;
      }
    }
    notifyListeners();
  }

  List<T> _parseList<T>(Object? raw, T Function(Map<String, dynamic>) parse) =>
      raw is List ? raw.whereType<Map<String, dynamic>>().map(parse).toList() : <T>[];

  List<AlarmModel> _sorted(List<AlarmModel> list) =>
      list..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));

  Future<void> _syncSchedule() async {
    try {
      await scheduler.sync(alarms, settings);
    } catch (e) {
      debugPrint('[aurora] could not schedule alarms: $e');
    }
  }

  // ------------------------------------------------------------------- auth

  Future<void> _ensureSignedIn() async {
    if (api.token == null) {
      await _guestLogin();
    } else {
      user ??= UserModel.fromJson((await api.me())['user'] as Map<String, dynamic>);
    }
  }

  Future<void> _guestLogin() async => _adopt(await api.guestLogin(store.deviceId));

  Future<void> _adopt(Map<String, dynamic> json) async {
    api.token = json['token'] as String;
    await store.saveToken(api.token);
    user = UserModel.fromJson(json['user'] as Map<String, dynamic>);
  }

  /// A rejected token means it expired. Guests simply sign in again; a
  /// registered account cannot do that silently, so it falls back to a fresh
  /// guest and asks the user to sign in.
  Future<bool> _recoverSession() async {
    final wasRegistered = user != null && !user!.isGuest;
    try {
      await _guestLogin();
      if (wasRegistered) {
        notice = 'Your session expired. Please sign in again.';
        alarms = [];
        notes = [];
      }
      return true;
    } on ApiException {
      return false;
    }
  }

  Future<void> register(String email, String password, String? displayName) async {
    await _adopt(await api.register(email, password, displayName));
    await refreshAll();
  }

  Future<void> login(String email, String password) async {
    await _adopt(await api.login(email, password));
    alarms = [];
    notes = [];
    await refreshAll();
  }

  Future<void> signOut() async {
    await store.resetIdentity();
    api.token = null;
    user = null;
    alarms = [];
    notes = [];
    settings = SettingsModel.defaults();
    await scheduler.sync(const [], settings);
    notifyListeners();
    await refreshAll();
  }

  // ----------------------------------------------------------------- alarms

  Future<void> _persistAlarms() async {
    await store.writeAlarms(alarms);
    await _syncSchedule();
    notifyListeners();
  }

  /// Creates the alarm when its id is empty, otherwise updates it.
  Future<AlarmModel> saveAlarm(AlarmModel alarm) async {
    final json = alarm.id.isEmpty
        ? await api.createAlarm(alarm.toApiJson())
        : await api.updateAlarm(alarm.id, alarm.toApiJson());
    final saved = AlarmModel.fromJson(json['alarm'] as Map<String, dynamic>);
    alarms = _sorted([...alarms.where((a) => a.id != saved.id), saved]);
    await _persistAlarms();
    return saved;
  }

  /// Flips an alarm immediately and tells the server in the background. If the
  /// server refuses, the switch flips back and the user is told why.
  Future<void> setAlarmEnabled(AlarmModel alarm, bool enabled, {bool keepOnNetworkFailure = false}) async {
    final previous = alarms;
    alarms = [for (final a in alarms) a.id == alarm.id ? a.copyWith(enabled: enabled) : a];
    await _persistAlarms();
    try {
      await api.updateAlarm(alarm.id, {'enabled': enabled});
    } on ApiException catch (e) {
      if (e.isNetwork && keepOnNetworkFailure) return;
      alarms = previous;
      notice = e.message;
      await _persistAlarms();
    }
  }

  Future<void> deleteAlarm(String id) async {
    await api.deleteAlarm(id);
    alarms = alarms.where((a) => a.id != id).toList();
    await _persistAlarms();
  }

  // --------------------------------------------------------------- settings

  Future<void> updateSettings(SettingsModel next) async {
    final before = settings.toJson();
    final after = next.toJson();
    final patch = {
      for (final key in after.keys)
        if (jsonLike(before[key]) != jsonLike(after[key])) key: after[key],
    };
    settings = next;
    notifyListeners();
    await store.writeSettings(next);
    if (patch.isEmpty) return;
    try {
      await api.updateSettings(patch);
    } on ApiException catch (e) {
      if (e.isNetwork) {
        offline = true;
      } else {
        notice = e.message;
      }
    }
    await _syncSchedule(); // sound, volume and haptics are baked into scheduled alarms
    notifyListeners();
  }

  /// Lists compare by content; everything else by value.
  String jsonLike(Object? v) => v is List ? v.join('\u0001') : '$v';

  // ------------------------------------------------------------------ notes

  Future<NoteModel> uploadNote({
    String? title,
    String? text,
    String? fileName,
    String? mimeType,
    String? base64Data,
  }) async {
    final json = await api.uploadNote(
      title: title,
      text: text,
      fileName: fileName,
      mimeType: mimeType,
      base64Data: base64Data,
    );
    final note = NoteModel.fromJson(json['note'] as Map<String, dynamic>);
    notes = [note, ...notes];
    notifyListeners();
    return note;
  }

  Future<void> deleteNote(String id) async {
    await api.deleteNote(id);
    notes = notes.where((n) => n.id != id).toList();
    // The server unlinks the note from alarms; mirror that locally.
    alarms = [for (final a in alarms) a.noteId == id ? a.copyWith(clearNote: true) : a];
    await _persistAlarms();
  }

  // --------------------------------------------------- ringing and challenge

  void _onRing(String alarmId) {
    if (ringingAlarm?.id == alarmId && !previewMode) return; // already handling it
    final now = DateTime.now();
    ringingAlarm = alarms.where((a) => a.id == alarmId).firstOrNull ??
        AlarmModel(id: alarmId, hour: now.hour, minute: now.minute, label: kAppName);
    previewMode = false;
    session = null;
    result = null;
    notifyListeners();
    onRing?.call();
  }

  /// Walks through the ring and challenge screens without sounding an alarm.
  void startPreview(AlarmModel alarm) {
    ringingAlarm = alarm;
    previewMode = true;
    session = null;
    result = null;
    notifyListeners();
  }

  /// Opens the alarm's challenge. What it asks (type, topic or notes, difficulty,
  /// question count) comes from the alarm alone; nothing is swapped or downgraded.
  Future<ChallengeSession> startChallenge() async {
    final alarm = ringingAlarm!;
    final json = await api.startChallenge(alarmId: alarm.id);
    session = ChallengeSession.fromJson(json['session'] as Map<String, dynamic>);
    result = null;
    notifyListeners();
    return session!;
  }

  Future<AnswerResult> answer(String questionId, int selected) async =>
      AnswerResult.fromJson(await api.answer(session!.id, questionId, selected));

  Future<VoiceGrade> submitVoice(String questionId, int seconds, String base64Wav) async =>
      VoiceGrade.fromJson(await api.submitVoice(session!.id, questionId, seconds, base64Wav));

  Future<ChallengeResult> completeChallenge() async {
    final json = await api.complete(session!.id);
    result = ChallengeResult.fromJson(json['result'] as Map<String, dynamic>);
    notifyListeners();
    return result!;
  }

  /// Ends the ring: silences the alarm and schedules its next occurrence.
  ///
  /// There is deliberately no way to skip the challenge. A real alarm stops only
  /// after a passed result; a preview (started from the home screen, nothing is
  /// ringing) can be left at any time.
  Future<void> dismissAlarm() async {
    final alarm = ringingAlarm;
    if (alarm == null) return;
    final wasPreview = previewMode;
    if (!wasPreview && result?.success != true) return;

    ringingAlarm = null;
    session = null;
    result = null;
    previewMode = false;
    notifyListeners();
    if (wasPreview) return;

    await scheduler.stopRinging(alarm.id);
    if (alarm.isOneShot) {
      // One-shot alarms switch themselves off once they have rung.
      await setAlarmEnabled(alarm, false, keepOnNetworkFailure: true);
    } else {
      await _syncSchedule();
    }
  }
}
