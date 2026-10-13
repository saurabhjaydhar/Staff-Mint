import '../utils/json.dart';

/// One check against government records: `aadhaar`, `pan` or `bank`.
class VerifyCheck {
  const VerifyCheck({
    required this.id,
    required this.kind,
    required this.status,
    this.last4,
    this.nameOnRecord,
    this.matchScore,
    this.overrideReason,
    this.details = const {},
    this.attempts = 0,
  });
  final String id;
  final String kind;

  /// waiting · otp_sent · verified · mismatch · not_found · failed
  final String status;
  final String? last4;
  final String? nameOnRecord;
  final int? matchScore;

  /// The owner accepted a name that doesn't quite match, with this reason.
  final String? overrideReason;

  /// Owner only: e.g. date of birth from Aadhaar.
  final Map<String, String> details;
  final int attempts;

  bool get accepted => overrideReason != null;
  bool get ok => status == 'verified' || (status == 'mismatch' && accepted);
  bool get needsLook => (status == 'mismatch' && !accepted) || status == 'not_found';

  factory VerifyCheck.fromJson(Json j) => VerifyCheck(
    id: asString(j['id']),
    kind: asString(j['kind']),
    status: asString(j['status'], 'waiting'),
    last4: asStringOrNull(j['last4']),
    nameOnRecord: asStringOrNull(j['nameOnRecord']),
    matchScore: asIntOrNull(j['matchScore']),
    overrideReason: asStringOrNull(asMapOrNull(j['override'])?['reason']),
    details: {for (final e in asMap(j['details']).entries) e.key: '${e.value}'},
    attempts: asInt(j['attempts']),
  );
}

class VerifyRequest {
  const VerifyRequest({required this.id, required this.kinds, required this.status, this.consented = false});
  final String id;
  final List<String> kinds;

  /// asked · in_progress · done · cancelled
  final String status;
  final bool consented;

  bool get open => status == 'asked' || status == 'in_progress';

  static VerifyRequest? fromJson(Object? v) {
    final j = asMapOrNull(v);
    if (j == null) return null;
    return VerifyRequest(
      id: asString(j['id']),
      kinds: [for (final k in (j['kinds'] as List? ?? const [])) '$k'],
      status: asString(j['status']),
      consented: asBool(j['consented']),
    );
  }
}

/// The owner's view of one person: badge, latest request, its checks, and this month's allowance.
class OwnerVerification {
  const OwnerVerification({
    this.badge = 'none',
    this.request,
    this.checks = const [],
    this.used = 0,
    this.limit = 0,
    this.extraPricePaise = 0,
  });
  final String badge;
  final VerifyRequest? request;
  final List<VerifyCheck> checks;
  final int used;
  final int limit;
  final int extraPricePaise;

  int get left => (limit - used).clamp(0, limit);

  factory OwnerVerification.fromJson(Json j) {
    final q = asMap(j['quota']);
    return OwnerVerification(
      badge: asString(j['badge'], 'none'),
      request: VerifyRequest.fromJson(j['request']),
      checks: asList(j['checks'], VerifyCheck.fromJson),
      used: asInt(q['used']),
      limit: asInt(q['limit']),
      extraPricePaise: asInt(q['extraPricePaise']),
    );
  }
}

/// Staff: what the owner asked for and how each step went.
class MyVerification {
  const MyVerification({
    required this.businessName,
    this.request,
    this.checks = const [],
    this.consentEn = const [],
    this.consentHi = const [],
    this.savedBankLast4,
    this.savedBankIfsc,
  });
  final String businessName;
  final VerifyRequest? request;
  final List<VerifyCheck> checks;
  final List<String> consentEn;
  final List<String> consentHi;

  /// Their salary account on file, if any (the bank step can use it).
  final String? savedBankLast4;
  final String? savedBankIfsc;

  VerifyCheck? check(String kind) {
    for (final c in checks) {
      if (c.kind == kind) return c;
    }
    return null;
  }

  /// Something for the staff member to do.
  bool get todo => request != null && (request!.open || checks.any((c) => !c.ok && !c.needsLook));

  factory MyVerification.fromJson(Json j) {
    final t = asMap(j['consentText']);
    final bank = asMapOrNull(j['savedBank']);
    return MyVerification(
      businessName: asString(j['businessName']),
      request: VerifyRequest.fromJson(j['request']),
      checks: asList(j['checks'], VerifyCheck.fromJson),
      consentEn: [for (final x in (t['en'] as List? ?? const [])) '$x'],
      consentHi: [for (final x in (t['hi'] as List? ?? const [])) '$x'],
      savedBankLast4: asStringOrNull(bank?['last4']),
      savedBankIfsc: asStringOrNull(bank?['ifsc']),
    );
  }
}

/// A staff member's document (photos or a PDF). Only the last 4 characters of its number are kept.
class StaffDoc {
  const StaffDoc({
    required this.id,
    required this.kind,
    this.label,
    this.numberLast4,
    this.mimes = const [],
    this.expiresOn,
    this.expiry,
    this.addedBy = 'staff',
    this.hasSlip = false,
  });
  final String id;

  /// aadhaar · pan · dl · voter · passport · bank_proof · address · police · experience · other
  final String kind;

  /// The name of an "other" document.
  final String? label;
  final String? numberLast4;
  final List<String> mimes;

  /// "2027-03-31" or null.
  final String? expiresOn;

  /// ok · soon · expired, or null when it doesn't expire.
  final String? expiry;

  /// staff · owner
  final String addedBy;
  final bool hasSlip;

  int get pages => mimes.length;
  bool get isPdf => mimes.isNotEmpty && mimes.every((m) => m == 'application/pdf');

  factory StaffDoc.fromJson(Json j) => StaffDoc(
    id: asString(j['id']),
    kind: asString(j['kind'], 'other'),
    label: asStringOrNull(j['label']),
    numberLast4: asStringOrNull(j['numberLast4']),
    mimes: [for (final f in (j['files'] as List? ?? const [])) asString(asMap(f)['mime'])],
    expiresOn: asStringOrNull(j['expiresOn']),
    expiry: asStringOrNull(j['expiry']),
    addedBy: asString(j['addedBy'], 'staff'),
    hasSlip: asBool(j['hasSlip']),
  );
}

class StaffDocs {
  const StaffDocs({this.documents = const [], this.agreementOnFile = false});
  final List<StaffDoc> documents;

  /// The person agreed before (in the app, or a signed slip), so the owner needn't add a slip again.
  final bool agreementOnFile;

  factory StaffDocs.fromJson(Json j) => StaffDocs(
    documents: [for (final d in (j['documents'] as List? ?? const [])) StaffDoc.fromJson(asMap(d))],
    agreementOnFile: asBool(j['agreementOnFile']),
  );
}

/// A file to upload: base64 and its type.
class DocFile {
  const DocFile({required this.data, required this.mime});
  final String data;
  final String mime;
  Json toJson() => {'data': data, 'mime': mime};
}

/// Short-lived links to open a document's files.
class OpenedDoc {
  const OpenedDoc({this.files = const [], this.slip});
  final List<({String url, String mime})> files;
  final ({String url, String mime})? slip;

  static ({String url, String mime}) _f(Object? v) {
    final j = asMap(v);
    return (url: asString(j['url']), mime: asString(j['mime']));
  }

  factory OpenedDoc.fromJson(Json j) => OpenedDoc(
    files: [for (final f in (j['files'] as List? ?? const [])) _f(f)],
    slip: j['slip'] == null ? null : _f(j['slip']),
  );
}
