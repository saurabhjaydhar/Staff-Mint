import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import 'assistant_controller.dart';

/// Mint chat: text + hold-to-record voice, confirm cards, option chips.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  AudioRecorder? _recorder;
  bool _recording = false;
  bool _pressing = false;
  String? _recordPath;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _recorder?.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send([String? text]) async {
    final t = text ?? _input.text;
    if (t.trim().isEmpty) return;
    _input.clear();
    _scrollToEnd();
    await ref.read(assistantControllerProvider.notifier).sendText(t);
    _scrollToEnd();
  }

  Future<void> _startRecording() async {
    final s = context.s;
    try {
      _recorder ??= AudioRecorder();
      if (!await _recorder!.hasPermission()) {
        if (mounted) showSnack(context, s.micPermissionDenied, error: true);
        return;
      }
      final dir = await getTemporaryDirectory();
      _recordPath = '${dir.path}/mint_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder!.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 16000, numChannels: 1),
        path: _recordPath!,
      );
      if (!_pressing) {
        // Finger lifted while we were starting (e.g. permission prompt).
        await _recorder!.cancel();
        return;
      }
      if (mounted) setState(() => _recording = true);
    } catch (_) {
      if (mounted) showSnack(context, s.micPermissionDenied, error: true);
    }
  }

  Future<void> _stopRecording({bool cancel = false}) async {
    if (!_recording) return;
    setState(() => _recording = false);
    final s = context.s;
    try {
      final path = await _recorder?.stop() ?? _recordPath;
      if (path == null) return;
      final file = File(path);
      if (cancel || !await file.exists()) return;
      final bytes = await file.readAsBytes();
      await file.delete().catchError((_) => file);
      if (bytes.length < 2000) return; // too short — accidental tap
      _scrollToEnd();
      await ref.read(assistantControllerProvider.notifier).sendVoice(base64Encode(bytes), 'audio/mp4', s.voiceMessage);
      _scrollToEnd();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final state = ref.watch(assistantControllerProvider);
    final ctrl = ref.read(assistantControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: AppColors.mint,
              child: Icon(Icons.auto_awesome_rounded, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(s.mintTitle, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [IconButton(tooltip: s.newChat, icon: const Icon(Icons.refresh_rounded), onPressed: ctrl.reset)],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              children: [
                _Bubble(fromUser: false, child: Text(s.mintWelcome, style: const TextStyle(fontSize: 17))),
                if (state.messages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final q in s.mintSuggestions)
                          ActionChip(
                            avatar: const Icon(Icons.bolt_rounded, size: 18, color: AppColors.mintDark),
                            label: Text(q),
                            onPressed: () => _send(q),
                          ),
                      ],
                    ),
                  ),
                for (var i = 0; i < state.messages.length; i++)
                  _MessageView(
                    message: state.messages[i],
                    onAct: (action, {optionId, label}) => ctrl.act(i, action, optionId: optionId, label: label),
                  ),
                if (state.sending)
                  _Bubble(
                    fromUser: false,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 10),
                        Text(s.mintThinking),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_recording)
            Container(
              width: double.infinity,
              color: AppColors.absent.withValues(alpha: 0.1),
              padding: const EdgeInsets.all(10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.fiber_manual_record, color: AppColors.absent),
                  const SizedBox(width: 6),
                  Text(s.listening, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(hintText: s.typeMessage),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _input,
                    builder: (_, v, _) => v.text.trim().isNotEmpty
                        ? IconButton.filled(
                            iconSize: 28,
                            onPressed: state.sending ? null : () => _send(),
                            icon: const Icon(Icons.send_rounded),
                          )
                        : Semantics(
                            button: true,
                            label: s.holdToTalk,
                            child: GestureDetector(
                              onLongPressStart: state.sending
                                  ? null
                                  : (_) {
                                      _pressing = true;
                                      _startRecording();
                                    },
                              onLongPressEnd: (_) {
                                _pressing = false;
                                _stopRecording();
                              },
                              onTap: () => showSnack(context, s.holdToTalk),
                              child: CircleAvatar(
                                radius: 26,
                                backgroundColor: _recording ? AppColors.absent : AppColors.mint,
                                child: const Icon(Icons.mic_rounded, color: Colors.white, size: 28),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _ActCallback = void Function(String action, {String? optionId, String? label});

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, required this.onAct});
  final ChatMessage message;
  final _ActCallback onAct;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (message.fromUser) {
      return _Bubble(
        fromUser: true,
        child: Text(message.text, style: const TextStyle(color: Colors.white, fontSize: 17)),
      );
    }
    if (message.error != null) {
      return _Bubble(
        fromUser: false,
        error: true,
        child: Text(errorMessage(context, message.error!), style: const TextStyle(fontSize: 16)),
      );
    }
    final r = message.reply!;
    switch (r.kind) {
      case 'confirm':
        return _ConfirmCard(reply: r, resolved: message.resolved, onAct: onAct);
      case 'choose':
        return _Bubble(
          fromUser: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.text, style: const TextStyle(fontSize: 17)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in r.options)
                    ActionChip(
                      label: Text(o.label),
                      onPressed: message.resolved ? null : () => onAct('choose', optionId: o.id, label: o.label),
                    ),
                ],
              ),
              if (!message.resolved)
                TextButton(
                  onPressed: () => onAct('cancel', label: s.cancel),
                  child: Text(s.cancel),
                ),
            ],
          ),
        );
      case 'error':
        return _Bubble(fromUser: false, error: true, child: Text(r.text, style: const TextStyle(fontSize: 17)));
      case 'cancelled':
        return _Bubble(
          fromUser: false,
          child: Text(
            r.text.isEmpty ? s.actionCancelled : r.text,
            style: const TextStyle(fontSize: 17, color: Colors.black54),
          ),
        );
      default: // answer | done
        return _Bubble(
          fromUser: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r.kind == 'done')
                    const Padding(
                      padding: EdgeInsets.only(right: 6, top: 2),
                      child: Icon(Icons.check_circle_rounded, color: AppColors.mint, size: 20),
                    ),
                  Flexible(child: SelectableText(r.text, style: const TextStyle(fontSize: 17))),
                ],
              ),
              if (r.attachment != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => openUrl(context, r.attachment!.url),
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text('${s.openAttachment}: ${r.attachment!.filename}', overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
        );
    }
  }
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({required this.reply, required this.resolved, required this.onAct});
  final AssistantReply reply;
  final bool resolved;
  final _ActCallback onAct;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = reply.preview;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.mint, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (reply.text.isNotEmpty) Text(reply.text, style: const TextStyle(fontSize: 17)),
                if (p != null) ...[
                  const SizedBox(height: 8),
                  Text(p.title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  for (final row in p.rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(row.label, style: const TextStyle(color: Colors.black54)),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(row.value, style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: resolved ? null : () => onAct('cancel', label: s.cancel),
                        child: Text(s.cancel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: resolved ? null : () => onAct('confirm', label: s.confirm),
                        child: Text(s.confirm),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.fromUser, required this.child, this.error = false});
  final bool fromUser;
  final Widget child;
  final bool error;

  @override
  Widget build(BuildContext context) => Align(
    alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: fromUser
            ? AppColors.mint
            : error
            ? AppColors.absent.withValues(alpha: 0.1)
            : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(fromUser ? 18 : 4),
          bottomRight: Radius.circular(fromUser ? 4 : 18),
        ),
        border: fromUser ? null : Border.all(color: const Color(0xFFE3E8E5)),
      ),
      child: child,
    ),
  );
}
