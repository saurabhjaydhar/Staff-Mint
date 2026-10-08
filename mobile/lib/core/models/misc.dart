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
  );
}

class BillingInfo {
  const BillingInfo({this.subscription, this.plan, this.staffCount = 0});
  final Subscription? subscription;
  final Plan? plan;
  final int staffCount;

  factory BillingInfo.fromJson(Json j) => BillingInfo(
    subscription: j['subscription'] is Map ? Subscription.fromJson(asMap(j['subscription'])) : null,
    plan: j['plan'] is Map ? Plan.fromJson(asMap(j['plan'])) : null,
    staffCount: asInt(j['staffCount']),
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
