import 'dart:convert';

import 'package:aurora/app.dart';
import 'package:aurora/services/alarm_scheduler.dart';
import 'package:aurora/services/api_client.dart';
import 'package:aurora/services/session_store.dart';
import 'package:aurora/state/app_state.dart';
import 'package:aurora/theme/app_theme.dart';
import 'package:aurora/widgets/renaissance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alarmId = '65a1b2c3d4e5f60718293a4b';
const _alarm = {
  'id': _alarmId,
  'hour': 6,
  'minute': 30,
  'label': 'Morning Study',
  'days': [1, 2, 3, 4, 5],
  'enabled': true,
  'difficulty': 'Medium',
  'type': 'MCQ',
  'questions': 1,
  'topic': 'JavaScript',
  'noteId': null,
};
const _settings = {
  'volume': 70,
  'sound': 'Cathedral Bells',
  'difficulty': 'Medium',
  'topics': ['JavaScript'],
  'haptics': true,
  'animations': true,
  'notifications': true,
  'microphone': false,
  'theme': 'dark',
};

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// A scripted stand-in for the Aurora backend.
class _FakeServer {
  final calls = <String>[];
  bool offline = false;
  bool failPatch = false;
  int? lastSelected;

  Future<http.Response> handle(http.Request req) async {
    if (offline) throw http.ClientException('no network');
    final key = '${req.method} ${req.url.path}';
    calls.add(key);
    switch (key) {
      case 'POST /api/auth/guest':
        return _json({
          'token': 'jwt',
          'user': {'id': 'u1', 'displayName': 'Guest Scholar', 'isGuest': true, 'settings': _settings},
        });
      case 'GET /api/settings':
        return _json({'settings': _settings});
      case 'GET /api/alarms':
        return _json({'alarms': [_alarm]});
      case 'GET /api/notes':
        return _json({'notes': []});
      case 'PATCH /api/alarms/$_alarmId':
        if (failPatch) return _json({'error': {'code': 'boom', 'message': 'The server refused.'}}, 500);
        return _json({'alarm': {..._alarm, ...(jsonDecode(req.body) as Map<String, dynamic>)}});
      case 'POST /api/challenges/start':
        return _json({
          'session': {
            'id': 's1',
            'kind': 'mcq',
            'topic': 'JavaScript',
            'difficulty': 'Medium',
            'status': 'active',
            'total': 1,
            'questions': [
              {
                'id': 'q1',
                'text': 'Which data structure offers O(1) average lookup by key?',
                'options': ['Linked list', 'Hash map', 'Binary heap', 'Stack'],
                'solved': false,
                'attempts': 0,
              },
            ],
          },
        }, 201);
      case 'POST /api/challenges/s1/answer':
        final selected = (jsonDecode(req.body) as Map<String, dynamic>)['selected'] as int;
        lastSelected = selected;
        final correct = selected == 1;
        return _json({
          'correct': correct,
          'solved': correct,
          'attempts': 1,
          'remaining': correct ? 0 : 1,
          if (correct) 'explanation': 'Hash maps compute a bucket from the key.',
        });
      case 'POST /api/challenges/s1/complete':
        return _json({
          'result': {'success': true, 'accuracy': 0, 'attempts': 2, 'seconds': 42, 'feedback': 'Well fought.'},
        });
    }
    return _json({'error': {'code': 'not_found', 'message': 'unexpected request: $key'}}, 404);
  }
}

class _Harness {
  _Harness(this.server, this.scheduler, this.app);

  final _FakeServer server;
  final NoopAlarmScheduler scheduler;
  final AppState app;
}

Future<_Harness> _boot(WidgetTester tester, {Map<String, Object> prefs = const {}, bool offline = false}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(prefs);
  final server = _FakeServer()..offline = offline;
  final scheduler = NoopAlarmScheduler();
  final app = AppState(
    api: ApiClient(client: MockClient(server.handle), baseUrl: 'http://test'),
    store: SessionStore(await SharedPreferences.getInstance()),
    scheduler: scheduler,
  );
  await tester.runAsync(app.bootstrap);
  // bootstrap() starts the first server sync in the background; wait for it
  // (refreshAll joins the in-flight one) so the cache/server state is settled.
  await tester.runAsync(app.refreshAll);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: app, child: const AuroraApp()));
  await tester.pump(const Duration(milliseconds: 3300)); // the splash timer
  await tester.pump(const Duration(milliseconds: 500)); // route fade
  return _Harness(server, scheduler, app);
}

Future<void> _advance(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(() => Typo.useGoogleFonts = false);

  testWidgets('a ringing alarm leads through a wrong then right answer to dismissal', (tester) async {
    final h = await _boot(tester);
    expect(find.text('Upcoming Alarms'), findsOneWidget);
    expect(find.textContaining('Morning Study'), findsOneWidget);

    h.scheduler.emitRing(_alarmId);
    await _advance(tester);
    expect(find.text('The Hour Has Come'), findsOneWidget);

    await tester.tap(find.text('BEGIN CHALLENGE'));
    await _advance(tester);
    expect(find.text('A Trial of Knowledge'), findsOneWidget);
    expect(find.text('QUESTION 1 OF 1'), findsOneWidget);

    await tester.tap(find.text('Linked list'));
    await tester.pump();
    await tester.tap(find.text('SUBMIT ANSWER'));
    await _advance(tester);
    expect(h.server.lastSelected, 0);
    expect(find.text('Not quite. Try once more.'), findsOneWidget);
    expect(find.textContaining('Hash maps compute'), findsNothing, reason: 'a wrong guess reveals nothing');

    await tester.tap(find.text('Hash map'));
    await tester.pump();
    await tester.tap(find.text('SUBMIT ANSWER'));
    await _advance(tester);
    expect(find.textContaining('Correct'), findsOneWidget);
    expect(find.textContaining('Hash maps compute'), findsOneWidget);

    await tester.tap(find.text('SEE RESULTS'));
    await _advance(tester);
    expect(find.text('Victory'), findsOneWidget);

    await tester.tap(find.text('DISMISS ALARM'));
    await _advance(tester);
    expect(find.text('Upcoming Alarms'), findsOneWidget);
    expect(h.app.ringingAlarm, isNull);
    expect(h.scheduler.stopped, [_alarmId], reason: 'the OS alarm must be silenced');
  });

  testWidgets('emergency dismiss silences the alarm after confirmation', (tester) async {
    final h = await _boot(tester);
    h.scheduler.emitRing(_alarmId);
    await _advance(tester);

    await tester.tap(find.text('EMERGENCY DISMISS'));
    await _advance(tester);
    await tester.tap(find.text('Dismiss'));
    await _advance(tester);

    expect(find.text('Upcoming Alarms'), findsOneWidget);
    expect(h.scheduler.stopped, [_alarmId]);
  });

  testWidgets('a rejected toggle flips back and tells the user', (tester) async {
    final h = await _boot(tester);
    h.server.failPatch = true;

    await tester.tap(find.byType(AuroraSwitch).first);
    await _advance(tester);

    expect(h.app.alarms.single.enabled, isTrue, reason: 'optimistic change rolled back');
    expect(find.text('The server refused.'), findsOneWidget);
  });

  testWidgets('starts from the on-device cache when the network is down', (tester) async {
    final h = await _boot(
      tester,
      prefs: {
        'cache.alarms': jsonEncode([_alarm]),
      },
      offline: true,
    );
    await _advance(tester);

    expect(find.textContaining('Morning Study'), findsOneWidget, reason: 'cached alarms still show');
    expect(find.textContaining('Offline'), findsOneWidget);
    expect(h.app.offline, isTrue);
  });
}
