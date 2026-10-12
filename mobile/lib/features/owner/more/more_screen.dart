import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/bilingual.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_controller.dart';
import '../providers/owner_providers.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    final s = context.s;
    try {
      final res = await ref.read(reportsApiProvider).export();
      if (!mounted) return;
      if (res.url != null) {
        await openUrl(context, res.url!);
      } else if (res.bytes != null) {
        final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/staffmint-export-${DateTime.now().millisecondsSinceEpoch}.zip');
        await file.writeAsBytes(res.bytes!);
        if (mounted) showSnack(context, s.exportSaved(file.path));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = ref.watch(authControllerProvider);
    final lang = ref.watch(localeProvider);
    final isOwner = session.user?.role == UserRole.owner;
    final waiting = ref.watch(dashboardProvider).value?.leaveRequests.length ?? 0;
    final trial = session.company?.trial;
    final trialDays = trial != null && trial.activeAt(DateTime.now()) ? trial.daysLeftAt(DateTime.now()) : null;

    final groups = <(String, List<_Entry>)>[
      (
        s.groupDaily,
        [
          _Entry(
            'leaves',
            Icons.beach_access_rounded,
            s.leaveRequests,
            waiting > 0 ? s.leaveWaiting(waiting) : null,
            'leave chutti chhutti छुट्टी अर्ज़ी',
            () => context.push(Routes.ownerLeaves),
          ),
          _Entry(
            'reports',
            Icons.description_rounded,
            s.reports,
            null,
            'report excel pdf register रिपोर्ट',
            () => context.push(Routes.ownerReports),
          ),
        ],
      ),
      if (isOwner)
        (
          s.groupShopRules,
          [
            _Entry(
              'timings',
              Icons.schedule_rounded,
              s.timingsTitle,
              s.timingsHint,
              'shift time holiday festival weekly off sunday शिफ़्ट समय त्योहार छुट्टी',
              () => context.push(Routes.ownerTimings),
            ),
            _Entry(
              'attendanceRules',
              Icons.fact_check_rounded,
              s.attendanceRulesTitle,
              s.attendanceRulesHint,
              'late grace half day checkout forgot summary लेट आधा दिन',
              () => context.push(Routes.ownerAttendanceRules),
            ),
            _Entry(
              'salaryRules',
              Icons.currency_rupee_rounded,
              s.salaryRulesTitle,
              s.salaryRulesHint,
              'salary days 30 26 paid leave pf esi tax सैलरी दिन',
              () => context.push(Routes.ownerSalaryRules),
            ),
            _Entry(
              'safety',
              Icons.verified_user_rounded,
              s.safetyTitle,
              s.safetyHint,
              'area geofence location selfie phone lock face proxy सेल्फ़ी फ़ोन लॉक चेहरा',
              () => context.push(Routes.ownerSafety),
            ),
          ],
        ),
      (
        s.groupBusiness,
        [
          if (isOwner)
            _Entry(
              'business',
              Icons.storefront_rounded,
              s.businessDetailsTitle,
              s.businessDetailsHint,
              'name branch pf esi close business नाम ब्रांच',
              () => context.push(Routes.ownerSettings),
            ),
          if (isOwner)
            _Entry(
              'team',
              Icons.key_rounded,
              s.teamAccess,
              s.teamAccessHint,
              'ca accountant partner co-owner manager पार्टनर मैनेजर',
              () => context.push(Routes.ownerTeam),
            ),
          if (isOwner)
            _Entry(
              'plan',
              Icons.workspace_premium_rounded,
              s.planPayment,
              trialDays == null ? null : s.trialDaysLeftShort(trialDays),
              'plan billing payment trial upgrade प्लान पेमेंट',
              () => context.push(Routes.ownerBilling),
            ),
          _Entry(
            'history',
            Icons.history_rounded,
            s.historyOfChanges,
            null,
            'audit log history changes who changed बदलाव',
            () => context.push(Routes.ownerAudit),
          ),
        ],
      ),
      (
        s.groupApp,
        [
          _Entry(
            'help',
            Icons.help_outline_rounded,
            s.helpVideos,
            null,
            'help video faq support whatsapp मदद',
            () => context.push(Routes.ownerHelp),
          ),
          if (isOwner)
            _Entry(
              'export',
              Icons.download_rounded,
              s.exportData,
              s.exportHint,
              'export download backup data डाउनलोड',
              _exporting ? () {} : _export,
            ),
        ],
      ),
    ];
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final (title, entries) in groups)
        (
          title,
          [
            for (final e in entries)
              if (q.isEmpty || e.matches(q)) e,
          ],
        ),
    ].where((g) => g.$2.isNotEmpty).toList();

    Widget tile(_Entry e) => ListTile(
      key: Key('more_${e.id}'),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: BorderRadius.circular(12)),
        child: Icon(e.icon, color: AppColors.mintDark, size: 22),
      ),
      title: Text(e.title),
      subtitle: e.subtitle == null ? null : Text(e.subtitle!),
      trailing: e.id == 'export' && _exporting
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right_rounded),
      onTap: e.onTap,
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ScreenHeader(subtitle: s.appName, title: s.moreTitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
              child: TextField(
                key: const Key('moreSearch'),
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: s.moreSearchHint),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (q.isEmpty)
              Container(
                key: const Key('moreProfileCard'),
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(18)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => context.push(Routes.ownerProfile),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        InitialsAvatar(
                          session.user?.name.isNotEmpty == true
                              ? session.user!.name
                              : (session.company?.name ?? s.appName),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.company?.name ?? s.appName,
                                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                              ),
                              Text(
                                [
                                  session.user?.name ?? '',
                                  Phones.display(session.user?.phone ?? ''),
                                ].where((t) => t.isNotEmpty).join(' · '),
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13.5),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
              ),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(s.nothingFound, key: const Key('moreNothing'), textAlign: TextAlign.center),
              ),
            for (final (title, entries) in shown) ...[
              SectionHeader(title),
              Card(child: Column(children: [for (final e in entries) tile(e)])),
            ],
            if (q.isEmpty)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.translate_rounded, color: AppColors.mintDark, size: 22),
                      ),
                      title: Text(s.language),
                      trailing: LanguageToggle(value: lang, onChanged: (v) => setAppLanguage(ref, v)),
                    ),
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: AppColors.redLight, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.logout_rounded, color: AppColors.red, size: 22),
                      ),
                      title: Text(s.logout, style: const TextStyle(color: AppColors.red)),
                      onTap: () async {
                        if (await confirmDialog(context, title: s.logout, message: s.logoutConfirm)) {
                          await ref.read(authControllerProvider.notifier).logout();
                        }
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One place in More; found by its words in either language.
class _Entry {
  const _Entry(this.id, this.icon, this.title, this.subtitle, this.keywords, this.onTap);
  final String id;
  final IconData icon;
  final String title;
  final String? subtitle;
  final String keywords;
  final VoidCallback onTap;

  bool matches(String q) => '$title ${subtitle ?? ''} $keywords'.toLowerCase().contains(q);
}
