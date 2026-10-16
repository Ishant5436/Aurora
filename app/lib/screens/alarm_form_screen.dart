import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/constants.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/renaissance.dart';

/// Creates a new alarm, or edits one when [alarmId] is given.
class AlarmFormScreen extends StatefulWidget {
  const AlarmFormScreen({super.key, this.alarmId});

  final String? alarmId;

  @override
  State<AlarmFormScreen> createState() => _AlarmFormScreenState();
}

class _AlarmFormScreenState extends State<AlarmFormScreen> {
  AlarmModel? _existing;
  late int _hour;
  late int _minute;
  late List<int> _days;
  late final TextEditingController _label;
  late String _difficulty;
  late String _type;
  late int _questions;
  late String _topic;
  String? _noteId;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.alarmId != null;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final a = _editing ? app.alarms.where((x) => x.id == widget.alarmId).firstOrNull : null;
    _existing = a;
    _hour = a?.hour ?? 6;
    _minute = a?.minute ?? 30;
    _days = [...(a?.days ?? const [1, 2, 3, 4, 5])];
    _label = TextEditingController(text: a?.label ?? 'Morning Study');
    _difficulty = a?.difficulty ?? app.settings.difficulty;
    _type = a?.type ?? 'MCQ';
    _questions = a?.questions ?? 3;
    _topic = a?.topic ?? (app.settings.topics.firstOrNull ?? kTopics.first);
    _noteId = a?.noteId;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save(AppState app) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final alarm = AlarmModel(
      id: _existing?.id ?? '',
      hour: _hour,
      minute: _minute,
      label: _label.text.trim().isEmpty ? 'Alarm' : _label.text.trim(),
      days: ([..._days]..sort()),
      enabled: _existing?.enabled ?? true,
      difficulty: _difficulty,
      type: _noteId != null ? 'MCQ' : _type,
      questions: _questions,
      topic: _topic,
      noteId: _noteId,
    );
    try {
      await app.saveAlarm(alarm);
      if (mounted) context.canPop() ? context.pop() : context.go('/home');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(AppState app) async {
    final ok = await showConfirm(
      context,
      title: 'Delete alarm',
      message: 'Remove "${_existing!.label}" at ${_existing!.timeLabel}?',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    try {
      await app.deleteAlarm(_existing!.id);
      if (mounted) context.canPop() ? context.pop() : context.go('/home');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.colors;

    if (_editing && _existing == null) {
      return Screen(
        child: Column(children: [
          const TopBar(title: 'Alarm'),
          Panel(child: InlineMessage('That alarm no longer exists.', isError: true)),
        ]),
      );
    }

    final usesNotes = _noteId != null;
    final effectiveType = usesNotes ? 'MCQ' : _type;

    return Screen(
      footer: GoldButton(label: 'Save Alarm', busy: _busy, onPressed: () => _save(app)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TopBar(title: _editing ? 'Edit Alarm' : 'New Alarm'),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: [
                // Scales down on very narrow phones instead of overflowing.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Dial(label: 'Hour', value: _hour, max: 24, onChanged: (v) => setState(() => _hour = v)),
                      Padding(
                        padding: const EdgeInsets.only(top: 34, left: 12, right: 12),
                        child: Text(':', style: Typo.display(48, color: c.primary)),
                      ),
                      _Dial(label: 'Minute', value: _minute, max: 60, onChanged: (v) => setState(() => _minute = v)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final d in const [-5, 5, 15])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _minute = (_minute + d + 60) % 60),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border.all(color: c.border),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text('${d > 0 ? '+' : ''}${d}m', style: Typo.sans(12, color: c.mutedForeground)),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Ornament(padding: EdgeInsets.symmetric(vertical: 24)),
          const SectionLabel('Repeat'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _days.contains(i) ? _days.remove(i) : _days.add(i)),
                  child: Semantics(
                    button: true,
                    selected: _days.contains(i),
                    label: kWeekdayNames[i],
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _days.contains(i) ? c.primary : null,
                        border: Border.all(color: _days.contains(i) ? c.primary : c.border),
                      ),
                      child: Text(
                        kDayLetters[i],
                        style: Typo.display(14, color: _days.contains(i) ? c.onPrimary : c.mutedForeground),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_days.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('No days selected: this alarm rings once.', style: Typo.sans(12, color: c.mutedForeground)),
            ),
          const SizedBox(height: 24),
          const SectionLabel('Label'),
          TextField(
            controller: _label,
            maxLength: 40,
            style: Typo.serif(22, color: c.foreground),
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.border)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.primary)),
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('Difficulty'),
          ChipRow(options: kDifficulties, value: _difficulty, onChanged: (v) => setState(() => _difficulty = v)),
          const SizedBox(height: 24),
          const SectionLabel('Quiz Source'),
          ChipRow(
            options: const ['Topic', 'My Notes'],
            value: usesNotes ? 'My Notes' : 'Topic',
            onChanged: (v) => setState(() {
              if (v == 'Topic') {
                _noteId = null;
              } else {
                _noteId = app.notes.firstOrNull?.id;
                if (_noteId != null) _type = 'MCQ';
              }
            }),
          ),
          const SizedBox(height: 16),
          if (usesNotes)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in app.notes)
                  AuroraChip(label: n.title, active: _noteId == n.id, onTap: () => setState(() => _noteId = n.id)),
              ],
            )
          else if (_noteId == null && app.notes.isEmpty)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Upload thy notes and $kAppName will quiz thee on them.',
                    textAlign: TextAlign.center,
                    style: Typo.serif(18, italic: true, color: c.mutedForeground),
                  ),
                  const SizedBox(height: 12),
                  GoldButton(label: 'Upload Notes', variant: GoldVariant.outline, onPressed: () => context.push('/notes')),
                ],
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in kTopics) AuroraChip(label: t, active: _topic == t, onTap: () => setState(() => _topic = t)),
              ],
            ),
          const SizedBox(height: 24),
          const SectionLabel('Challenge'),
          if (usesNotes)
            Text('Quizzes from your notes are multiple choice.', style: Typo.sans(13, color: c.mutedForeground))
          else
            ChipRow(
              options: kChallengeTypes,
              value: _type,
              labelFor: (t) => t == 'Voice' ? 'Voice Interview' : t,
              onChanged: (v) => setState(() => _type = v),
            ),
          if (effectiveType != 'Voice') ...[
            const SizedBox(height: 24),
            SectionLabel('Questions to dismiss $kMiddot $_questions'),
            Slider(
              value: _questions.toDouble(),
              min: 1,
              max: 4,
              divisions: 3,
              label: '$_questions',
              onChanged: (v) => setState(() => _questions = v.round()),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            InlineMessage(_error!, isError: true),
          ],
          if (_editing) ...[
            const SizedBox(height: 24),
            GoldButton(label: 'Delete Alarm', variant: GoldVariant.ghost, onPressed: () => _delete(app)),
          ],
        ],
      ),
    );
  }
}

