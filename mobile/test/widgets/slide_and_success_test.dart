import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/core/widgets/slide_to_confirm.dart';
import 'package:staffmint/core/widgets/success_screen.dart';

void main() {
  group('SlideToConfirm', () {
    late int confirmed;

    Future<void> pump(WidgetTester tester, {bool enabled = true}) async {
      confirmed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: SlideToConfirm(
                  label: 'Slide to approve & send payslips',
                  enabled: enabled,
                  onConfirmed: () => confirmed++,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('dragging the thumb to the end confirms once', (tester) async {
      await pump(tester);
      await tester.drag(find.byKey(const Key('slideThumb')), const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(confirmed, 1);
    });

    testWidgets('a half slide does not confirm and the thumb springs back', (tester) async {
      await pump(tester);
      final start = tester.getTopLeft(find.byKey(const Key('slideThumb')));
      await tester.drag(find.byKey(const Key('slideThumb')), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(confirmed, 0);
      expect(tester.getTopLeft(find.byKey(const Key('slideThumb'))), start);
    });

    testWidgets('long-press on the track is the accessible fallback', (tester) async {
      await pump(tester);
      await tester.longPress(find.text('Slide to approve & send payslips'));
      await tester.pumpAndSettle();
      expect(confirmed, 1);
    });

    testWidgets('disabled slider ignores drags', (tester) async {
      await pump(tester, enabled: false);
      await tester.drag(find.byKey(const Key('slideThumb')), const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(confirmed, 0);
    });
  });

  group('SuccessScreen', () {
    testWidgets('offline variant says saved offline and closes with Done', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSuccessScreen(
                  context,
                  title: 'Saved offline',
                  subtitle: 'Will sync when internet is back',
                  rows: const [('Selfie', '✔ saved')],
                  offline: true,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('successOffline')), findsOneWidget);
      expect(find.byKey(const Key('successOnline')), findsNothing);
      expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget);
      expect(find.text('Saved offline'), findsOneWidget);
      expect(find.text('✔ saved'), findsOneWidget);

      await tester.tap(find.byKey(const Key('successDone')));
      await tester.pumpAndSettle();
      expect(find.text('go'), findsOneWidget);
    });

    testWidgets('online variant shows the tick', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SuccessScreen(title: 'Checked in!')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('successOnline')), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });
}
