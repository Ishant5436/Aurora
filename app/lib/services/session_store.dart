import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Everything that must survive an app restart: the guest identity, the login
/// token, and a cache of alarms and settings so alarms still ring (and the
/// home screen still renders) with no network.
class SessionStore {
  SessionStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kDeviceId = 'deviceId';
  static const _kToken = 'token';
  static const _kAlarms = 'cache.alarms';
  static const _kSettings = 'cache.settings';

  /// A random id that identifies this install to the backend as a guest.
  String get deviceId {
    final existing = _prefs.getString(_kDeviceId);
    if (existing != null) return existing;
    final rng = Random.secure();
    final id = List.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    _prefs.setString(_kDeviceId, id);
    return id;
  }

  String? get token => _prefs.getString(_kToken);

  Future<void> saveToken(String? token) async {
    if (token == null) {
      await _prefs.remove(_kToken);
    } else {
      await _prefs.setString(_kToken, token);
    }
  }

  List<AlarmModel> readAlarms() {
    final raw = _prefs.getString(_kAlarms);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(AlarmModel.fromJson)
          .toList();
    } catch (_) {
      return []; // a corrupt cache must never stop the app from starting
    }
  }

  Future<void> writeAlarms(List<AlarmModel> alarms) =>
      _prefs.setString(_kAlarms, jsonEncode(alarms.map((a) => a.toJson()).toList()));

  SettingsModel readSettings() {
    final raw = _prefs.getString(_kSettings);
    if (raw == null) return SettingsModel.defaults();
    try {
      return SettingsModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return SettingsModel.defaults();
    }
  }

  Future<void> writeSettings(SettingsModel settings) =>
      _prefs.setString(_kSettings, jsonEncode(settings.toJson()));

  /// Signing out starts over as a brand new guest.
  Future<void> resetIdentity() async {
    await _prefs.remove(_kToken);
    await _prefs.remove(_kDeviceId);
    await _prefs.remove(_kAlarms);
    await _prefs.remove(_kSettings);
  }
}
