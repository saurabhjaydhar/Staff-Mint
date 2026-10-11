import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/core/widgets/common.dart';

class _TrackedController extends TextEditingController {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  testWidgets('controllers outlive the exit animation and are disposed once the dialog has closed', (tester) async {
    final ctrl = _TrackedController();
    String? typed;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final ok = await showDialogWithControllers<bool>(
                context,
                [ctrl],
                (ctx) => AlertDialog(
                  content: TextField(key: const Key('field'), controller: ctrl),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add'))],
                ),
              );
              if (ok == true) typed = ctrl.text;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field')), 'CA Gupta');
    await tester.tap(find.text('Add'));
    await tester.pump();

    // Mid exit animation: the value is readable and the field is still alive.
    expect(typed, 'CA Gupta');
    expect(ctrl.disposed, isFalse);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(ctrl.disposed, isTrue);
  });
}
