import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/constants.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/hero_art.dart';
import '../widgets/renaissance.dart';

const _tabular = [FontFeature.tabularFigures()];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.colors;
    final active = app.alarms.where((a) => a.enabled).length;

    return Screen(
      onRefresh: app.refreshAll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(kAppName.toUpperCase(), style: Typo.display(14, color: c.primary, letterSpacing: 4.2)),
              Row(
                children: [
                  _HeaderIcon(icon: Icons.menu_book_outlined, label: 'My notes', onTap: () => context.push('/notes')),
                  const SizedBox(width: 16),
                  _HeaderIcon(icon: Icons.settings_outlined, label: 'Settings', onTap: () => context.push('/settings')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          _ClockArch(now: _now),
          const SizedBox(height: 24),
          GoldButton(label: '+ Set Alarm', onPressed: () => context.push('/alarm/new')),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Upcoming Alarms',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Typo.display(18, color: c.primary),
                ),
              ),
              const SizedBox(width: 12),
              Text('$active active', style: Typo.sans(12, color: c.mutedForeground)),
            ],
          ),
          if (app.offline)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Offline $kEmDash showing saved alarms',
                style: Typo.sans(12, color: c.accent),
              ),
            ),
          const SizedBox(height: 12),
          if (app.alarms.isEmpty)
            Panel(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No alarms yet. Set one, and let thy mind rise with the sun.',
                textAlign: TextAlign.center,
                style: Typo.serif(18, italic: true, color: c.mutedForeground),
              ),
            )
          else
            for (final alarm in app.alarms)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: _AlarmCard(alarm: alarm)),
        ],
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 22, color: context.colors.primary)),
      ),
    );
  }
}

class _ClockArch extends StatelessWidget {
  const _ClockArch({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        final radius = BorderRadius.vertical(top: Radius.elliptical(box.maxWidth / 2, 128));
        return DecoratedBox(
          decoration: BoxDecoration(
            color: c.card.withValues(alpha: 0.6),
            border: Border.all(color: c.primary.withValues(alpha: 0.6)),
            borderRadius: radius,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                const Positioned.fill(child: HeroArt(opacity: 0.15)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 64, 24, 32),
                  child: Column(
                    children: [
                      Text(
                        kWeekdayNames[now.weekday % 7].toUpperCase(),
                        style: Typo.display(12, color: c.mutedForeground, letterSpacing: 3.6),
                      ),
                      const SizedBox(height: 12),
                      GoldText(
                        '${pad2(now.hour)}:${pad2(now.minute)}',
                        style: Typo.display(72).copyWith(fontFeatures: _tabular),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${now.day} ${kMonthNames[now.month - 1]} ${now.year}',
                        style: Typo.serif(20, italic: true, color: c.foreground),
                      ),
                      const Ornament(padding: EdgeInsets.only(top: 20)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AlarmCard extends StatelessWidget {
  const _AlarmCard({required this.alarm});

  final AlarmModel alarm;

  Future<bool> _confirmDelete(BuildContext context) async {
    final app = context.read<AppState>();
    final ok = await showConfirm(
      context,
      title: 'Delete alarm',
      message: 'Remove "${alarm.label}" at ${alarm.timeLabel}?',
      confirmLabel: 'Delete',
    );
    if (!ok) return false;
    try {
      await app.deleteAlarm(alarm.id);
    } catch (e) {
      app.showNotice(e.toString());
    }
    return false; // the list rebuilds without the card once the state updates
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final app = context.read<AppState>();
    final kind = alarm.type == 'Voice' ? 'Voice interview' : alarm.type;
    // Spell out the source, so it is clear what this alarm will quiz on.
    final source = alarm.hasNote
        ? (app.notes.where((n) => n.id == alarm.noteId).firstOrNull?.title ?? 'My notes')
        : alarm.topic;

    return Dismissible(
      key: ValueKey(alarm.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: c.accent.withValues(alpha: 0.2),
        child: Icon(Icons.delete_outline, color: c.accent),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push('/alarm/${alarm.id}'),
        child: Panel(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alarm.timeLabel,
                      style: Typo.display(30, color: alarm.enabled ? c.foreground : c.mutedForeground)
                          .copyWith(fontFeatures: _tabular),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${alarm.label} $kMiddot $kind $kMiddot ${alarm.difficulty}',
                      style: Typo.sans(14, color: c.mutedForeground),
                    ),
                    Text(
                      '${alarm.hasNote ? 'Notes' : 'Topic'}: $source',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Typo.sans(12, color: c.mutedForeground.withValues(alpha: 0.85)),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (var i = 0; i < 7; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              kDayLetters[i],
                              style: Typo.sans(
                                11,
                                color: alarm.days.contains(i) ? c.primary : c.mutedForeground.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                        if (alarm.isOneShot) Text('once', style: Typo.sans(11, color: c.mutedForeground)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AuroraSwitch(
                    label: 'Toggle ${alarm.label}',
                    value: alarm.enabled,
                    onChanged: (v) => app.setAlarmEnabled(alarm, v),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      app.startPreview(alarm);
                      context.go('/ring');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('PREVIEW', style: Typo.sans(12, color: c.accent, letterSpacing: 2.4)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
