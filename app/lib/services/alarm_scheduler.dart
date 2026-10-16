import 'dart:async';
import 'dart:io' show Platform;

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../models/constants.dart';
import '../models/models.dart';
import 'alarm_schedule.dart';

/// Schedules the OS-level alarms and reports when one starts ringing. The app
/// talks to this interface so the plugin stays contained in one file.
abstract class AlarmScheduler {
  /// Server alarm ids as they start ringing. Replays an alarm that is already
  /// ringing, which is how an alarm that launched the app is noticed.
  Stream<String> get ringing;

  Future<void> init();

  /// Makes the OS schedule match [alarms]: the next occurrence of every
  /// enabled alarm, and nothing else.
  Future<void> sync(List<AlarmModel> alarms, SettingsModel settings);

  /// Silences an alarm that is currently ringing.
  Future<void> stopRinging(String alarmId);
}

/// Real alarms through the `alarm` plugin (foreground service on Android,
/// background audio plus notification on iOS).
class DeviceAlarmScheduler implements AlarmScheduler {
  // The plugin crashes if set() and stop() overlap, so every job is serialised.
  Future<void> _queue = Future<void>.value();

  Future<void> _enqueue(Future<void> Function() job) {
    final next = _queue.then((_) => job()).catchError((Object e, StackTrace s) {
      debugPrint('[alarm] scheduler job failed: $e');
    });
    _queue = next;
    return next;
  }

  @override
  Stream<String> get ringing =>
      Alarm.ringing.expand((set) => set.alarms.map((a) => a.payload).whereType<String>());

  @override
  Future<void> init() async {
    await Alarm.init();
    if (Platform.isIOS) {
      await Alarm.setWarningNotificationOnKill(
        '$kAppName was closed',
        'Reopen $kAppName so your alarm can ring.',
      );
    }
  }

  @override
  Future<void> sync(List<AlarmModel> alarms, SettingsModel settings) => _enqueue(() async {
        final now = DateTime.now();
        final wanted = <int>{};

        for (final alarm in alarms) {
          final next = nextOccurrence(alarm, now);
          if (next == null) continue;
          final id = alarmIntId(alarm.id);
          wanted.add(id);
          // Re-scheduling an alarm that is ringing right now would cut it off.
          if (await Alarm.isRinging(id)) continue;
          await Alarm.set(alarmSettings: _settingsFor(alarm, id, next, settings));
        }

        // Anything scheduled that we no longer want (deleted or disabled).
        for (final scheduled in await Alarm.getAlarms()) {
          if (wanted.contains(scheduled.id)) continue;
          if (await Alarm.isRinging(scheduled.id)) continue;
          await Alarm.stop(scheduled.id);
        }
      });

  @override
  Future<void> stopRinging(String alarmId) => _enqueue(() async {
        await Alarm.stop(alarmIntId(alarmId));
      });

  AlarmSettings _settingsFor(AlarmModel alarm, int id, DateTime when, SettingsModel s) {
    return AlarmSettings(
      id: id,
      dateTime: when,
      assetAudioPath: kSoundAssets[s.sound] ?? kSoundAssets.values.first,
      loopAudio: true,
      vibrate: s.haptics,
      warningNotificationOnKill: Platform.isIOS && s.notifications,
      androidFullScreenIntent: true,
      // Killing the app must not silence the alarm: the quiz is the only way out.
      androidStopAlarmOnTermination: false,
      payload: alarm.id,
      volumeSettings: VolumeSettings.fade(
        volume: (s.volume / 100).clamp(0.0, 1.0),
        fadeDuration: const Duration(seconds: 6),
        volumeEnforced: true,
      ),
      notificationSettings: NotificationSettings(
        title: alarm.label.isEmpty ? kAppName : alarm.label,
        body: 'Open $kAppName and answer the challenge to silence it.',
        // No stop button and no swipe-to-dismiss: only the quiz silences it.
        androidStopAlarmOnDismiss: false,
      ),
    );
  }
}

/// Used on unsupported platforms and in tests. [emitRing] simulates an alarm
/// going off so the ring flow can be exercised without the OS.
class NoopAlarmScheduler implements AlarmScheduler {
  final _controller = StreamController<String>.broadcast();

  /// Ids passed to [stopRinging], so tests can assert an alarm was silenced.
  final stopped = <String>[];

  void emitRing(String alarmId) => _controller.add(alarmId);

  @override
  Stream<String> get ringing => _controller.stream;

  @override
  Future<void> init() async {}

  @override
  Future<void> sync(List<AlarmModel> alarms, SettingsModel settings) async {}

  @override
  Future<void> stopRinging(String alarmId) async => stopped.add(alarmId);
}
