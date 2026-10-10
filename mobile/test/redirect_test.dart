import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/router/redirect.dart';
import 'package:staffmint/core/router/routes.dart';
import 'package:staffmint/features/auth/session_state.dart';

User _user(String role, {String? companyId = 'c1'}) =>
    User(id: 'u1', phone: '9876543210', name: 'Test', role: role, companyId: companyId);

SessionState _auth(String role, {bool needsSetup = false, bool? consent}) => SessionState(
  status: SessionStatus.authenticated,
  user: _user(role, companyId: needsSetup ? null : 'c1'),
  needsCompanySetup: needsSetup,
  employee: consent == null ? null : Employee(id: 'e1', name: 'Test', phone: '9876543210', locationConsent: consent),
);

void main() {
  group('computeRedirect', () {
    test('unknown session shows the splash', () {
      const s = SessionState.unknown();
      expect(computeRedirect(s, Routes.ownerHome), Routes.splash);
      expect(computeRedirect(s, Routes.splash), isNull);
    });

    test('logged-out users can only see login screens', () {
      const s = SessionState.unauthenticated();
      expect(computeRedirect(s, Routes.splash), Routes.login);
      expect(computeRedirect(s, Routes.employeeHome), Routes.login);
      expect(computeRedirect(s, Routes.login), isNull);
      expect(computeRedirect(s, Routes.otp), isNull);
    });

    test('new owner is forced into company setup', () {
      final s = _auth(UserRole.owner, needsSetup: true);
      expect(computeRedirect(s, Routes.ownerHome), Routes.setup);
      expect(computeRedirect(s, Routes.otp), Routes.setup);
      expect(computeRedirect(s, Routes.setup), isNull);
    });

    test('after company creation /setup forwards to the add-staff step', () {
      final s = _auth(UserRole.owner);
      expect(computeRedirect(s, Routes.setup), Routes.setupStaff);
      expect(computeRedirect(s, Routes.setupStaff), isNull);
    });

    test('owner and manager land in the owner shell', () {
      for (final role in [UserRole.owner, UserRole.manager, UserRole.ca]) {
        final s = _auth(role);
        expect(computeRedirect(s, Routes.splash), Routes.ownerHome, reason: role);
        expect(computeRedirect(s, Routes.login), Routes.ownerHome, reason: role);
        expect(computeRedirect(s, Routes.employeeHome), Routes.ownerHome, reason: role);
        expect(computeRedirect(s, Routes.ownerSalary), isNull, reason: role);
        expect(computeRedirect(s, '/owner/staff/abc'), isNull, reason: role);
        expect(computeRedirect(s, Routes.ownerLeaves), isNull, reason: role);
      }
    });

    test('employee without consent must accept the notice first', () {
      final s = _auth(UserRole.employee, consent: false);
      expect(computeRedirect(s, Routes.employeeHome), Routes.employeeConsent);
      expect(computeRedirect(s, Routes.ownerHome), Routes.employeeConsent);
      expect(computeRedirect(s, Routes.employeeConsent), isNull);
    });

    test('employee with consent lands in the employee shell only', () {
      final s = _auth(UserRole.employee, consent: true);
      expect(computeRedirect(s, Routes.splash), Routes.employeeHome);
      expect(computeRedirect(s, Routes.employeeConsent), Routes.employeeHome);
      expect(computeRedirect(s, Routes.ownerHome), Routes.employeeHome);
      expect(computeRedirect(s, Routes.setup), Routes.employeeHome);
      expect(computeRedirect(s, Routes.ownerSalary), Routes.employeeHome);
      expect(computeRedirect(s, Routes.employeeSalary), isNull);
    });

    test('employees never get the company setup flow', () {
      final s = SessionState(
        status: SessionStatus.authenticated,
        user: _user(UserRole.employee),
        employee: const Employee(id: 'e1', name: 'x', phone: '9876543210', locationConsent: true),
      );
      expect(computeRedirect(s, Routes.setup), Routes.employeeHome);
    });
  });

  group('accounts', () {
    test('several accounts after login: the chooser comes first', () {
      final s = _auth(UserRole.owner).copyWith(needsAccountChoice: true);
      expect(computeRedirect(s, Routes.ownerHome), Routes.accounts);
      expect(computeRedirect(s, Routes.employeeHome), Routes.accounts);
      expect(computeRedirect(s, Routes.accounts), isNull);
      expect(computeRedirect(s, Routes.accountsNew), isNull);
    });

    test('the chooser and "new business" stay open to every role', () {
      expect(computeRedirect(_auth(UserRole.owner), Routes.accounts), isNull);
      expect(computeRedirect(_auth(UserRole.employee, consent: true), Routes.accountsNew), isNull);
      // Even before staff accept the location notice.
      expect(computeRedirect(_auth(UserRole.employee, consent: false), Routes.accounts), isNull);
      expect(computeRedirect(_auth(UserRole.ca), Routes.accountsNew), isNull);
    });

    test('a number with no business still goes to setup, not the chooser', () {
      final s = _auth(UserRole.owner, needsSetup: true);
      expect(computeRedirect(s, Routes.accounts), Routes.setup);
    });
  });
}
