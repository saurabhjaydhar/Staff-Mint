import '../../models/models.dart';
import '../../utils/json.dart';
import '../api_client.dart';

class MeResponse {
  const MeResponse({required this.user, this.company, this.employee});
  final User user;
  final Company? company;
  final Employee? employee;

  factory MeResponse.fromJson(Json j) => MeResponse(
    user: User.fromJson(asMap(j['user'])),
    company: j['company'] is Map ? Company.fromJson(asMap(j['company'])) : null,
    employee: j['employee'] is Map ? Employee.fromJson(asMap(j['employee'])) : null,
  );
}

class MeApi {
  MeApi(this._c);
  final ApiClient _c;

  /// Returns the raw JSON too, so it can be cached for offline start.
  Future<(MeResponse, Json)> me() async {
    final d = asMap(await _c.get('/me'));
    return (MeResponse.fromJson(d), d);
  }

  Future<User> update({String? name, String? language}) async {
    final d = await _c.patch('/me', body: {'name': ?name, 'language': ?language});
    return User.fromJson(asMap(d));
  }

  Future<Employee> giveLocationConsent() async {
    final d = await _c.post('/me/consent', body: {'location': true});
    return Employee.fromJson(asMap(d));
  }

  Future<void> registerPushToken(String token, String platform) async {
    await _c.post('/me/push-token', body: {'token': token, 'platform': platform});
  }

  Future<SalaryOverview> salary({String? month}) async {
    final d = await _c.get('/me/salary', query: {'month': month});
    return SalaryOverview.fromJson(asMap(d));
  }

  Future<List<AppNotification>> notifications() async {
    final d = await _c.get('/me/notifications');
    return asList(d, AppNotification.fromJson);
  }
}
