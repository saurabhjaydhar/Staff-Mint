import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/core/api/api_exception.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/misc_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/features/assistant/assistant_controller.dart';
import 'package:staffmint/features/auth/auth_controller.dart';
import 'package:staffmint/features/auth/session_state.dart';

class _FakeAuth extends AuthController {
  @override
  SessionState build() => const SessionState(
    status: SessionStatus.authenticated,
    user: User(id: 'u1', phone: '9876543210', name: 'Owner', role: UserRole.owner, companyId: 'c1'),
  );
}

class _FakeAssistantApi implements AssistantApi {
  final List<Map<String, Object?>> calls = [];
  bool fail = false;

  @override
  Future<AssistantReply> message({String? text, String? audioBase64, String? audioMime, String? sessionId}) async {
    calls.add({'text': text, 'audio': audioBase64, 'mime': audioMime, 'sessionId': sessionId});
    if (fail) throw ApiException.network();
    if (text == 'Ramesh ko aaj half day laga do') {
      return const AssistantReply(
        sessionId: 's-1',
        kind: 'confirm',
        text: 'Confirm?',
        pendingActionId: 'pa-1',
        preview: AssistantPreview(
          title: 'Mark attendance',
          rows: [AssistantPreviewRow(label: 'Status', value: 'Half day')],
        ),
      );
    }
    return const AssistantReply(sessionId: 's-1', kind: 'answer', text: '2 staff late today');
  }

  @override
  Future<AssistantReply> confirm({required String pendingActionId, required String action, String? optionId}) async {
    calls.add({'pendingActionId': pendingActionId, 'action': action, 'optionId': optionId});
    return const AssistantReply(sessionId: 's-1', kind: 'done', text: 'Done');
  }
}

void main() {
  late _FakeAssistantApi api;
  late ProviderContainer container;

  setUp(() {
    api = _FakeAssistantApi();
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [assistantApiProvider.overrideWithValue(api), authControllerProvider.overrideWith(_FakeAuth.new)],
    );
  });

  tearDown(() => container.dispose());

  AssistantController ctrl() => container.read(assistantControllerProvider.notifier);
  AssistantState state() => container.read(assistantControllerProvider);

  test('keeps sessionId across messages', () async {
    await ctrl().sendText('Kaun late aaya?');
    await ctrl().sendText('Kal kaun absent tha?');
    expect(api.calls[0]['sessionId'], isNull);
    expect(api.calls[1]['sessionId'], 's-1');
    expect(state().messages, hasLength(4));
    expect(state().messages.last.reply!.text, '2 staff late today');
  });

  test('confirm card resolves once and calls /assistant/confirm', () async {
    await ctrl().sendText('Ramesh ko aaj half day laga do');
    final idx = state().messages.indexWhere((m) => m.reply?.kind == 'confirm');
    expect(state().messages[idx].needsAction, isTrue);

    await ctrl().act(idx, 'confirm', label: 'Confirm');

    expect(api.calls.last, {'pendingActionId': 'pa-1', 'action': 'confirm', 'optionId': null});
    expect(state().messages[idx].needsAction, isFalse);
    expect(state().messages.last.reply!.kind, 'done');

    // A second tap on the resolved card is ignored by the UI; calling again
    // would re-send, so the card must report it no longer needs action.
    expect(state().messages[idx].resolved, isTrue);
  });

  test('voice messages send base64 audio with mime type', () async {
    await ctrl().sendVoice('AAAA', 'audio/mp4', 'Voice message');
    expect(api.calls.single['audio'], 'AAAA');
    expect(api.calls.single['mime'], 'audio/mp4');
    expect(state().messages.first.isVoice, isTrue);
  });

  test('errors become an error bubble and sending resets', () async {
    api.fail = true;
    await ctrl().sendText('hello');
    expect(state().sending, isFalse);
    expect(state().messages.last.error, isA<ApiException>());
  });

  test('reset clears the conversation', () async {
    await ctrl().sendText('Kaun late aaya?');
    ctrl().reset();
    expect(state().messages, isEmpty);
    expect(state().sessionId, isNull);
  });
}
