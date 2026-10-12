import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/accounts_api.dart';
import 'package:staffmint/core/api/services/misc_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/features/owner/more/billing_screen.dart';
import 'package:staffmint/features/owner/providers/owner_providers.dart';

const _plans = [
  Plan(
    code: 'free',
    name: 'Free',
    priceMonthlyPaise: 0,
    priceYearlyPaise: 0,
    currency: 'INR',
    staffLimit: 5,
    extraStaffPricePaise: 0,
    trialDays: 0,
    features: ['attendance', 'leave', 'digest'],
  ),
  Plan(
    code: 'starter',
    name: 'Starter',
    priceMonthlyPaise: 49900,
    priceYearlyPaise: 499000,
    currency: 'INR',
    staffLimit: 15,
    extraStaffPricePaise: 0,
    trialDays: 14,
    features: ['attendance', 'leave', 'digest', 'payroll', 'advances', 'payslips', 'assistant', 'reports'],
  ),
  Plan(
    code: 'growth',
    name: 'Growth',
    priceMonthlyPaise: 99900,
    priceYearlyPaise: 999000,
    currency: 'INR',
    staffLimit: 30,
    extraStaffPricePaise: 0,
    trialDays: 14,
    features: [
      'attendance', 'leave', 'digest', 'payroll', 'advances', 'payslips', 'assistant', 'reports', //
      'branches', 'whatsapp_payslips', 'whatsapp_assistant', 'face_match',
    ],
  ),
  Plan(
    code: 'pro',
    name: 'Pro',
    priceMonthlyPaise: 179900,
    priceYearlyPaise: 1799000,
    currency: 'INR',
    staffLimit: 50,
    extraStaffPricePaise: 3000,
    maxStaffHardCap: 500,
    trialDays: 14,
    features: [
      'attendance', 'leave', 'digest', 'payroll', 'advances', 'payslips', 'assistant', 'reports', //
      'branches', 'whatsapp_payslips', 'whatsapp_assistant', 'face_match', 'priority_support', 'ca_access',
    ],
  ),
];

class _FakeBillingApi implements BillingApi {
  _FakeBillingApi(this.info, {this.receiptList = const []});
  BillingInfo info;
  final List<Receipt> receiptList;
  final subscribed = <String>[];
  var cancelled = 0;

  @override
  Future<List<Plan>> plans() async => _plans;
  @override
  Future<BillingInfo> subscription() async => info;
  @override
  Future<List<Receipt>> receipts() async => receiptList;
  @override
  Future<String> subscribe(String planCode, String interval) async {
    subscribed.add('$planCode/$interval');
    return 'https://pay.example/checkout';
  }

