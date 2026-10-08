import '../../models/models.dart';
import '../../utils/json.dart';
import '../api_client.dart';

class CreateCompanyRequest {
  const CreateCompanyRequest({
    required this.name,
    required this.businessType,
    required this.location,
    required this.openingTime,
    this.closingTime,
    required this.weeklyOff,
  });
  final String name;
  final String businessType;
  final GeoPoint location;
  final String openingTime;
  final String? closingTime;
  final List<int> weeklyOff;

  Json toJson() => {
    'name': name,
    'businessType': businessType,
    'location': location.toJson(),
    'openingTime': openingTime,
    'closingTime': ?closingTime,
    'weeklyOff': weeklyOff,
    'country': 'IN',
    'timezone': 'Asia/Kolkata',
    'currency': 'INR',
  };
}

class CreateCompanyResult {
  const CreateCompanyResult({required this.company, required this.accessToken, required this.refreshToken});
  final Company company;
  final String accessToken;
  final String refreshToken;
}

class CompanyApi {
  CompanyApi(this._c);
  final ApiClient _c;

  Future<CreateCompanyResult> create(CreateCompanyRequest req) async {
    final d = asMap(await _c.post('/company', body: req.toJson()));
    return CreateCompanyResult(
      company: Company.fromJson(asMap(d['company'])),
      accessToken: asString(d['accessToken']),
      refreshToken: asString(d['refreshToken']),
    );
  }

  Future<Company> get() async => Company.fromJson(asMap(await _c.get('/company')));

  Future<Company> update({String? name, String? businessType, GeoPoint? location}) async {
    final d = await _c.patch(
      '/company',
      body: {'name': ?name, 'businessType': ?businessType, if (location != null) 'location': location.toJson()},
    );
    return Company.fromJson(asMap(d));
  }

  Future<Company> updateSettings(Json partial) async =>
      Company.fromJson(asMap(await _c.patch('/company/settings', body: partial)));

  Future<List<RuleText>> rules() async {
    final d = asMap(await _c.get('/company/rules'));
    return asList(d['rules'], RuleText.fromJson);
  }

  Future<List<Branch>> branches() async => asList(await _c.get('/branches'), Branch.fromJson);

  Future<Branch> createBranch({required String name, required GeoPoint location, int? radiusM}) async =>
      Branch.fromJson(
        asMap(await _c.post('/branches', body: {'name': name, 'location': location.toJson(), 'radiusM': ?radiusM})),
      );

  Future<Branch> updateBranch(String id, Json partial) async =>
      Branch.fromJson(asMap(await _c.patch('/branches/$id', body: partial)));

  Future<List<Shift>> shifts() async => asList(await _c.get('/shifts'), Shift.fromJson);

  Future<Shift> createShift(Json body) async => Shift.fromJson(asMap(await _c.post('/shifts', body: body)));

  Future<Shift> updateShift(String id, Json partial) async =>
      Shift.fromJson(asMap(await _c.patch('/shifts/$id', body: partial)));

  Future<List<Holiday>> holidays({int? year}) async =>
      asList(await _c.get('/holidays', query: {'year': year}), Holiday.fromJson);

  Future<Holiday> addHoliday(String date, String name) async =>
      Holiday.fromJson(asMap(await _c.post('/holidays', body: {'date': date, 'name': name})));

  Future<void> deleteHoliday(String id) async => _c.delete('/holidays/$id');

  Future<Dashboard> dashboardToday() async => Dashboard.fromJson(asMap(await _c.get('/dashboard/today')));

  Future<PublicConfig> publicConfig() async =>
      PublicConfig.fromJson(asMap(await _c.get('/config/public', auth: false)));
}
