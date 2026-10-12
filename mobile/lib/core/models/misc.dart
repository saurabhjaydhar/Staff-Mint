import '../utils/json.dart';
import 'company.dart';

class AuditLog {
  const AuditLog({
    required this.id,
    this.actorId,
    required this.actorName,
    required this.channel,
    required this.action,
    required this.entity,
    this.entityId,
    this.before,
    this.after,
    this.at,
    this.text,
    this.category = 'other',
    this.changes = const [],
  });
  final String id;
  final String? actorId;
  final String actorName;
  final String channel;
  final String action;
  final String entity;
  final String? entityId;
  final Object? before;
  final Object? after;
  final DateTime? at;

  /// One plain sentence for people ("Raju: 1 Oct set to Absent"), in the app's language.
  final String? text;

  /// attendance | leave | salary | staff | settings | team | billing | other
  final String category;

  /// What changed, in words ("Status: Present → Absent").
  final List<AuditChange> changes;

  factory AuditLog.fromJson(Json j) => AuditLog(
    id: asString(j['id']),
    actorId: asStringOrNull(j['actorId']),
    actorName: asString(j['actorName'], '—'),
    channel: asString(j['channel'], 'app'),
    action: asString(j['action']),
    entity: asString(j['entity']),
    entityId: asStringOrNull(j['entityId']),
    before: j['before'],
    after: j['after'],
    at: asDateTimeOrNull(j['at']),
    text: asStringOrNull(j['text']),
    category: asString(j['category'], 'other'),
    changes: asList(j['changes'], AuditChange.fromJson),
  );
}

class AuditChange {
  const AuditChange({required this.label, this.from, this.to});
  final String label;
  final String? from;
  final String? to;

  factory AuditChange.fromJson(Json j) =>
      AuditChange(label: asString(j['label']), from: asStringOrNull(j['from']), to: asStringOrNull(j['to']));
}

class BillingInfo {
  const BillingInfo({
    this.subscription,
    this.plan,
    this.staffCount = 0,
    int? billStaffCount,
    this.billedToName,
    this.trial,
    this.usage = const {},
    this.recommendation,
    this.priceLockMonths = 0,
  }) : billStaffCount = billStaffCount ?? staffCount;
  final Subscription? subscription;
  final Trial? trial;
  final Plan? plan;
  final int staffCount;

  /// Staff across every business on the bill: what plan limits count.
  final int billStaffCount;

  /// Paid features used since the trial started (at most 30 days back), e.g. `face_match: 85`.
  final Map<String, int> usage;
  final PlanRecommendation? recommendation;

  /// The price stays the same this long after subscribing.
  final int priceLockMonths;

  /// Paid together with this business (one bill); its plan is managed there.
  final String? billedToName;

  factory BillingInfo.fromJson(Json j) => BillingInfo(
    subscription: j['subscription'] is Map ? Subscription.fromJson(asMap(j['subscription'])) : null,
    plan: j['plan'] is Map ? Plan.fromJson(asMap(j['plan'])) : null,
    staffCount: asInt(j['staffCount']),
    billStaffCount: j['billStaffCount'] == null ? null : asInt(j['billStaffCount']),
    billedToName: j['billedTo'] is Map ? asStringOrNull(asMap(j['billedTo'])['name']) : null,
    trial: j['trial'] is Map ? Trial.fromJson(asMap(j['trial'])) : null,
    usage: {
      if (j['usage'] is Map)
        for (final e in asMap(j['usage']).entries)
          if (asInt(e.value) > 0) e.key: asInt(e.value),
    },
    recommendation: j['recommendation'] is Map ? PlanRecommendation.fromJson(asMap(j['recommendation'])) : null,
    priceLockMonths: asInt(j['priceLockMonths']),
  );
}

/// One reason a plan suits the shop: its staff fit, or a paid feature it used.
class PlanReason {
  const PlanReason.staff(int this.staff, int this.limit) : feature = null, count = 0;
  const PlanReason.feature(String this.feature, this.count) : staff = null, limit = null;
  final int? staff;
  final int? limit;
  final String? feature;
  final int count;

