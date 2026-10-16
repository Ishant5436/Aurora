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
          ? 'Cannot reach the oracle. Check thy connection and try again, or use emergency dismiss.'
          : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _emergency(AppState app) async {
    final ok = await showConfirm(
      context,
      title: 'Emergency dismiss',
      message: 'Silence the alarm without answering? This is recorded.',
      confirmLabel: 'Dismiss',
    );
    if (!ok || !mounted) return;
    await app.dismissAlarm(emergency: true);
    if (mounted) context.go('/home');
  }

  String _subtitle(AlarmModel alarm) {
    final n = alarm.questions;
    final kind = alarm.effectiveType;
    if (kind == 'Voice') return '${alarm.label} $kEmDash a spoken trial awaits';
    if (kind == 'Random') return '${alarm.label} $kEmDash a trial of knowledge or voice awaits';
    return '${alarm.label} $kEmDash $n trial${n > 1 ? 's' : ''} await';
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
          if (app.previewMode)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('PREVIEW', style: Typo.display(11, color: c.accent, letterSpacing: 3.6)),
            ),
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
            _subtitle(alarm),
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
          const SizedBox(height: 20),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _emergency(app),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'EMERGENCY DISMISS',
                style: Typo.display(12, color: c.mutedForeground, letterSpacing: 2.4)
                    .copyWith(decoration: TextDecoration.underline),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
