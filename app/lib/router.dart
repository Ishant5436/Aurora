import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/alarm_form_screen.dart';
import 'screens/home_screen.dart';
import 'screens/mcq_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/results_screen.dart';
import 'screens/ring_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/voice_screen.dart';
import 'state/app_state.dart';

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 250),
      transitionsBuilder: (context, animation, secondary, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
    );

GoRouter buildRouter(AppState app) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: app,
    redirect: (context, state) {
      // An alarm that is already ringing (it launched the app) skips the splash.
      if (state.uri.path == '/' && app.hasRealRing) return '/ring';
      return null;
    },
    routes: [
      GoRoute(path: '/', pageBuilder: (c, s) => _fade(s, const SplashScreen())),
      GoRoute(path: '/home', pageBuilder: (c, s) => _fade(s, const HomeScreen())),
      GoRoute(path: '/alarm/new', pageBuilder: (c, s) => _fade(s, const AlarmFormScreen())),
      GoRoute(
        path: '/alarm/:id',
        pageBuilder: (c, s) => _fade(s, AlarmFormScreen(alarmId: s.pathParameters['id'])),
      ),
      GoRoute(path: '/ring', pageBuilder: (c, s) => _fade(s, const RingScreen())),
      GoRoute(path: '/challenge/mcq', pageBuilder: (c, s) => _fade(s, const McqScreen())),
      GoRoute(path: '/challenge/voice', pageBuilder: (c, s) => _fade(s, const VoiceScreen())),
      GoRoute(path: '/results', pageBuilder: (c, s) => _fade(s, const ResultsScreen())),
      GoRoute(path: '/settings', pageBuilder: (c, s) => _fade(s, const SettingsScreen())),
      GoRoute(path: '/notes', pageBuilder: (c, s) => _fade(s, const NotesScreen())),
    ],
  );
}
