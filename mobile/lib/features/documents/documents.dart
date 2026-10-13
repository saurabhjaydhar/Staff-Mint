import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/providers.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/common.dart';

final ownerDocumentsProvider = FutureProvider.autoDispose.family<StaffDocs, String>(
  (ref, employeeId) => ref.watch(verificationApiProvider).documentsFor(employeeId),
);
final myDocumentsProvider = FutureProvider.autoDispose<StaffDocs>(
  (ref) => ref.watch(verificationApiProvider).myDocuments(),
);

const documentKinds = [
  'aadhaar',
  'pan',
  'dl',
  'voter',
  'passport',
  'bank_proof',
  'address',
  'police',
  'experience',
  'other',
];

/// Documents that run out; we ask for the date and remind 30 days before.
const expiringKinds = {'dl', 'passport', 'police'};

const _kindIcons = {
  'aadhaar': Icons.fingerprint_rounded,
  'pan': Icons.credit_card_rounded,
  'dl': Icons.directions_car_rounded,
  'voter': Icons.how_to_vote_rounded,
  'passport': Icons.travel_explore_rounded,
  'bank_proof': Icons.account_balance_rounded,
  'address': Icons.home_rounded,
  'police': Icons.local_police_rounded,
  'experience': Icons.work_history_rounded,
};

/// Picks a document photo; faked in widget tests.
abstract class DocPicker {
  /// A JPEG (up to ~1600 px) or null when cancelled.
  Future<DocFile?> pick(ImageSource source);
}

class DeviceDocPicker implements DocPicker {
  @override
  Future<DocFile?> pick(ImageSource source) async {
    final f = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
      requestFullMetadata: false,
    );
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    final png = bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50;
    return DocFile(data: base64Encode(bytes), mime: png ? 'image/png' : 'image/jpeg');
  }
}

final docPickerProvider = Provider<DocPicker>((ref) => DeviceDocPicker());

String docName(S s, StaffDoc d) => d.kind == 'other' && (d.label ?? '').isNotEmpty ? d.label! : s.fileKind(d.kind);

/// "ending 234F · 2 pages · Added by staff", and the expiry line with its colour.
(String, (String, Color)?) docLines(S s, StaffDoc d, {required bool owner}) {
  final first = [
    if (d.numberLast4 != null) s.endingWith(d.numberLast4!),
    if (d.isPdf) 'PDF' else s.pagesCount(d.pages),
    if (owner) d.addedBy == 'owner' ? s.addedByYou : s.addedByStaff,
  ].join(' · ');
  final date = d.expiresOn == null ? null : Dates.prettyApiDate(d.expiresOn!, s.languageCode);
  final expiry = switch (d.expiry) {
    'expired' => (s.expiredOn(date!), AppColors.red),
    'soon' => (s.expiresSoon(date!), AppColors.amberDark),
    'ok' => (s.validTillDate(date!), AppColors.muted),
    _ => null,
  };
  return (first, expiry);
}

