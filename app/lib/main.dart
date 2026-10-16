import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'services/alarm_scheduler.dart';
import 'services/api_client.dart';
import 'services/session_store.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = SessionStore(await SharedPreferences.getInstance());
  final app = AppState(
    api: ApiClient(),
    store: store,
    // The OS alarm plugin only exists on iOS and Android.
    scheduler: kIsWeb ? NoopAlarmScheduler() : DeviceAlarmScheduler(),
  );
  // Loads the cache and arms the OS alarms before the first frame, so a
  // ringing alarm is known by the time the UI appears.
  await app.bootstrap();

  runApp(ChangeNotifierProvider.value(value: app, child: const AuroraApp()));
}