  @override
  Future<void> cancel() async => cancelled++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAccountsApi implements AccountsApi {
  @override
  Future<BillingGroup> billingGroup() async => const BillingGroup();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BillingInfo _trialShop() => BillingInfo(
  plan: _plans[2],
  subscription: const Subscription(status: 'trialing', planCode: 'growth'),
  trial: Trial(planCode: 'growth', planName: 'Growth', endsAt: DateTime.now().add(const Duration(days: 10, hours: 12))),
  staffCount: 9,
  usage: const {'face_match': 85, 'whatsapp_payslips': 12, 'payroll': 1},
  recommendation: const PlanRecommendation(
    planCode: 'growth',
    reasons: [
      PlanReason.staff(9, 30),
      PlanReason.feature('face_match', 85),
      PlanReason.feature('whatsapp_payslips', 12),
    ],
    cheaperCode: 'starter',
    cheaperLoses: [(feature: 'face_match', count: 85), (feature: 'whatsapp_payslips', count: 12)],
  ),
  priceLockMonths: 24,
);

Future<void> _pump(WidgetTester tester, _FakeBillingApi api, {String lang = 'en'}) async {
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
        billingApiProvider.overrideWithValue(api),
        accountsApiProvider.overrideWithValue(_FakeAccountsApi()),
        publicConfigProvider.overrideWith((ref) async => const PublicConfig(supportWhatsApp: '+919999900000')),
      ],
      child: MaterialApp(
        locale: Locale(lang),
        supportedLocales: const [Locale('en'), Locale('hi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const BillingScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('trial: the best plan with reasons, an honest cheaper option, colour-coded plans', (tester) async {
    final api = _FakeBillingApi(_trialShop());
    await _pump(tester, api);

    expect(find.text('Plan & payment'), findsOneWidget);
    expect(find.textContaining('Free trial: 11 days left', findRichText: true), findsOneWidget);
    expect(find.text('Best plan for your shop'), findsOneWidget);
    expect(find.text('Your 9 staff fit (up to 30)'), findsOneWidget);
    expect(find.text('You used Face check 85 times in your trial'), findsOneWidget);
    expect(find.text('You sent 12 salary slips on WhatsApp'), findsOneWidget);
    expect(find.text('About ₹33 a day'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Keep Growth'), findsOneWidget);
    expect(find.text('Want to spend less? Starter'), findsOneWidget);
    expect(find.text('Fits your 9 staff, but Face check and Salary slips on WhatsApp will stop.'), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const Key('plan_free')), 300);
    expect(find.text('Not for you: allows only 5 staff'), findsOneWidget);
    expect(find.text('2 months free'), findsOneWidget);
    await tester.tap(find.text('Yearly'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('plan_growth')), 300);
    expect(find.text('₹833 a month · you save ₹1,998'), findsOneWidget);
    expect(find.textContaining('Best for you · On trial now'), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const Key('compareTable')), 300);
    expect(find.text('Your CA can log in'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Your price stays the same for 2 years.'), 300);
    await tester.scrollUntilVisible(find.byKey(const Key('nextPayment')), 300);
    expect(find.textContaining('only if you choose Growth'), findsOneWidget);
    expect(find.text('Your receipts show here after the first payment'), findsOneWidget);
    // A trial has nothing to stop.
    expect(find.byKey(const Key('stopPlan')), findsNothing);
  });

  testWidgets('keeping the plan in a trial: ₹0 today, then checkout', (tester) async {
    final api = _FakeBillingApi(_trialShop());
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('bestChoose')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('paySheet')), findsOneWidget);
    expect(find.text('Today you pay ₹0'), findsOneWidget);
    expect(find.text('Set up payment · ₹0 today'), findsOneWidget);
    await tester.tap(find.byKey(const Key('payGo')));
    // Checkout opens outside the app (no plugin in tests), so don't wait for it to settle.
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.subscribed, ['growth/monthly']);
  });

  testWidgets('a cheaper plan first shows what stops, with the shop’s own numbers', (tester) async {
    final api = _FakeBillingApi(_trialShop());
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('cheaperPlan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('switchSheet')), findsOneWidget);
    expect(find.text('You save ₹500 a month (₹499 instead of ₹999)'), findsOneWidget);
    expect(find.text('Face check (used 85 times)'), findsOneWidget);
    expect(find.text('Your 9 staff fit in Starter (up to 15)'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Keep Growth').last);
    await tester.pumpAndSettle();
    expect(api.subscribed, isEmpty);

    await tester.tap(find.byKey(const Key('cheaperPlan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switchGo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('paySheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('payGo')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.subscribed, ['starter/monthly']);
  });

  testWidgets('paid plan: renewal date, receipts, stop plan', (tester) async {
    final renew = DateTime(2026, 11, 23);
    final api = _FakeBillingApi(
      BillingInfo(
        plan: _plans[1],
        subscription: Subscription(status: 'active', planCode: 'starter', currentPeriodEnd: renew, pricePaise: 49900),
        staffCount: 9,
        recommendation: const PlanRecommendation(planCode: 'starter', reasons: [PlanReason.staff(9, 15)]),
        priceLockMonths: 24,
      ),
      receiptList: [Receipt(id: 'r1', planName: 'Starter', amountPaise: 49900, paidAt: DateTime(2026, 10, 23))],
    );
    await _pump(tester, api);
    expect(find.text('Your plan: Starter · renews on 23 Nov 2026'), findsOneWidget);
    expect(find.byKey(const Key('bestIsYours')), findsOneWidget);
    expect(find.byKey(const Key('cheaperPlan')), findsNothing);

    await tester.scrollUntilVisible(find.byKey(const Key('receipt_r1')), 300);
    expect(find.text('Starter · 1 month'), findsOneWidget);
    expect(find.textContaining('₹499 on 23 Nov 2026'), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const Key('stopPlan')), 300);
    await tester.tap(find.byKey(const Key('stopPlan')));
    await tester.pumpAndSettle();
    expect(find.text('Stop Starter?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Stop plan'));
    await tester.pumpAndSettle();
    expect(api.cancelled, 1);
  });

  testWidgets('Hindi mode is all Hindi', (tester) async {
    await _pump(tester, _FakeBillingApi(_trialShop()), lang: 'hi');
    expect(find.text('प्लान और पेमेंट'), findsOneWidget);
    expect(find.textContaining('फ़्री ट्रायल: 11 दिन बचे', findRichText: true), findsOneWidget);
    expect(find.text('आपकी दुकान के लिए सबसे सही प्लान'), findsOneWidget);
    expect(find.text('आपने ट्रायल में चेहरा मिलान 85 बार इस्तेमाल किया'), findsOneWidget);
    expect(find.text('Growth रखें'), findsOneWidget);
    expect(find.text('कम ख़र्च? Starter'), findsOneWidget);
  });
}