class DocTile extends StatelessWidget {
  const DocTile({super.key, required this.doc, required this.owner, required this.onTap});
  final StaffDoc doc;
  final bool owner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final (line, expiry) = docLines(s, doc, owner: owner);
    return ListTile(
      key: Key('doc_${doc.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: AppColors.mintFaint,
        child: Icon(_kindIcons[doc.kind] ?? Icons.description_rounded, color: AppColors.mintDark),
      ),
      title: Text(docName(s, doc), style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: line),
            if (expiry != null)
              TextSpan(
                text: '\n${expiry.$1}',
                style: TextStyle(color: expiry.$2, fontWeight: doc.expiry == 'ok' ? null : FontWeight.w700),
              ),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

/// Staff profile (owner only): the person's documents, and "Add document" on their behalf.
class DocumentsCard extends ConsumerWidget {
  const DocumentsCard({super.key, required this.employee});
  final Employee employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final docs = ref.watch(ownerDocumentsProvider(employee.id)).value;
    if (docs == null) return const SizedBox.shrink();
    void reload() => ref.invalidate(ownerDocumentsProvider(employee.id));

    return Card(
      key: const Key('docsCard'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_shared_rounded, color: AppColors.mintDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(s.documentsTitle, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                TextButton.icon(
                  key: const Key('docAdd'),
                  onPressed: () async {
                    if (await showAddDocumentSheet(
                      context,
                      employee: employee,
                      agreementOnFile: docs.agreementOnFile,
                    )) {
                      reload();
                    }
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(s.addDocument),
                ),
              ],
            ),
            if (docs.documents.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(s.noDocumentsHint, style: const TextStyle(color: AppColors.muted)),
              ),
            for (final d in docs.documents)
              DocTile(
                doc: d,
                owner: true,
                onTap: () async {
                  final changed = await openDocumentViewer(context, d, owner: true);
                  if (changed) reload();
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Staff: their own documents (Profile → My documents).
class MyDocumentsScreen extends ConsumerWidget {
  const MyDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final docs = ref.watch(myDocumentsProvider);
    Future<void> add() async {
      if (await showAddDocumentSheet(context)) ref.invalidate(myDocumentsProvider);
    }

    return Scaffold(
      appBar: AppBar(title: Text(s.myDocuments)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('docAdd'),
        onPressed: add,
        icon: const Icon(Icons.add_rounded),
        label: Text(s.addDocument),
      ),
      body: AsyncBody<StaffDocs>(
        value: docs,
        onRetry: () => ref.invalidate(myDocumentsProvider),
        data: (d) => RefreshableList(
          onRefresh: () => ref.refresh(myDocumentsProvider.future),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Text(s.myDocumentsHint, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 8),
            if (d.documents.isEmpty)
              EmptyView(icon: Icons.folder_shared_rounded, message: '${s.noDocuments}\n${s.noDocumentsHint}')
            else
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Column(
                    children: [
                      for (final x in d.documents)
                        DocTile(
                          doc: x,
                          owner: false,
                          onTap: () async {
                            if (await openDocumentViewer(context, x, owner: false)) {
                              ref.invalidate(myDocumentsProvider);
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- add

/// [employee] set: the owner adds it for them. Returns true when saved.
Future<bool> showAddDocumentSheet(BuildContext context, {Employee? employee, bool agreementOnFile = true}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.paper,
    builder: (_) => _AddDocSheet(employee: employee, agreementOnFile: agreementOnFile),
  );
  if (saved == true && context.mounted) showSnack(context, context.s.documentSaved);
  return saved == true;
}

class _AddDocSheet extends ConsumerStatefulWidget {
  const _AddDocSheet({this.employee, required this.agreementOnFile});
  final Employee? employee;
  final bool agreementOnFile;

  @override
  ConsumerState<_AddDocSheet> createState() => _AddDocSheetState();
}

class _AddDocSheetState extends ConsumerState<_AddDocSheet> {
  String _kind = 'aadhaar';
  final _label = TextEditingController();
  final _number = TextEditingController();
  String? _expiresOn;
  final _files = <DocFile>[];
  bool _agreed = false;
  DocFile? _slip;
  bool _busy = false;

  bool get _forStaff => widget.employee != null;
  bool get _needsSlip => _forStaff && !widget.agreementOnFile;
  bool get _ready =>
      _files.isNotEmpty &&
      (_kind != 'other' || _label.text.trim().isNotEmpty) &&
      (!_forStaff || (_agreed && (!_needsSlip || _slip != null)));

  @override
  void dispose() {
    _label.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<DocFile?> _pick() async {
    final s = context.s;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('docCamera'),
              leading: const Icon(Icons.photo_camera_rounded),
              title: Text(s.takePhoto),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              key: const Key('docGallery'),
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(s.chooseFromGallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    return ref.read(docPickerProvider).pick(source);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _expiresOn == null ? DateTime(now.year + 1, now.month, now.day) : Dates.parseDate(_expiresOn!),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 25),
    );
    if (d != null) setState(() => _expiresOn = Dates.toApiDate(d));
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final number = _number.text.trim();
    final ok = await runGuarded(
      context,
      () => ref
          .read(verificationApiProvider)
          .addDocument(
            employeeId: widget.employee?.id,
            kind: _kind,
            label: _kind == 'other' ? _label.text.trim() : null,
            number: number.isEmpty ? null : number,
            expiresOn: expiringKinds.contains(_kind) ? _expiresOn : null,
            files: _files,
            staffAgreed: _agreed,
            slip: _slip,
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    Widget title(String t) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
    );
    return SingleChildScrollView(
      key: const Key('docSheet'),
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.addDocument, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          title(s.whichDocument),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in documentKinds)
                ChoiceChip(
                  key: Key('docKind_$k'),
                  label: Text(s.fileKind(k)),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
          if (_kind == 'other') ...[
            const SizedBox(height: 14),
            TextField(
              key: const Key('docLabel'),
              controller: _label,
              maxLength: 60,
              decoration: InputDecoration(labelText: s.documentName, hintText: s.documentNameHint, counterText: ''),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            key: const Key('docNumber'),
            controller: _number,
            maxLength: _kind == 'aadhaar' ? 4 : 24,
            keyboardType: _kind == 'aadhaar' ? TextInputType.number : TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: '${_kind == 'aadhaar' ? s.aadhaarLast4 : s.documentNumber} (${s.optional})',
              counterText: '',
            ),
          ),
          if (_kind == 'aadhaar')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(s.maskedAadhaarNote, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ),
          if (expiringKinds.contains(_kind)) ...[
            title(s.validTill),
            OutlinedButton.icon(
              key: const Key('docExpiry'),
              onPressed: _pickDate,
              icon: const Icon(Icons.event_rounded),
              label: Text(_expiresOn == null ? s.pickDate : Dates.prettyApiDate(_expiresOn!, s.languageCode)),
            ),
          ],
          title(s.photosOfDocument),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, f) in _files.indexed)
                _Thumb(key: Key('docThumb_$i'), file: f, onRemove: () => setState(() => _files.removeAt(i))),
              if (_files.length < 3)
                OutlinedButton.icon(
                  key: const Key('docAddPhoto'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(96, 96)),
                  onPressed: () async {
                    final f = await _pick();
                    if (f != null) setState(() => _files.add(f));
                  },
                  icon: const Icon(Icons.add_a_photo_rounded),
                  label: Text(s.addPhoto),
                ),
            ],
          ),
          if (_forStaff) ...[
            const SizedBox(height: 12),
            CheckboxListTile(
              key: const Key('docAgreed'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v ?? false),
              title: Text(
                s.staffAgreedTick(widget.employee!.name),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (_needsSlip) ...[
              title(s.consentSlip),
              Text(s.consentSlipHint, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 8),
              if (_slip != null)
                _Thumb(key: const Key('docSlipThumb'), file: _slip!, onRemove: () => setState(() => _slip = null))
              else
                OutlinedButton.icon(
                  key: const Key('docAddSlip'),
                  onPressed: () async {
                    final f = await _pick();
                    if (f != null) setState(() => _slip = f);
                  },
                  icon: const Icon(Icons.draw_rounded),
                  label: Text(s.addSlipPhoto),
                ),
            ],
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.lock_rounded, size: 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(s.onlyOwnerSees, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('docSave'),
              onPressed: _ready && !_busy ? _save : null,
              child: Text(s.save),
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({super.key, required this.file, required this.onRemove});
  final DocFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 96,
          height: 96,
          color: AppColors.mintFaint,
          child: Image.memory(
            base64Decode(file.data),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.image_rounded, color: AppColors.mintDark, size: 36),
          ),
        ),
      ),
      Positioned(
        right: -8,
        top: -8,
        child: IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded),
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------- view

/// Opens a document (written to History). Returns true when it changed or was removed.
Future<bool> openDocumentViewer(BuildContext context, StaffDoc doc, {required bool owner}) async {
  final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      builder: (_) => _DocViewer(doc: doc, owner: owner),
    ),
  );
  return changed == true;
}

class _DocViewer extends ConsumerStatefulWidget {
  const _DocViewer({required this.doc, required this.owner});
  final StaffDoc doc;
  final bool owner;

  @override
  ConsumerState<_DocViewer> createState() => _DocViewerState();
}

class _DocViewerState extends ConsumerState<_DocViewer> {
  late StaffDoc _doc = widget.doc;
  late Future<OpenedDoc> _opened = ref.read(verificationApiProvider).openDocument(widget.doc.id);
  bool _changed = false;

  Future<void> _changeDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _doc.expiresOn == null
          ? DateTime(now.year + 1, now.month, now.day)
          : Dates.parseDate(_doc.expiresOn!),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 25),
    );
    if (d == null || !mounted) return;
    StaffDoc? updated;
    final ok = await runGuarded(context, () async {
      updated = await ref.read(verificationApiProvider).updateDocument(_doc.id, expiresOn: Dates.toApiDate(d));
    });
    if (ok && updated != null && mounted) {
      setState(() {
        _doc = updated!;
        _changed = true;
      });
    }
  }

  Future<void> _remove() async {
    final s = context.s;
    final name = docName(s, _doc);
    final yes = await confirmDialog(
      context,
      title: s.removeDocumentQ(name),
      message: s.removeDocumentBody,
      confirmLabel: s.remove,
      destructive: true,
    );
    if (!yes || !mounted) return;
    final ok = await runGuarded(context, () => ref.read(verificationApiProvider).removeDocument(_doc.id));
    if (ok && mounted) {
      showSnack(context, s.documentRemoved);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final (line, expiry) = docLines(s, _doc, owner: widget.owner);
    final canRemove = widget.owner || _doc.addedBy == 'staff';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(docName(s, _doc)),
          actions: [
            if (canRemove)
              IconButton(
                key: const Key('docRemove'),
                tooltip: s.remove,
                onPressed: _remove,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            final f = ref.read(verificationApiProvider).openDocument(_doc.id);
            setState(() => _opened = f);
            await f;
          },
          child: ListView(
            key: const Key('docViewer'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(line, style: const TextStyle(color: AppColors.muted)),
              if (expiry != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        expiry.$1,
                        style: TextStyle(color: expiry.$2, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (widget.owner)
                      TextButton(key: const Key('docChangeDate'), onPressed: _changeDate, child: Text(s.changeExpiry)),
                  ],
                )
              else if (widget.owner && expiringKinds.contains(_doc.kind))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(key: const Key('docChangeDate'), onPressed: _changeDate, child: Text(s.validTill)),
                ),
              const SizedBox(height: 10),
              FutureBuilder<OpenedDoc>(
                future: _opened,
                builder: (context, snap) {
                  if (snap.hasError) return Text(errorMessage(context, snap.error!));
                  final o = snap.data;
                  if (o == null) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final f in o.files) _FileView(url: f.url, mime: f.mime),
                      if (o.slip != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 8),
                          child: Text(s.signedSlip, style: Theme.of(context).textTheme.titleMedium),
                        ),
                        _FileView(url: o.slip!.url, mime: o.slip!.mime),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileView extends StatelessWidget {
  const _FileView({required this.url, required this.mime});
  final String url;
  final String mime;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (mime == 'application/pdf') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton.icon(
          key: const Key('docOpenPdf'),
          onPressed: () => openUrl(context, url),
          icon: const Icon(Icons.picture_as_pdf_rounded),
          label: Text(s.openPdf),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Container(
              height: 160,
              color: AppColors.mintFaint,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16),
              child: Text(s.couldNotLoadFile, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}
