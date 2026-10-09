import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/features/assistant/assistant_controller.dart';
import 'package:staffmint/features/assistant/chat_bubbles.dart';

void main() {
  Future<void> pump(WidgetTester tester, ChatMessage m, {ChatActCallback? onAct}) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatMessageView(message: m, onAct: onAct ?? (_, {optionId, label}) {}),
      ),
    ),
  );

  testWidgets('confirm reply renders as a receipt (no duplicated reply text) with Yes / No', (tester) async {
    final acts = <String>[];
    await pump(
      tester,
      ChatMessage.assistant(
        const AssistantReply(
          sessionId: 's1',
          kind: 'confirm',
          text: 'Mark attendance?\nStaff: Suresh Yadav\nStatus: Absent',
          pendingActionId: 'pa-1',
          preview: AssistantPreview(
            title: 'Mark attendance?',
            rows: [
              AssistantPreviewRow(label: 'Staff', value: 'Suresh Yadav'),
              AssistantPreviewRow(label: 'Status', value: 'Absent'),
            ],
          ),
        ),
      ),
      onAct: (action, {optionId, label}) => acts.add(action),
    );
    expect(find.byKey(const Key('confirmReceipt')), findsOneWidget);
    expect(find.text('Mark attendance?'), findsOneWidget);
    expect(find.text('Suresh Yadav'), findsOneWidget);
    expect(find.textContaining('Staff: Suresh Yadav'), findsNothing);
    await tester.tap(find.byKey(const Key('confirmYes')));
    expect(acts, ['confirm']);
  });

  testWidgets('voice note bubble shows duration and the transcript when known', (tester) async {
    await pump(
      tester,
      ChatMessage.user(
        'Voice note',
        isVoice: true,
        voiceDuration: const Duration(seconds: 3),
        transcript: 'Suresh aaj nahi aaya',
      ),
    );
    expect(find.text('0:03'), findsOneWidget);
    expect(find.text('“Suresh aaj nahi aaya”'), findsOneWidget);
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
  });
}
