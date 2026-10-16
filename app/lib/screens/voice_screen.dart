import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../models/constants.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/clock_dial.dart';
import '../widgets/preview_bar.dart';
import '../widgets/renaissance.dart';

enum _Phase { ready, recording, processing, feedback }

/// The voice interview: the examiner asks the alarm's questions one at a time,
/// each answered aloud and graded. A question must reach the pass mark before the
/// next one is asked, exactly like multiple choice, so the alarm stays on until
/// the whole interview is done.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> with SingleTickerProviderStateMixin {
  static const _maxSeconds = 90;

  final _recorder = AudioRecorder();
  late final AnimationController _wave;
  int _index = 0;
  _Phase _phase = _Phase.ready;
  int _secs = 0;
  double _level = 0;
  Timer? _timer;
  StreamSubscription<Amplitude>? _amplitude;
  String? _path;
  VoiceGrade? _grade;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    if (context.read<AppState>().settings.animations) _wave.repeat();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amplitude?.cancel();
    _wave.dispose();
    _recorder.dispose();
    _deleteRecording();
    super.dispose();
  }

  void _deleteRecording() {
    final path = _path;
    _path = null;
    if (path != null) File(path).delete().catchError((Object _) => File(path));
  }

  Future<void> _toggle() async {
    if (_phase == _Phase.processing || _busy) return;
    if (_phase == _Phase.recording) return _stop();

    if (!await _recorder.hasPermission()) {
      if (mounted) {
        setState(() => _error =
            'Microphone access is needed for the interview. Allow it in the phone settings, then tap the microphone again.');
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    _deleteRecording();
    await _recorder.start(
      // 16 kHz mono WAV: small, and a format the AI grader accepts everywhere.
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: '${dir.path}/aurora_answer.wav',
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secs++);
      if (_secs >= _maxSeconds) _stop();
    });
    _amplitude = _recorder.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((a) {
      // dBFS runs from about -45 (quiet room) up to 0 (clipping).
      if (mounted) setState(() => _level = ((a.current + 45) / 45).clamp(0.0, 1.0));
    });
    setState(() {
      _phase = _Phase.recording;
      _secs = 0;
      _grade = null;
      _error = null;
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    await _amplitude?.cancel();
    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.ready;
      _path = path;
      _level = 0;
    });
  }

  Future<void> _submit(AppState app) async {
    final path = _path;
    if (path == null) return;
    final question = app.session!.questions[_index];
    setState(() {
      _phase = _Phase.processing;
      _error = null;
    });
    try {
      final bytes = await File(path).readAsBytes();
      final grade = await app.submitVoice(question.id, _secs, base64Encode(bytes));
      if (!mounted) return;
      setState(() {
        _grade = grade;
        _phase = _Phase.feedback;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.isNetwork ? 'The examiner needs the internet. Reconnect, then submit again.' : e.message;
          _phase = _Phase.ready;
        });
      }
    }
  }

  /// Moves to the next question, or finishes the interview after the last one.
  Future<void> _next(AppState app) async {
    final total = app.session!.questions.length;
    if (_index + 1 < total) {
      _deleteRecording();
      setState(() {
        _index++;
        _phase = _Phase.ready;
        _secs = 0;
        _grade = null;
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

  void _tryAgain() {
    _deleteRecording();
    setState(() {
      _phase = _Phase.ready;
      _secs = 0;
      _grade = null;
      _error = null;
    });
  }

  String get _status => switch (_phase) {
        _Phase.ready => _path != null ? 'Recorded $kEmDash submit, or record again' : 'Tap to speak',
        _Phase.recording => 'Recording$kEllipsis',
        _Phase.processing => 'The examiner weighs thy words$kEllipsis',
        _Phase.feedback => 'Judgement rendered',
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final session = app.session;
    if (session == null || !session.isVoice || session.questions.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(app.ringingAlarm == null ? '/home' : '/ring');
      });
      return const SizedBox.shrink();
    }
    final c = context.colors;
    final total = session.questions.length;
    final question = session.questions[_index];
    final recording = _phase == _Phase.recording;
    final grade = _grade;
    final passed = grade?.passed ?? false;
    final isLast = _index + 1 >= total;
    final progress = (_index + (passed ? 1 : 0)) / total;

    return Screen(
      footer: _phase == _Phase.feedback && grade != null
          ? (passed
              ? GoldButton(
                  label: isLast ? 'See Results' : 'Next Question',
                  busy: _busy,
                  onPressed: () => _next(app),
                )
              : GoldButton(label: 'Try Again', onPressed: _tryAgain))
          : GoldButton(
              label: 'Submit Explanation',
              onPressed: _path != null && _phase == _Phase.ready ? () => _submit(app) : null,
              busy: _phase == _Phase.processing,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PreviewBar(),
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
          const SizedBox(height: 24),
          GoldText('Defend Thy Knowledge', style: Typo.display(30)),
          const Ornament(),
          Panel(child: Text(question.text, style: Typo.serif(22, color: c.foreground))),
          const SizedBox(height: 28),
          Center(
            child: SizedBox(
              width: 192,
              height: 192,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TickRing(size: 192, color: c.primary.withValues(alpha: 0.6)),
                  Semantics(
                    button: true,
                    label: recording ? 'Stop recording' : 'Start recording',
                    child: GestureDetector(
                      onTap: _toggle,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: recording ? c.primary : c.card,
                          border: Border.all(color: c.primary, width: 2),
                          boxShadow: recording
                              ? [BoxShadow(color: c.primary.withValues(alpha: 0.4), spreadRadius: 10 * _level, blurRadius: 18)]
                              : null,
                        ),
                        child: Icon(
                          recording ? Icons.stop_rounded : Icons.mic_none,
                          size: 44,
                          color: recording ? c.onPrimary : c.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 40,
            child: AnimatedBuilder(
              animation: _wave,
              builder: (context, _) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < 21; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: 4,
                      height: (20 + (i * 37) % 20) *
                          (recording ? 0.3 + 0.7 * math.max(_level, 0.12) * (0.6 + 0.4 * math.sin(2 * math.pi * (_wave.value + i / 21))) : 0.5),
                      decoration: BoxDecoration(
                        color: c.primary.withValues(alpha: recording ? 1 : 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${pad2(_secs ~/ 60)}:${pad2(_secs % 60)}',
            textAlign: TextAlign.center,
            style: Typo.display(26, color: c.primary),
          ),
          const SizedBox(height: 4),
          Text(
            _status.toUpperCase(),
            textAlign: TextAlign.center,
            style: Typo.sans(11, color: c.mutedForeground, letterSpacing: 2.8),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            InlineMessage(_error!, isError: true),
          ],
          if (_phase == _Phase.feedback && grade != null) ...[
            const SizedBox(height: 24),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Score $kMiddot ${grade.score}%  (pass ${grade.passScore}%)',
                    style: Typo.display(16, color: passed ? c.primary : c.accent),
                  ),
                  const SizedBox(height: 8),
                  Text(grade.feedback, style: Typo.serif(20, italic: true, color: c.foreground)),
                  if (!passed)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Answer again to reach the pass mark and move on.',
                        style: Typo.sans(12, color: c.mutedForeground),
                      ),
                    ),
                  if (grade.mock)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Practice grading: the server has no AI key configured.',
                        style: Typo.sans(12, color: c.mutedForeground),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
