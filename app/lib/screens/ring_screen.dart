import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/constants.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/clock_dial.dart';
import '../widgets/hero_art.dart';
import '../widgets/preview_bar.dart';
import '../widgets/renaissance.dart';

class RingScreen extends StatefulWidget {
  const RingScreen({super.key});

  @override
  State<RingScreen> createState() => _RingScreenState();
}

class _RingScreenState extends State<RingScreen> with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pulse;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 40));
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    if (context.read<AppState>().settings.animations) {
      _spin.repeat();
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _begin(AppState app) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await app.startChallenge();
      if (!mounted) return;
      context.go(session.isVoice ? '/challenge/voice' : '/challenge/mcq');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.isNetwork
          ? 'Cannot reach the oracle. Check thy connection and try again.'
          : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Says exactly what this alarm will ask: its type, how many, and the source
  /// it chose (a topic, or the title of the notes).
  String _subtitle(AppState app, AlarmModel alarm) {
    final n = alarm.questions;
    final plural = n > 1 ? 's' : '';
    final source = alarm.hasNote
        ? (app.notes.where((x) => x.id == alarm.noteId).firstOrNull?.title ?? 'thy notes')
        : alarm.topic;
    final what = switch (alarm.type) {
      'Voice' => '$n spoken question$plural',
      'Random' => '$n question$plural, written or spoken',
      _ => '$n trial$plural',
    };
    return '${alarm.label} $kEmDash $what on $source';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final alarm = app.ringingAlarm;
    if (alarm == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/home');
      });
      return const SizedBox.shrink();
    }
    final c = context.colors;

    return Screen(
      center: true,
      background: const Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: 0.55,
          widthFactor: 1,
          child: HeroArt(opacity: 0.3, alignment: Alignment.bottomCenter),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PreviewBar(),
          SizedBox(
            width: 256,
            height: 256,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _spin,
                  builder: (context, _) =>
                      RomanDial(size: 256, color: c.primary.withValues(alpha: 0.7), turns: _spin.value),
                ),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    final t = _pulse.value;
                    return Container(
                      width: 160,
                      height: 160,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.card.withValues(alpha: 0.8),
                        border: Border.all(color: c.primary),
                        boxShadow: [
                          BoxShadow(color: c.primary.withValues(alpha: 0.5 * (1 - t)), spreadRadius: 22 * t),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: GoldText(
                    alarm.timeLabel,
                    style: Typo.display(48).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          GoldText('The Hour Has Come', style: Typo.display(34)),
          const Ornament(),
          Text(
            _subtitle(app, alarm),
            textAlign: TextAlign.center,
            style: Typo.serif(20, italic: true, color: c.foreground),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.music_note, size: 14, color: c.mutedForeground),
              const SizedBox(width: 4),
              Text(
                '${app.settings.sound} ringing$kEllipsis',
                style: Typo.sans(12, color: c.mutedForeground),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            InlineMessage(_error!, isError: true),
          ],
          const SizedBox(height: 40),
          GoldButton(
            label: _error == null ? 'Begin Challenge' : 'Try Again',
            glow: true,
            busy: _busy,
            onPressed: () => _begin(app),
          ),
        ],
      ),
    );
  }
}
