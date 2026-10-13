import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/verification_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/features/documents/documents.dart';

const _raju = Employee(id: 'e1', name: 'Raju', phone: '9876543210');

// 1×1 PNG.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

class _FakePicker implements DocPicker {
  int picked = 0;
  @override
  Future<DocFile?> pick(ImageSource source) async {
    picked++;
    return const DocFile(data: _png, mime: 'image/png');
  }
}

class _FakeApi implements VerificationApi {
  StaffDocs docs = const StaffDocs();
  final calls = <String>[];
  Map<String, Object?>? lastAdd;
  OpenedDoc opened = const OpenedDoc();

  @override
  Future<StaffDocs> documentsFor(String employeeId) async => docs;
  @override
  Future<StaffDocs> myDocuments() async => docs;

  @override
  Future<StaffDoc> addDocument({
    String? employeeId,
    required String kind,
    String? label,
    String? number,
    String? expiresOn,
    required List<DocFile> files,
    bool staffAgreed = false,
    DocFile? slip,
  }) async {
    lastAdd = {
      'employeeId': employeeId,
      'kind': kind,
      'label': label,
      'number': number,
      'files': files.length,
      'staffAgreed': staffAgreed,
      'slip': slip != null,
    };
    calls.add('add:$kind');
    return StaffDoc(id: 'new', kind: kind);
  }

  @override
  Future<OpenedDoc> openDocument(String id) async {
    calls.add('open:$id');
    return opened;
  }

