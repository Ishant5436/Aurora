import 'package:aurora/models/models.dart';
import 'package:aurora/screens/alarm_form_screen.dart';
import 'package:aurora/screens/home_screen.dart';
import 'package:aurora/screens/mcq_screen.dart';
import 'package:aurora/screens/notes_screen.dart';
import 'package:aurora/screens/results_screen.dart';
import 'package:aurora/screens/ring_screen.dart';
import 'package:aurora/screens/settings_screen.dart';
import 'package:aurora/screens/splash_screen.dart';
import 'package:aurora/screens/voice_screen.dart';
import 'package:aurora/services/alarm_scheduler.dart';
import 'package:aurora/services/api_client.dart';
import 'package:aurora/services/session_store.dart';
import 'package:aurora/state/app_state.dart';
import 'package:aurora/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _longQuestion = 'Which of the following best describes the difference between a process and a '
    'thread in a modern operating system, and why does it matter for scheduling?';
const _longOption = 'A deliberately long answer option that wraps onto several lines on a narrow phone';

Future<AppState> _app() async {
  SharedPreferences.setMockInitialValues({});
  final app = AppState(
    api: ApiClient(client: MockClient((_) async => http.Response('{}', 200)), baseUrl: 'http://test'),
    store: SessionStore(await SharedPreferences.getInstance()),
    scheduler: NoopAlarmScheduler(),
  );
  app.alarms = const [
    AlarmModel(
      id: 'a1',
      hour: 7,
      minute: 5,
      label: 'A very long alarm label that hits forty',
      days: [0, 1, 2, 3, 4, 5, 6],
      type: 'Random',
      questions: 4,
    ),
    AlarmModel(id: 'a2', hour: 22, minute: 45, label: 'Notes', noteId: 'n1', difficulty: 'Hard'),
  ];
  app.notes = [
    NoteModel(
      id: 'n1',
      title: 'Introduction to Operating Systems: processes, threads and scheduling',
      sourceType: 'file',
      questionCount: 12,
      createdAt: DateTime(2026, 10, 16),
    ),
  ];
  app.user = UserModel(id: 'u1', displayName: 'Guest Scholar', isGuest: true, settings: SettingsModel.defaults());
  return app;
}

Widget _wrap(AppState app, Widget screen) => ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: screen),
    );

void main() {
  setUpAll(() => Typo.useGoogleFonts = false);

  // Tests render every glyph in the "Ahem" font, one full em wide, which is
  // roughly 1.6x wider than Cinzel or DM Sans. Scaling by 0.62 approximates the
  // real widths; 0.8 is the same with the user's text size turned up ~30%.
  const sizes = [Size(320, 568), Size(360, 740), Size(412, 915)];
  for (final size in sizes) {
    for (final textScale in [0.62, 0.8]) {
      testWidgets('every screen fits ${size.width.toInt()}x${size.height.toInt()} at text x$textScale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);

        final app = await _app();
        app.startPreview(app.alarms.first);
        app.session = const ChallengeSession(
          id: 's1',
          kind: 'mcq',
          topic: 'Operating Systems',
          difficulty: 'Medium',
          questions: [
            QuizQuestion(
              id: 'q1',
              text: _longQuestion,
              options: [_longOption, _longOption, _longOption, _longOption],
            ),
          ],
        );
        app.result = const ChallengeResult(
          success: false,
          accuracy: 100,
          attempts: 12,
          seconds: 3725,
          feedback: 'A well-reasoned defence. You described the scheduler clearly and noted the context-switch '
              'cost. Consider mentioning how priorities interact with starvation and aging as well.',
        );

        final screens = <String, Widget>{
          'splash': const SplashScreen(),
          'home': const HomeScreen(),
          'new alarm': const AlarmFormScreen(),
          'edit alarm': const AlarmFormScreen(alarmId: 'a1'),
          'edit note alarm': const AlarmFormScreen(alarmId: 'a2'),
          'ring': const RingScreen(),
          'mcq': const McqScreen(),
          'results (failed)': const ResultsScreen(),
          'settings': const SettingsScreen(),
          'notes': const NotesScreen(),
          'voice': const VoiceScreen(),
        };

        // Collect every layout error across all screens, with file and line,
        // instead of stopping at the first one.
        final problems = <String>[];
        var current = '';
        final previous = FlutterError.onError;
        FlutterError.onError = (details) {
          // dumpErrorToConsole adds the widget's source location to the report.
          debugPrint('--- layout error on the $current screen');
          FlutterError.dumpErrorToConsole(details, forceReport: true);
          problems.add('$current: ${details.exceptionAsString().split('\n').first}');
        };
        try {
          for (final entry in screens.entries) {
            current = entry.key;
            if (entry.key == 'voice') {
              app.session = const ChallengeSession(
                id: 's2',
                kind: 'voice',
                topic: 'Databases',
                difficulty: 'Hard',
                prompt: 'Explain how a database index speeds up queries, and describe one trade-off of adding '
                    'too many indexes to a table that is written to constantly.',
                passScore: 80,
              );
            }
            await tester.pumpWidget(_wrap(app, entry.value));
            await tester.pump(const Duration(milliseconds: 700));
          }
        } finally {
          FlutterError.onError = previous;
        }
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }
  }
}
