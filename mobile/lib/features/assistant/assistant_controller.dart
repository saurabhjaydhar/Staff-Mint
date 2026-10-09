import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import '../../core/models/models.dart';
import '../auth/auth_controller.dart';

class ChatMessage {
  ChatMessage.user(this.text, {this.isVoice = false, this.voiceDuration, this.transcript, DateTime? at})
    : fromUser = true,
      reply = null,
      resolved = false,
      error = null,
      at = at ?? DateTime.now();

  ChatMessage.assistant(AssistantReply this.reply, {this.resolved = false, DateTime? at})
    : fromUser = false,
      text = '',
      isVoice = false,
      voiceDuration = null,
      transcript = null,
      error = null,
      at = at ?? DateTime.now();

  ChatMessage.error(Object this.error)
    : fromUser = false,
      text = '',
      isVoice = false,
      voiceDuration = null,
      transcript = null,
      reply = null,
      resolved = true,
      at = DateTime.now();

  final bool fromUser;
  final String text;
  final bool isVoice;
  final Duration? voiceDuration;

  /// What Mint heard (voice notes), when the server reports it.
  final String? transcript;
  final AssistantReply? reply;

  /// For confirm/choose replies: true once the user acted on it.
  final bool resolved;
  final Object? error;
  final DateTime at;

  bool get needsAction => !resolved && reply != null && (reply!.kind == 'confirm' || reply!.kind == 'choose');

  ChatMessage resolve() => reply == null ? this : ChatMessage.assistant(reply!, resolved: true, at: at);

  ChatMessage withTranscript(String t) =>
      ChatMessage.user(text, isVoice: isVoice, voiceDuration: voiceDuration, transcript: t, at: at);
}

class AssistantState {
  const AssistantState({this.messages = const [], this.sessionId, this.sending = false});
  final List<ChatMessage> messages;
  final String? sessionId;
  final bool sending;

  AssistantState copyWith({List<ChatMessage>? messages, String? sessionId, bool? sending}) => AssistantState(
    messages: messages ?? this.messages,
    sessionId: sessionId ?? this.sessionId,
    sending: sending ?? this.sending,
  );
}

/// Mint chat. Keeps `sessionId` across messages; every write goes through
/// a server-side confirm step (`/assistant/confirm`).
class AssistantController extends Notifier<AssistantState> {
  @override
  AssistantState build() {
    // New user → new conversation.
    ref.watch(authControllerProvider.select((s) => s.user?.id));
    return const AssistantState();
  }

  void reset() => state = const AssistantState();

  Future<void> sendText(String text) async {
    final t = text.trim();
    if (t.isEmpty || state.sending) return;
    _push(ChatMessage.user(t));
    await _run(() => ref.read(assistantApiProvider).message(text: t, sessionId: state.sessionId));
  }

  Future<void> sendVoice(String audioBase64, String mime, String label, {Duration? duration}) async {
    if (state.sending) return;
    _push(ChatMessage.user(label, isVoice: true, voiceDuration: duration));
    await _run(
      () =>
          ref.read(assistantApiProvider).message(audioBase64: audioBase64, audioMime: mime, sessionId: state.sessionId),
    );
  }

  /// action: confirm | cancel | choose
  Future<void> act(int index, String action, {String? optionId, String? label}) async {
    if (index < 0 || index >= state.messages.length || state.sending) return;
    final msg = state.messages[index];
    final pendingId = msg.reply?.pendingActionId;
    if (pendingId == null) return;
    final updated = [...state.messages];
    updated[index] = msg.resolve();
    state = state.copyWith(messages: updated);
    if (label != null) _push(ChatMessage.user(label));
    await _run(
      () => ref.read(assistantApiProvider).confirm(pendingActionId: pendingId, action: action, optionId: optionId),
    );
  }

  Future<void> _run(Future<AssistantReply> Function() call) async {
    state = state.copyWith(sending: true);
    try {
      final reply = await call();
      final messages = [...state.messages];
      final heard = reply.transcript;
      if (heard != null && heard.isNotEmpty && messages.isNotEmpty && messages.last.isVoice) {
        messages[messages.length - 1] = messages.last.withTranscript(heard);
      }
      state = state.copyWith(
        messages: [...messages, ChatMessage.assistant(reply)],
        sessionId: reply.sessionId ?? state.sessionId,
        sending: false,
      );
    } catch (e) {
      state = state.copyWith(messages: [...state.messages, ChatMessage.error(e)], sending: false);
    }
  }

  void _push(ChatMessage m) => state = state.copyWith(messages: [...state.messages, m]);
}

final assistantControllerProvider = NotifierProvider<AssistantController, AssistantState>(AssistantController.new);