/// Hour or minute wheel: tap the arrows, or drag the number up and down.
class _Dial extends StatefulWidget {
  const _Dial({required this.label, required this.value, required this.max, required this.onChanged});

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<_Dial> createState() => _DialState();
}

class _DialState extends State<_Dial> {
  double _drag = 0;

  void _step(int delta) => widget.onChanged((widget.value + delta + widget.max) % widget.max);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Increase ${widget.label.toLowerCase()}',
          onPressed: () => _step(1),
          icon: Icon(Icons.keyboard_arrow_up, color: c.primary, size: 30),
        ),
        GestureDetector(
          onVerticalDragUpdate: (d) {
            _drag += d.delta.dy;
            while (_drag <= -16) {
              _step(1);
              _drag += 16;
            }
            while (_drag >= 16) {
              _step(-1);
              _drag -= 16;
            }
          },
          child: Container(
            width: 96,
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.background.withValues(alpha: 0.6),
              border: Border.all(color: c.primary.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(2),
            ),
            child: GoldText(
              pad2(widget.value),
              style: Typo.display(48).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Decrease ${widget.label.toLowerCase()}',
          onPressed: () => _step(-1),
          icon: Icon(Icons.keyboard_arrow_down, color: c.primary, size: 30),
        ),
        Text(widget.label.toUpperCase(), style: Typo.sans(10, color: c.mutedForeground, letterSpacing: 3)),
      ],
    );
  }
}
