import '../utils/json.dart';

/// One person's app invite: what happened, and the invite in words to send from the owner's own WhatsApp.
class InvitePerson {
  const InvitePerson({required this.name, required this.phone, required this.status, required this.shareText});
  final String name;
  final String phone;

  /// sent · recent (sent a few minutes ago) · failed (our WhatsApp couldn't send it)
  final String status;
  final String shareText;

  factory InvitePerson.fromJson(Json j) => InvitePerson(
    name: asString(j['name']),
    phone: asString(j['phone']),
    status: asString(j['status'], 'sent'),
    shareText: asString(j['shareText']),
  );
}

/// `POST /employees/remind-invites`
class RemindResult {
  const RemindResult({this.sent = 0, this.failed = 0, this.whatsappConnected = true, this.people = const []});
  final int sent;
  final int failed;

  /// The business WhatsApp is set up; when it isn't, nothing really reaches their phone.
  final bool whatsappConnected;
  final List<InvitePerson> people;

  factory RemindResult.fromJson(Json j) => RemindResult(
    sent: asInt(j['sent']),
    failed: asInt(j['failed']),
    whatsappConnected: asBool(j['whatsappConnected'], true),
    people: asList(j['people'], InvitePerson.fromJson),
  );
}
