import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/renaissance.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final r = app.result;
    if (r == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(app.ringingAlarm == null ? '/home' : '/ring');
      });
      return const SizedBox.shrink();
    }
    final c = context.colors;
    final stats = [('Accuracy', '${r.accuracy}%'), ('Attempts', '${r.attempts}'), ('Time', r.timeLabel)];

    return Screen(
      footer: r.success
          ? GoldButton(
              label: 'Dismiss Alarm',
              glow: true,
              onPressed: () async {
                await app.dismissAlarm();
                if (context.mounted) context.go('/home');
              },
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GoldButton(label: 'Retry Challenge', onPressed: () => context.go('/ring')),
                const SizedBox(height: 8),
                GoldButton(
                  label: 'Emergency Dismiss',
                  variant: GoldVariant.ghost,
                  onPressed: () async {
                    await app.dismissAlarm(emergency: true);
                    if (context.mounted) context.go('/home');
                  },
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Center(
            child: Container(
              width: 144,
              height: 144,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.primary),
                boxShadow: c.glow,
              ),
              child: Icon(
                r.success ? Icons.workspace_premium_outlined : Icons.hourglass_empty,
                size: 72,
                color: c.primary,
              ),
            ),
          ),
          const SizedBox(height: 32),
          GoldText(r.success ? 'Victory' : 'Not Yet', style: Typo.display(40)),
          const SizedBox(height: 8),
          Text(
            r.success ? 'Thy intellect is awake.' : 'The trial must be attempted anew.',
            textAlign: TextAlign.center,
            style: Typo.serif(22, italic: true, color: c.foreground),
          ),
          const Ornament(padding: EdgeInsets.symmetric(vertical: 24)),
          Row(
            children: [
              for (var i = 0; i < stats.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Panel(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
                    child: Column(
                      children: [
                        Text(stats[i].$2, style: Typo.display(22, color: c.primary)),
                        const SizedBox(height: 4),
                        Text(
                          stats[i].$1.toUpperCase(),
                          style: Typo.sans(10, color: c.mutedForeground, letterSpacing: 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'THE ORACLE${String.fromCharCode(0x2019)}S COUNSEL',
                  style: Typo.display(12, color: c.primary, letterSpacing: 3.6),
                ),
                const SizedBox(height: 8),
                Text(r.feedback, style: Typo.serif(20, italic: true, color: c.foreground)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