  static PlanReason fromJson(Json j) => asString(j['kind']) == 'staff'
      ? PlanReason.staff(asInt(j['staff']), asInt(j['limit']))
      : PlanReason.feature(asString(j['feature']), asInt(j['count']));
}

/// The cheapest plan that fits the shop, why, and what the next cheaper plan would lose.
class PlanRecommendation {
  const PlanRecommendation({
    required this.planCode,
    this.reasons = const [],
    this.cheaperCode,
    this.cheaperLoses = const [],
  });
  final String planCode;
  final List<PlanReason> reasons;
  final String? cheaperCode;
  final List<({String feature, int count})> cheaperLoses;

  factory PlanRecommendation.fromJson(Json j) {
    final cheaper = j['cheaper'] is Map ? asMap(j['cheaper']) : null;
    return PlanRecommendation(
      planCode: asString(j['planCode']),
      reasons: asList(j['reasons'], PlanReason.fromJson),
      cheaperCode: cheaper == null ? null : asStringOrNull(cheaper['planCode']),
      cheaperLoses: cheaper == null
          ? const []
          : asList(cheaper['loses'], (Json l) => (feature: asString(l['feature']), count: asInt(l['count']))),
    );
  }
}

/// Money taken for a plan.
class Receipt {
  const Receipt({
    required this.id,
    this.planName,
    this.interval = 'monthly',
    required this.amountPaise,
    required this.paidAt,
    this.hasInvoice = false,
  });
  final String id;
  final String? planName;
  final String interval;
  final int amountPaise;
  final DateTime paidAt;

  /// The gateway made an invoice (with GST) that can be opened.
  final bool hasInvoice;

  factory Receipt.fromJson(Json j) => Receipt(
    id: asString(j['id']),
    planName: asStringOrNull(j['planName']),
    interval: asString(j['interval'], 'monthly'),
    amountPaise: asInt(j['amountPaise']),
    paidAt: asDateTimeOrNull(j['paidAt']) ?? DateTime.now(),
    hasInvoice: asBool(j['hasInvoice']),
  );
}

/// One bill for several businesses of the same main owner.
class BillingGroup {
  const BillingGroup({
    this.isPayer = true,
    this.members = const [],
    this.candidates = const [],
    this.totalStaff = 0,
    this.extraBusinessPricePaise = 0,
  });
  final bool isPayer;
  final List<({String companyId, String name, int staffCount})> members;
  final List<({String companyId, String name, int staffCount})> candidates;
  final int totalStaff;
  final int extraBusinessPricePaise;

  static ({String companyId, String name, int staffCount}) _biz(Json j) =>
      (companyId: asString(j['companyId']), name: asString(j['name']), staffCount: asInt(j['staffCount']));

  factory BillingGroup.fromJson(Json j) => BillingGroup(
    isPayer: asBool(j['isPayer']),
    members: asList(j['members'], _biz),
    candidates: asList(j['candidates'], _biz),
    totalStaff: asInt(j['totalStaff']),
    extraBusinessPricePaise: asInt(j['extraBusinessPricePaise']),
  );
}

class PublicConfig {
  const PublicConfig({this.minAppVersion, this.supportWhatsApp, this.otpProvider, this.environment});
  final String? minAppVersion;
  final String? supportWhatsApp;
  final String? otpProvider;
  final String? environment;

  factory PublicConfig.fromJson(Json j) => PublicConfig(
    minAppVersion: asStringOrNull(j['minAppVersion']),
    supportWhatsApp: asStringOrNull(j['supportWhatsApp']),
    otpProvider: asStringOrNull(j['otpProvider']),
    environment: asStringOrNull(j['environment']),
  );
}

class AppNotification {
  const AppNotification({required this.id, required this.title, required this.body, this.readAt, this.createdAt});
  final String id;
  final String title;
  final String body;
  final DateTime? readAt;
  final DateTime? createdAt;

  factory AppNotification.fromJson(Json j) => AppNotification(
    id: asString(j['id']),
    title: asString(j['title']),
    body: asString(j['body']),
    readAt: asDateTimeOrNull(j['readAt']),
    createdAt: asDateTimeOrNull(j['createdAt']),
  );
}
