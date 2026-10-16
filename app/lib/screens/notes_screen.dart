import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/constants.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/renaissance.dart';

const _minChars = 200;
const _maxFileBytes = 10 * 1024 * 1024;

class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  void _openAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddNoteSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.colors;

    return Screen(
      onRefresh: app.refreshAll,
      footer: GoldButton(label: 'Add Notes', onPressed: () => _openAddSheet(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TopBar(title: 'My Notes'),
          Text(
            'Upload thy notes and $kAppName will turn them into a quiz. '
            'Choose them as the source when setting an alarm.',
            textAlign: TextAlign.center,
            style: Typo.serif(20, italic: true, color: c.mutedForeground),
          ),
          const Ornament(padding: EdgeInsets.symmetric(vertical: 20)),
          if (app.notes.isEmpty)
            Panel(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No notes yet. Paste some text, or upload a PDF, .txt or .md file.',
                textAlign: TextAlign.center,
                style: Typo.sans(14, color: c.mutedForeground),
              ),
            )
          else
            for (final note in app.notes)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: _NoteTile(note: note)),
        ],
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note});

  final NoteModel note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final app = context.read<AppState>();
    final date = note.createdAt?.toLocal();
    final added = date == null ? '' : ' $kMiddot ${date.day} ${kMonthNames[date.month - 1].substring(0, 3)} ${date.year}';

    return Panel(
      child: Row(
        children: [
          Icon(note.sourceType == 'file' ? Icons.description_outlined : Icons.notes, color: c.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.title, style: Typo.serif(22, color: c.foreground)),
                Text('${note.questionCount} questions$added', style: Typo.sans(13, color: c.mutedForeground)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete ${note.title}',
            icon: Icon(Icons.delete_outline, color: c.mutedForeground),
            onPressed: () async {
              final ok = await showConfirm(
                context,
                title: 'Delete notes',
                message: 'Delete "${note.title}" and its quiz? Alarms using it will switch back to a topic.',
                confirmLabel: 'Delete',
              );
              if (!ok) return;
              try {
                await app.deleteNote(note.id);
              } on ApiException catch (e) {
                app.showNotice(e.message);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _AddNoteSheet extends StatefulWidget {
  const _AddNoteSheet();

  @override
  State<_AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends State<_AddNoteSheet> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  bool _fileMode = false;
  PlatformFile? _file;
  int _fileSize = 0;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  String _mimeFor(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'md' || 'markdown' => 'text/markdown',
      _ => 'text/plain',
    };
  }

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'txt', 'md'],
    );
    if (file == null) return;
    final size = await file.length() ?? 0;
    if (!mounted) return;
    setState(() {
      if (size > _maxFileBytes) {
        _error = 'That file is over 10 MB. Choose a smaller one.';
      } else {
        _file = file;
        _fileSize = size;
        _error = null;
      }
    });
  }

  Future<void> _submit(AppState app) async {
    if (_fileMode && _file == null) {
      setState(() => _error = 'Choose a file first.');
      return;
    }
    if (!_fileMode && _text.text.trim().length < _minChars) {
      setState(() => _error = 'Add at least $_minChars characters so there is enough to quiz thee on.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? data;
      String? mime;
      final file = _file;
      if (_fileMode && file != null) {
        data = base64Encode(await file.readAsBytes());
        mime = _mimeFor(file.name);
      }
      final note = await app.uploadNote(
        title: _title.text.trim(),
        text: _fileMode ? null : _text.text,
        fileName: file?.name,
        mimeType: mime,
        base64Data: data,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      app.showNotice('Quiz ready: ${note.questionCount} questions from "${note.title}".');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final c = context.colors;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChipRow(
              options: const ['Paste Text', 'Upload File'],
              value: _fileMode ? 'Upload File' : 'Paste Text',
              onChanged: _busy
                  ? (_) {}
                  : (v) => setState(() {
                        _fileMode = v == 'Upload File';
                        _error = null;
                      }),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _title,
              enabled: !_busy,
              maxLength: 80,
              style: Typo.serif(20, color: c.foreground),
              decoration: auroraInput(context, hint: 'Title (optional)').copyWith(counterText: ''),
            ),
            const SizedBox(height: 16),
            if (_fileMode)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _busy ? null : _pick,
                child: Panel(
                  child: Row(
                    children: [
                      Icon(Icons.upload_file, color: c.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _file == null
                              ? 'Choose a PDF, .txt or .md file (up to 10 MB)'
                              : '${_file!.name}  $kMiddot  ${(_fileSize / 1024).ceil()} KB',
                          style: Typo.sans(14, color: _file == null ? c.mutedForeground : c.foreground),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              TextField(
                controller: _text,
                enabled: !_busy,
                minLines: 6,
                maxLines: 10,
                maxLength: 60000,
                style: Typo.sans(15, color: c.foreground),
                decoration: auroraInput(context, hint: 'Paste thy notes here', box: true),
              ),
            if (_busy) ...[
              const SizedBox(height: 16),
              InlineMessage('The oracle studies thy notes$kEllipsis this can take up to a minute.'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              InlineMessage(_error!, isError: true),
            ],
            const SizedBox(height: 20),
            GoldButton(label: 'Create Quiz', busy: _busy, onPressed: () => _submit(app)),
          ],
        ),
      ),
    );
  }
}