  @override
  Future<void> removeDocument(String id) async => calls.add('remove:$id');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _FakeApi api, Widget child, {String lang = 'en', DocPicker? picker}) async {
  SharedPreferences.setMockInitialValues({'sm_language': lang});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        verificationApiProvider.overrideWithValue(api),
        docPickerProvider.overrideWithValue(picker ?? _FakePicker()),
      ],
      child: MaterialApp(
        locale: Locale(lang),
        supportedLocales: const [Locale('en'), Locale('hi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _addPhoto(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('docGallery')));
  await tester.pumpAndSettle();
}

bool _saveEnabled(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const Key('docSave'))).onPressed != null;

void main() {
  testWidgets('owner adds a document for staff without the app: photo, "they agreed", signed slip the first time', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(tester, api, const Scaffold(body: SingleChildScrollView(child: DocumentsCard(employee: _raju))));
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Keep copies of Aadhaar, PAN, licence and more, safely in one place.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('docAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('docKind_pan')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('docNumber')), 'abcde1234f');
    expect(_saveEnabled(tester), isFalse);
    await _addPhoto(tester, 'docAddPhoto');
    expect(find.byKey(const Key('docThumb_0')), findsOneWidget);
    // Still needs their agreement, and the slip.
    expect(_saveEnabled(tester), isFalse);
    await tester.ensureVisible(find.byKey(const Key('docAgreed')));
    await tester.tap(find.byKey(const Key('docAgreed')));
    await tester.pumpAndSettle();
    expect(find.text('Raju agreed to me keeping a copy'), findsOneWidget);
    expect(find.text('Photo of the signed consent slip'), findsOneWidget);
    expect(_saveEnabled(tester), isFalse);
    await _addPhoto(tester, 'docAddSlip');
    expect(_saveEnabled(tester), isTrue);
    await tester.ensureVisible(find.byKey(const Key('docSave')));
    await tester.tap(find.byKey(const Key('docSave')));
    await tester.pumpAndSettle();
    expect(api.lastAdd, {
      'employeeId': 'e1',
      'kind': 'pan',
      'label': null,
      'number': 'abcde1234f',
      'files': 1,
      'staffAgreed': true,
      'slip': true,
    });
    expect(find.text('Document saved'), findsOneWidget);
  });

  testWidgets('owner: list with expiry; a slip already on file isn’t asked again', (tester) async {
    final api = _FakeApi()
      ..docs = const StaffDocs(
        agreementOnFile: true,
        documents: [
          StaffDoc(
            id: 'd1',
            kind: 'dl',
            mimes: ['image/jpeg', 'image/jpeg'],
            expiresOn: '2026-10-30',
            expiry: 'soon',
          ),
          StaffDoc(id: 'd2', kind: 'pan', numberLast4: '234F', mimes: ['image/jpeg'], addedBy: 'owner', hasSlip: true),
          StaffDoc(id: 'd3', kind: 'other', label: '10th marksheet', mimes: ['application/pdf']),
        ],
      );
    await _pump(tester, api, const Scaffold(body: SingleChildScrollView(child: DocumentsCard(employee: _raju))));
    expect(find.text('Driving licence'), findsOneWidget);
    expect(find.textContaining('2 pages · Added by staff'), findsOneWidget);
    expect(find.textContaining('Expires 30 Oct 2026'), findsOneWidget);
    expect(find.textContaining('ending 234F · 1 page · Added by you'), findsOneWidget);
    expect(find.text('10th marksheet'), findsOneWidget);
    expect(find.textContaining('PDF · Added by staff'), findsOneWidget);

    await tester.tap(find.byKey(const Key('docAdd')));
    await tester.pumpAndSettle();
    await _addPhoto(tester, 'docAddPhoto');
    await tester.ensureVisible(find.byKey(const Key('docAgreed')));
    await tester.tap(find.byKey(const Key('docAgreed')));
    await tester.pumpAndSettle();
    expect(find.text('Photo of the signed consent slip'), findsNothing);
    expect(_saveEnabled(tester), isTrue);
  });

  testWidgets('owner opens a document: the files and the signed slip', (tester) async {
    final api = _FakeApi()
      ..docs = const StaffDocs(
        documents: [StaffDoc(id: 'd3', kind: 'police', mimes: ['application/pdf'], addedBy: 'owner', hasSlip: true)],
      )
      ..opened = const OpenedDoc(
        files: [(url: 'http://x/doc-files/a', mime: 'application/pdf')],
        slip: (url: 'http://x/doc-files/b', mime: 'application/pdf'),
      );
    await _pump(tester, api, const Scaffold(body: SingleChildScrollView(child: DocumentsCard(employee: _raju))));
    await tester.tap(find.byKey(const Key('doc_d3')));
    await tester.pumpAndSettle();
    expect(api.calls, ['open:d3']);
    expect(find.text('Police verification'), findsWidgets);
    expect(find.text('Open PDF'), findsNWidgets(2));
    expect(find.text('Signed consent slip'), findsOneWidget);
    // No date yet on a police certificate: the owner can add one.
    expect(find.byKey(const Key('docChangeDate')), findsOneWidget);
    expect(find.byKey(const Key('docRemove')), findsOneWidget);
  });

  testWidgets('staff: My documents, add their Aadhaar, remove only what they added', (tester) async {
    final api = _FakeApi()
      ..docs = const StaffDocs(
        documents: [
          StaffDoc(id: 'mine', kind: 'aadhaar', numberLast4: '1234', mimes: ['image/jpeg']),
          StaffDoc(id: 'boss', kind: 'pan', mimes: ['image/jpeg'], addedBy: 'owner'),
        ],
      )
      ..opened = const OpenedDoc(files: [(url: 'http://x/doc-files/a', mime: 'application/pdf')]);
    await _pump(tester, api, const MyDocumentsScreen());
    expect(find.text('My documents'), findsOneWidget);
    expect(find.textContaining('Added by'), findsNothing);

    await tester.tap(find.byKey(const Key('docAdd')));
    await tester.pumpAndSettle();
    expect(find.textContaining('masked Aadhaar'), findsOneWidget);
    expect(find.byKey(const Key('docAgreed')), findsNothing);
    await tester.enterText(find.byKey(const Key('docNumber')), '1234');
    await _addPhoto(tester, 'docAddPhoto');
    await tester.ensureVisible(find.byKey(const Key('docSave')));
    await tester.tap(find.byKey(const Key('docSave')));
    await tester.pumpAndSettle();
    expect(api.lastAdd, containsPair('employeeId', null));
    expect(api.lastAdd, containsPair('kind', 'aadhaar'));

    await tester.tap(find.byKey(const Key('doc_boss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('docRemove')), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('doc_mine')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('docRemove')));
    await tester.pumpAndSettle();
    expect(find.text('Remove Aadhaar?'), findsOneWidget);
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    expect(api.calls, ['add:aadhaar', 'open:boss', 'open:mine', 'remove:mine']);
    expect(find.text('Document removed'), findsOneWidget);
  });

  testWidgets('Hindi', (tester) async {
    await _pump(
      tester,
      _FakeApi(),
      const Scaffold(body: SingleChildScrollView(child: DocumentsCard(employee: _raju))),
      lang: 'hi',
    );
    expect(find.text('दस्तावेज़'), findsOneWidget);
    await tester.tap(find.byKey(const Key('docAdd')));
    await tester.pumpAndSettle();
    expect(find.text('कौन-सा दस्तावेज़?'), findsOneWidget);
    expect(find.text('ड्राइविंग लाइसेंस'), findsOneWidget);
  });
}
