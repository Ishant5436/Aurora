import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Shown only while an alarm is being previewed from the home screen. Nothing is
/// ringing then, so leaving is fine. A real ringing alarm shows nothing here and
/// can only be silenced by passing its challenge.
class PreviewBar extends StatelessWidget {
  const PreviewBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.previewMode) return const SizedBox.shrink();
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('PREVIEW', style: Typo.display(11, color: c.accent, letterSpacing: 3.6)),
          Semantics(
            button: true,
            label: 'Exit preview',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                await app.dismissAlarm();
                if (context.mounted) context.go('/home');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Text(
                  'EXIT PREVIEW',
                  style: Typo.display(11, color: c.mutedForeground, letterSpacing: 2.4)
                      .copyWith(decoration: TextDecoration.underline),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
