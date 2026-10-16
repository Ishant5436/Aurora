import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../config.dart';
import '../models/constants.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/renaissance.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Tracks the slider while it is being dragged; committed once on release so
  // we do not hit the server and reschedule every alarm on every tick.
  double? _dragVolume;

  Future<void> _setMicrophone(AppState app, bool on) async {
    if (on) {
      final probe = AudioRecorder();
      final granted = await probe.hasPermission();
      await probe.dispose();
      if (!granted) {
        app.showNotice('Microphone permission was denied. Enable it in the system Settings app.');
        return;
      }
    }
    await app.updateSettings(app.settings.copyWith(microphone: on));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final c = context.colors;
    final user = app.user;

    Widget toggleRow(String label, bool value, ValueChanged<bool> onChanged) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(label, style: Typo.sans(16, color: c.foreground))),
              const SizedBox(width: 12),
              AuroraSwitch(label: label, value: value, onChanged: onChanged),
            ],
          ),
        );

    return Screen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TopBar(title: 'Settings'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel('Sound $kMiddot ${(_dragVolume ?? s.volume.toDouble()).round()}%'),
                Slider(
                  value: _dragVolume ?? s.volume.toDouble(),
                  min: 0,
                  max: 100,
                  onChanged: (v) => setState(() => _dragVolume = v),
                  onChangeEnd: (v) {
                    setState(() => _dragVolume = null);
                    app.updateSettings(s.copyWith(volume: v.round()));
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final sound in kSounds)
                      AuroraChip(
                        label: sound,
                        active: s.sound == sound,
                        onTap: () => app.updateSettings(s.copyWith(sound: sound)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Default Difficulty'),
                ChipRow(
                  options: kDifficulties,
                  value: s.difficulty,
                  onChanged: (v) => app.updateSettings(s.copyWith(difficulty: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Preferred Topics'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in kTopics)
                      AuroraChip(
                        label: t,
                        active: s.topics.contains(t),
                        onTap: () {
                          final next = s.topics.contains(t) ? s.topics.where((x) => x != t).toList() : [...s.topics, t];
                          app.updateSettings(s.copyWith(topics: next));
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                toggleRow('Dark theme', s.isDark, (v) => app.updateSettings(s.copyWith(theme: v ? 'dark' : 'light'))),
                Divider(height: 1, color: c.border),
                toggleRow('Light haptics', s.haptics, (v) => app.updateSettings(s.copyWith(haptics: v))),
                Divider(height: 1, color: c.border),
                toggleRow('Animations', s.animations, (v) => app.updateSettings(s.copyWith(animations: v))),
                Divider(height: 1, color: c.border),
                toggleRow('Notifications', s.notifications, (v) => app.updateSettings(s.copyWith(notifications: v))),
                Divider(height: 1, color: c.border),
                toggleRow('Microphone access', s.microphone, (v) => _setMicrophone(app, v)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push('/notes'),
            child: Panel(
              child: Row(
                children: [
                  Icon(Icons.menu_book_outlined, color: c.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text('My Notes', style: Typo.sans(16, color: c.foreground))),
                  Text('${app.notes.length}', style: Typo.sans(14, color: c.mutedForeground)),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: c.mutedForeground),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Account'),
                Text(user?.displayName ?? 'Guest Scholar', style: Typo.serif(24, color: c.foreground)),
                const SizedBox(height: 2),
                Text(
                  user == null || user.isGuest
                      ? 'Sign in to keep thine alarms and notes on every device.'
                      : (user.email ?? ''),
                  style: Typo.sans(14, color: c.mutedForeground),
                ),
                const SizedBox(height: 16),
                if (user == null || user.isGuest)
                  GoldButton(
                    label: 'Sign In or Create Account',
                    variant: GoldVariant.outline,
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const _AuthSheet(),
                    ),
                  )
                else
                  GoldButton(
                    label: 'Sign Out',
                    variant: GoldVariant.outline,
                    onPressed: () async {
                      final ok = await showConfirm(
                        context,
                        title: 'Sign out',
                        message: 'Alarms on this device will be cleared. Sign back in to restore them.',
                        confirmLabel: 'Sign out',
                      );
                      if (ok) await app.signOut();
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '$kAppName $kMiddot server: $apiBaseUrl',
            textAlign: TextAlign.center,
            style: Typo.sans(11, color: c.mutedForeground.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

class _AuthSheet extends StatefulWidget {
  const _AuthSheet();

  @override
  State<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<_AuthSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final app = context.read<AppState>();
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || password.length < 8) {
      setState(() => _error = 'Enter a valid email and a password of at least 8 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await app.register(email, password, _name.text.trim());
      } else {
        await app.login(email, password);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      app.showNotice(_register ? 'Account created. Thine alarms are safe.' : 'Welcome back.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChipRow(
              options: const ['Sign In', 'Create Account'],
              value: _register ? 'Create Account' : 'Sign In',
              onChanged: (v) => setState(() {
                _register = v == 'Create Account';
                _error = null;
              }),
            ),
            const SizedBox(height: 20),
            if (_register) ...[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                style: Typo.sans(16, color: c.foreground),
                decoration: auroraInput(context, hint: 'Name (optional)'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              style: Typo.sans(16, color: c.foreground),
              decoration: auroraInput(context, hint: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
              style: Typo.sans(16, color: c.foreground),
              decoration: auroraInput(context, hint: 'Password (8+ characters)'),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              InlineMessage(_error!, isError: true),
            ],
            const SizedBox(height: 20),
            GoldButton(label: _register ? 'Create Account' : 'Sign In', busy: _busy, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
