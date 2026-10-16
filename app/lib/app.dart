import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'router.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

class AuroraApp extends StatefulWidget {
  const AuroraApp({super.key});

  @override
  State<AuroraApp> createState() => _AuroraAppState();
}

class _AuroraAppState extends State<AuroraApp> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late final AppState _app;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _router = buildRouter(_app);
    _app.onRing = () => _router.go('/ring');
    _app.addListener(_showNotice);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _app.removeListener(_showNotice);
    _app.onRing = null;
    _router.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app re-syncs and re-arms the next occurrences.
    if (state == AppLifecycleState.resumed && _app.status == BootStatus.ready) _app.refreshAll();
  }

  void _showNotice() {
    final message = _app.takeNotice();
    if (message == null) return;
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.select<AppState, bool>((s) => s.settings.isDark);
    return MaterialApp.router(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messenger,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: _router,
    );
  }
}
