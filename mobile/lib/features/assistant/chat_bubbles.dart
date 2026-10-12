import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/receipt.dart';
import 'assistant_controller.dart';

typedef ChatActCallback = void Function(String action, {String? optionId, String? label});

/// WhatsApp-style bubble: green outgoing with ✓✓, white incoming.
class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.outgoing, required this.child, required this.at, this.error = false});
  final bool outgoing;
  final Widget child;
  final DateTime at;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final bg = outgoing
        ? AppColors.outBubble
        : error
        ? AppColors.redLight
        : Colors.white;
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(outgoing ? 12 : 2),
            topRight: Radius.circular(outgoing ? 2 : 12),
            bottomLeft: const Radius.circular(12),
            bottomRight: const Radius.circular(12),
          ),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 1, offset: Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DefaultTextStyle.merge(style: const TextStyle(fontSize: 16, height: 1.35), child: child),
            _Stamp(at: at, ticks: outgoing),
          ],
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.at, required this.ticks});
  final DateTime at;
  final bool ticks;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Text(Dates.clock(at), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      if (ticks) ...[const SizedBox(width: 3), const Icon(Icons.done_all_rounded, size: 15, color: AppColors.mint)],
    ],
  );
}

/// Voice note: play icon + waveform bars + duration, transcript underneath.
class VoiceNoteBubble extends StatelessWidget {
  const VoiceNoteBubble({super.key, required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final d = message.voiceDuration ?? Duration.zero;
    final dur = '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    final seed = message.at.millisecondsSinceEpoch;
    return ChatBubble(
      outgoing: true,
      at: message.at,
      child: Semantics(
        label: '${context.s.voiceNote} $dur',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 22,
                    child: Row(
                      children: [
                        for (var i = 0; i < 26; i++)
                          Expanded(
                            child: Center(
                              child: Container(
                                width: 2.4,
                                height: 5 + ((seed >> (i % 16)) + i * 7) % 15,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF5AA874),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(dur, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
            if (message.transcript != null) ...[
              const SizedBox(height: 4),
              Text('“${message.transcript}”', style: const TextStyle(fontSize: 13.5, color: Color(0xFF4A6B4F))),
            ],
          ],
        ),
      ),
    );
  }
}

/// One message from the transcript.
class ChatMessageView extends StatelessWidget {
  const ChatMessageView({super.key, required this.message, required this.onAct});
  final ChatMessage message;
  final ChatActCallback onAct;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final m = message;
    if (m.fromUser) {
      if (m.isVoice) return VoiceNoteBubble(message: m);
      return ChatBubble(outgoing: true, at: m.at, child: Text(m.text));
    }
    if (m.error != null) {
      return ChatBubble(outgoing: false, error: true, at: m.at, child: Text(errorMessage(context, m.error!)));
    }
    if (m.isHelp) {
      return ChatBubble(
        outgoing: false,
        at: m.at,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(m.text),
            if (m.route != null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('mintHelpOpen'),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(m.routeLabel ?? s.openScreen),
                onPressed: () {
                  final router = GoRouter.of(context);
                  Navigator.of(context).maybePop();
                  router.push(m.route!);
                },
              ),
            ],
          ],
        ),
      );
    }
    final r = m.reply!;
    switch (r.kind) {
      case 'confirm':
        return ConfirmReceipt(reply: r, resolved: m.resolved, onAct: onAct);
      case 'choose':
        return ChatBubble(
          outgoing: false,
          at: m.at,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(r.text),
              const SizedBox(height: 8),
              for (final o in r.options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: AppColors.mintDark,
                      side: const BorderSide(color: AppColors.line, width: 1.5),
                    ),
                    onPressed: m.resolved ? null : () => onAct('choose', optionId: o.id, label: o.label),
                    child: Text(o.label),
                  ),
                ),
              if (!m.resolved)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.muted),
                  onPressed: () => onAct('cancel', label: s.cancel),
                  child: Text(s.cancel),
                ),
            ],
          ),
        );
      case 'error':
        return ChatBubble(outgoing: false, error: true, at: m.at, child: Text(r.text));
      case 'cancelled':
        return ChatBubble(
          outgoing: false,
          at: m.at,
          child: Text(r.text.isEmpty ? s.actionCancelled : r.text, style: const TextStyle(color: AppColors.muted)),
        );
      default: // answer | done
        return ChatBubble(
          outgoing: false,
          at: m.at,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (r.kind == 'done')
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2, right: 6),
                      child: Icon(Icons.check_circle_rounded, color: AppColors.mint, size: 18),
                    ),
                    Flexible(child: SelectableText(r.text)),
                  ],
                )
              else
                SelectableText(r.text),
              if (r.attachment != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
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

/// Confirm reply as a receipt: "📝 title", label/value rows, "नहीं | ✓ हाँ, कर दो".
class ConfirmReceipt extends StatelessWidget {
  const ConfirmReceipt({super.key, required this.reply, required this.resolved, required this.onAct});
  final AssistantReply reply;
  final bool resolved;
  final ChatActCallback onAct;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = reply.preview;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const Key('confirmReceipt'),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.84),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 1, offset: Offset(0, 1))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: AppColors.mintLight,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1, right: 6),
                    child: Icon(Icons.edit_note_rounded, color: AppColors.mintDark, size: 20),
                  ),
                  Expanded(
                    child: Text(
                      p?.title ?? reply.text,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.mintDark),
                    ),
                  ),
                ],
              ),
            ),
            // The API text repeats the preview rows (it is meant for WhatsApp), so it is shown only without a preview.
            if (p != null && p.rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
                child: Column(
                  children: [
                    for (var i = 0; i < p.rows.length; i++)
                      ReceiptRow(label: p.rows[i].label, value: p.rows[i].value, divider: i > 0),
                  ],
                ),
              ),
            const Divider(),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.muted,
                        shape: const RoundedRectangleBorder(),
                      ),
                      onPressed: resolved ? null : () => onAct('cancel', label: s.confirmNo),
                      child: Text(s.confirmNo),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: TextButton.icon(
                      key: const Key('confirmYes'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.mint,
                        shape: const RoundedRectangleBorder(),
                      ),
                      onPressed: resolved ? null : () => onAct('confirm', label: s.confirmYes),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(s.confirmYes),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
