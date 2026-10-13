import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
import '../i18n/locale_provider.dart';
import '../storage/providers.dart';
import 'api_client.dart';
import 'services/accounts_api.dart';
import 'services/roster_api.dart';
import 'services/attendance_api.dart';
import 'services/auth_api.dart';
import 'services/company_api.dart';
import 'services/employees_api.dart';
import 'services/leave_api.dart';
import 'services/geo_api.dart';
import 'services/me_api.dart';
import 'services/misc_api.dart';
import 'services/money_api.dart';
import 'services/payroll_api.dart';
import 'services/profile_api.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient.create(
    tokens: ref.watch(tokenStorageProvider),
    languageCode: () => ref.read(localeProvider),
    onSessionExpired: () => ref.read(authControllerProvider.notifier).onSessionExpired(),
    onAccountChanged: (change) => ref.read(authControllerProvider.notifier).onAccountChanged(change),
  );
});

final authApiProvider = Provider((ref) => AuthApi(ref.watch(apiClientProvider)));
final meApiProvider = Provider((ref) => MeApi(ref.watch(apiClientProvider)));
final profileApiProvider = Provider((ref) => ProfileApi(ref.watch(apiClientProvider)));
final companyApiProvider = Provider((ref) => CompanyApi(ref.watch(apiClientProvider)));
final employeesApiProvider = Provider((ref) => EmployeesApi(ref.watch(apiClientProvider)));
final attendanceApiProvider = Provider((ref) => AttendanceApi(ref.watch(apiClientProvider)));
final rosterApiProvider = Provider((ref) => RosterApi(ref.watch(apiClientProvider)));
final leaveApiProvider = Provider((ref) => LeaveApi(ref.watch(apiClientProvider)));
final geoApiProvider = Provider((ref) => GeoApi(ref.watch(apiClientProvider)));
final moneyApiProvider = Provider((ref) => MoneyApi(ref.watch(apiClientProvider)));
final payrollApiProvider = Provider((ref) => PayrollApi(ref.watch(apiClientProvider)));
final reportsApiProvider = Provider((ref) => ReportsApi(ref.watch(apiClientProvider)));
final assistantApiProvider = Provider((ref) => AssistantApi(ref.watch(apiClientProvider)));
final billingApiProvider = Provider((ref) => BillingApi(ref.watch(apiClientProvider)));
final accountsApiProvider = Provider((ref) => AccountsApi(ref.watch(apiClientProvider)));
final auditApiProvider = Provider((ref) => AuditApi(ref.watch(apiClientProvider)));
