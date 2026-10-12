import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_controller.dart';
import 'assistant_controller.dart';
import 'chat_bubbles.dart';
import 'mint_help.dart';
import 'voice_recorder.dart';

/// Opens Mint as a draggable sheet over the current screen (no page change).
Future<void> showMintSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: Colors.transparent,
  builder: (ctx) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.9,
    minChildSize: 0.5,
    maxChildSize: 1,
    builder: (ctx, controller) => ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: MintChat(scrollController: controller),
    ),
  ),
);

/// WhatsApp-style Mint chat: wallpaper, bubbles, voice notes, receipts.
class MintChat extends ConsumerStatefulWidget {
  const MintChat({super.key, this.scrollController});
  final ScrollController? scrollController;

  @override
  ConsumerState<MintChat> createState() => _MintChatState();
}

class _MintChatState extends ConsumerState<MintChat> {
  final _input = TextEditingController();
  final _voice = VoiceRecorder();
  late final ScrollController _scroll = widget.scrollController ?? ScrollController();
  bool _recording = false;

  @override
  void dispose() {
    _input.dispose();
    _voice.dispose();
    if (widget.scrollController == null) _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 240,
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
    final s = context.s;
    final owner = ref.read(authControllerProvider).isOwner;
    await ref
        .read(assistantControllerProvider.notifier)
        .sendText(t, localHelp: owner ? (q) => mintHelpFor(s, q) : null);
    _scrollToEnd();
  }

  Future<void> _holdStart() async {
    final ok = await _voice.press();
    if (!mounted) return;
    if (!ok) {
      showSnack(context, context.s.micPermissionDenied, error: true);
      return;
    }
    setState(() => _recording = _voice.isRecording);
  }

  Future<void> _holdEnd() async {
    final label = context.s.voiceNote;
    setState(() => _recording = false);
    try {
      final clip = await _voice.release();
      if (clip == null) return;
      _scrollToEnd();
      await ref
          .read(assistantControllerProvider.notifier)
          .sendVoice(clip.base64, clip.mime, label, duration: clip.duration);
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
    ref.listen(assistantControllerProvider.select((v) => v.messages.length), (_, _) => _scrollToEnd());
    return Material(
      color: AppColors.chatBg,
      child: Column(
        children: [
          _Header(onClose: () => Navigator.of(context).maybePop(), onReset: ctrl.reset),
          Expanded(
            child: CustomPaint(
              painter: const _WallpaperPainter(),
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                children: [
                  if (state.messages.isEmpty)
                    ChatBubble(
                      outgoing: false,
                      at: DateTime.now(),
                      child: Column(
                        key: const Key('mintExamples'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.mintIntro),
                          const SizedBox(height: 6),
                          for (final ex in s.mintExamples)
                            InkWell(
                              onTap: state.sending ? null : () => _send(ex),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                child: Text(
                                  '“$ex”',
                                  style: const TextStyle(color: AppColors.mintDark, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  else
                    ChatBubble(outgoing: false, at: DateTime.now(), child: Text(s.mintWelcome)),
                  for (var i = 0; i < state.messages.length; i++)
                    ChatMessageView(
                      message: state.messages[i],
                      onAct: (action, {optionId, label}) => ctrl.act(i, action, optionId: optionId, label: label),
                    ),
                  if (state.sending)
                    ChatBubble(
                      outgoing: false,
                      at: DateTime.now(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Text(s.mintThinking, style: const TextStyle(color: AppColors.muted)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_recording) _RecordingBanner(text: s.listening),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
            child: Wrap(
              key: const Key('mintChips'),
              spacing: 6,
              runSpacing: 0,
              children: [
                for (final (label, query) in s.mintSuggestionChips)
                  ActionChip(
                    label: Text(label),
                    labelStyle: const TextStyle(color: AppColors.mintDark, fontWeight: FontWeight.w700, fontSize: 13.5),
                    side: const BorderSide(color: Color(0xFFCDEBDB)),
                    backgroundColor: Colors.white,
                    onPressed: state.sending ? null : () => _send(query),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, 2, 8, 8 + MediaQuery.viewInsetsOf(context).bottom),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('mintInput'),
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: s.mintInputHint,
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                          borderSide: BorderSide(color: AppColors.mint, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _input,
                    builder: (_, v, _) => v.text.trim().isNotEmpty
                        ? _RoundButton(
                            icon: Icons.send_rounded,
                            semantic: s.typeMessage,
                            onTap: state.sending ? null : () => _send(),
                          )
                        : Semantics(
                            button: true,
                            label: s.holdToTalk,
                            excludeSemantics: true,
                            child: GestureDetector(
                              onLongPressStart: state.sending ? null : (_) => _holdStart(),
                              onLongPressEnd: (_) => _holdEnd(),
                              onTap: () => showSnack(context, s.holdToTalk),
                              child: _RoundButton(icon: Icons.mic_rounded, recording: _recording),
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

class _Header extends StatelessWidget {
  const _Header({required this.onClose, required this.onReset});
  final VoidCallback onClose;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Container(
      color: AppColors.ink,
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: s.close,
            onPressed: onClose,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.mint,
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, height: 1.1),
                ),
                Text(s.mintSubtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12.5)),
              ],
            ),
          ),
          IconButton(
            tooltip: s.newChat,
            onPressed: onReset,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _RecordingBanner extends StatelessWidget {
  const _RecordingBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: AppColors.redLight,
    padding: const EdgeInsets.all(10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.fiber_manual_record, color: AppColors.red, size: 16),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, this.onTap, this.recording = false, this.semantic});
  final IconData icon;
  final VoidCallback? onTap;
  final bool recording;
  final String? semantic;

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(color: recording ? AppColors.red : AppColors.mint, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 24),
    );
    if (onTap == null && semantic == null) return circle;
    return Semantics(
      button: true,
      label: semantic,
      child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: circle),
    );
  }
}

/// Faint dot pattern like a chat wallpaper; painted once, cheap.
class _WallpaperPainter extends CustomPainter {
  const _WallpaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AppColors.chatDots.withValues(alpha: 0.55);
    for (var y = 0.0; y < size.height; y += 60) {
      for (var x = 0.0; x < size.width; x += 60) {
        canvas.drawCircle(Offset(x + 8, y + 8), 2, p);
        canvas.drawCircle(Offset(x + 38, y + 26), 1.6, p);
        canvas.drawRect(Rect.fromLTWH(x + 20, y + 44, 6, 2), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
