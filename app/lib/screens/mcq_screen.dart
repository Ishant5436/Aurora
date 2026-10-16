import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/constants.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/renaissance.dart';

enum _Status { idle, right, wrong }

class McqScreen extends StatefulWidget {
  const McqScreen({super.key});

  @override
  State<McqScreen> createState() => _McqScreenState();
}

class _McqScreenState extends State<McqScreen> {
  int _index = 0;
  int? _selected;
  _Status _status = _Status.idle;
  String? _explanation;
  String? _error;
  bool _busy = false;

  Future<void> _submit(AppState app) async {
    final question = app.session!.questions[_index];
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await app.answer(question.id, _selected!);
      if (!mounted) return;
      if (app.settings.haptics) {
        res.correct ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();
      }
      setState(() {
        _status = res.correct ? _Status.right : _Status.wrong;
        _explanation = res.explanation;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _next(AppState app) async {
    final total = app.session!.questions.length;
    if (_index + 1 < total) {
      setState(() {
        _index++;
        _selected = null;
        _status = _Status.idle;
        _explanation = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.completeChallenge();
      if (mounted) context.go('/results');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final session = app.session;
    if (session == null || session.isVoice || session.questions.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(app.ringingAlarm == null ? '/home' : '/ring');
      });
      return const SizedBox.shrink();
    }
    final c = context.colors;
    final total = session.questions.length;
    final question = session.questions[_index];
    final solved = _status == _Status.right;
    final progress = (_index + (solved ? 1 : 0)) / total;

    return Screen(
      footer: solved
          ? GoldButton(
              label: _index + 1 < total ? 'Next Question' : 'See Results',
              busy: _busy,
              onPressed: () => _next(app),
            )
          : GoldButton(
              label: _status == _Status.wrong ? 'Retry' : 'Submit Answer',
              busy: _busy,
              onPressed: _selected == null ? null : () => _submit(app),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'QUESTION ${_index + 1} OF $total',
            textAlign: TextAlign.center,
            style: Typo.display(12, color: c.mutedForeground, letterSpacing: 3.6),
          ),
          const SizedBox(height: 12),
          Container(
            height: 2,
            color: c.muted,
            alignment: Alignment.centerLeft,
            child: AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 700),
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(color: c.primary),
            ),
          ),
          const SizedBox(height: 32),
          GoldText('A Trial of Knowledge', style: Typo.display(30)),
          const Ornament(),
          Text(
            question.text,
            textAlign: TextAlign.center,
            style: Typo.serif(26, color: c.foreground),
          ),
          const SizedBox(height: 28),
          for (var k = 0; k < question.options.length; k++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Option(
                letter: 'ABCD'[k],
                text: question.options[k],
                chosen: _selected == k,
                status: _selected == k ? _status : _Status.idle,
                enabled: !solved && !_busy,
                onTap: () => setState(() {
                  _selected = k;
                  _status = _Status.idle;
                  _error = null;
                }),
              ),
            ),
          const SizedBox(height: 8),
          // A minimum, not a fixed height: explanations can run to several lines.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Center(
              child: _error != null
                  ? InlineMessage(_error!, isError: true)
                  : solved
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Correct $kEmDash wisdom prevails.',
                              style: Typo.serif(20, italic: true, color: c.primary),
                            ),
                            if (_explanation != null && _explanation!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _explanation!,
                                  textAlign: TextAlign.center,
                                  style: Typo.serif(16, color: c.mutedForeground),
                                ),
                              ),
                          ],
                        )
                      : _status == _Status.wrong
                          ? Text('Not quite. Try once more.', style: Typo.serif(20, italic: true, color: c.accent))
                          : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.letter,
    required this.text,
    required this.chosen,
    required this.status,
    required this.enabled,
    required this.onTap,
  });

  final String letter;
  final String text;
  final bool chosen;
  final _Status status;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Color border = c.border;
    Color? fill = c.card.withValues(alpha: 0.7);
    List<BoxShadow>? shadow;
    if (chosen && status == _Status.right) {
      border = c.primary;
      fill = c.primary.withValues(alpha: 0.2);
      shadow = c.glow;
    } else if (chosen && status == _Status.wrong) {
      border = c.accent;
      fill = c.accent.withValues(alpha: 0.2);
    } else if (chosen) {
      border = c.primary;
      fill = c.parchment.withValues(alpha: 0.1);
    }

    return Semantics(
      button: true,
      selected: chosen,
      label: 'Option $letter: $text',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(2),
              boxShadow: shadow,
            ),
            child: Row(
              children: [
                Text(letter, style: Typo.display(16, color: c.primary)),
                const SizedBox(width: 16),
                Expanded(child: Text(text, style: Typo.sans(16, color: c.foreground))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
