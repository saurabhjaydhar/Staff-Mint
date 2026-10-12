import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/api/providers.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/bilingual.dart';
import '../../core/widgets/common.dart';
import '../accounts/accounts_screen.dart';
import '../accounts/past_payslips_screen.dart';
import '../auth/auth_controller.dart';
import '../employee/punch/punch_providers.dart';
import '../setup/setup_screen.dart' show businessIcons;
import 'profile_sheets.dart';

final profileProvider = FutureProvider.autoDispose<Profile>((ref) => ref.watch(profileApiProvider).get());

/// Picks a profile photo; faked in widget tests.
abstract class PhotoPicker {
  /// ~600px JPEG as base64, or null when cancelled.
  Future<String?> pick(ImageSource source);
}

class DevicePhotoPicker implements PhotoPicker {
  @override
  Future<String?> pick(ImageSource source) async {
    final f = await ImagePicker().pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 80,
      requestFullMetadata: false,
    );
    return f == null ? null : base64Encode(await f.readAsBytes());
  }
}

final photoPickerProvider = Provider<PhotoPicker>((ref) => DevicePhotoPicker());

/// One profile for everyone: owner and manager (from More) and staff (tab).
/// Display first; every value opens a focused edit sheet.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, this.showBack = false});
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return Scaffold(
      body: profile.when(
        loading: () => const SafeArea(child: LoadingView(rows: 6)),
        error: (e, _) => SafeArea(
          child: ErrorView(error: e, onRetry: () => ref.invalidate(profileProvider)),
        ),
        data: (p) => RefreshIndicator(
          onRefresh: () async => ref.refresh(profileProvider.future),
          child: _ProfileBody(profile: p, showBack: showBack),
        ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile, required this.showBack});
  final Profile profile;
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final p = profile;
    final api = ref.read(profileApiProvider);

    /// Saved → fresh profile, and the session (name, phone, language) too.
    Future<void> refresh({bool session = false}) async {
      ref.invalidate(profileProvider);
      if (session) await ref.read(authControllerProvider.notifier).refreshMe();
    }

    Future<void> edit(Widget sheet, {bool session = false}) async {
      if (await showEditSheet(context, sheet)) {
        await refresh(session: session);
        if (context.mounted) showSnack(context, s.saved);
      }
    }

    void editName() => edit(
      TextFieldSheet(
        title: s.fullName,
        initial: p.name,
        icon: Icons.badge_rounded,
        onSave: (v) => api.update({'name': v}),
      ),
      session: true,
    );

    void editEmail() => edit(
      TextFieldSheet(
        title: s.emailLabel,
        hint: s.emailHint,
        initial: p.email ?? '',
        icon: Icons.alternate_email_rounded,
        keyboardType: TextInputType.emailAddress,
        allowEmpty: true,
        validator: (v) => emailRe.hasMatch(v) ? null : s.invalidEmail,
        onSave: (v) => api.update({'email': v.isEmpty ? null : v}),
      ),
    );

    Future<void> changePhone() async {
      final ok = await showEditSheet(
        context,
        PhoneChangeSheet(onRequest: api.requestPhoneChange, onVerify: (ph, code) => api.verifyPhoneChange(ph, code)),
      );
      if (!ok) return;
      await refresh(session: true);
      if (context.mounted) showSnack(context, s.mobileChanged);
    }

    void editBank() => edit(
      BankSheet(initial: p.bank, defaultHolder: p.name, onSave: (b) => api.setBank(b), onRemove: api.removeBank),
    );

    void editEmergency() =>
        edit(EmergencySheet(initial: p.emergencyContact, onSave: (c) => api.update({'emergencyContact': c?.toJson()})));

    Future<void> changePhoto() async {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        backgroundColor: AppColors.paper,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(s.changePhoto, style: Theme.of(ctx).textTheme.titleMedium),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: Text(s.takePhoto),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                key: const Key('photoGallery'),
                leading: const Icon(Icons.photo_library_rounded),
                title: Text(s.chooseFromGallery),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              if (p.photoUrl != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
                  title: Text(s.removePhoto, style: const TextStyle(color: AppColors.red)),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
            ],
          ),
        ),
      );
      if (choice == null || !context.mounted) return;
      final ok = await runGuarded(context, () async {
        if (choice == 'remove') {
          await api.removePhoto();
        } else {
          final photo = await ref
              .read(photoPickerProvider)
              .pick(choice == 'camera' ? ImageSource.camera : ImageSource.gallery);
          if (photo == null) return;
          await api.setPhoto(photo);
        }
      });
      if (ok) await refresh();
    }

    void openMissing(String k) => switch (k) {
      'photo' => changePhoto(),
      'name' => editName(),
      'email' => editEmail(),
      'bank' => editBank(),
      _ => editEmergency(),
    };

    Future<void> logout() async {
      if (!await confirmDialog(context, title: s.logout, message: s.logoutConfirm)) return;
      if (p.isStaff) {
        // Try to flush offline punches before the token goes away.
        try {
          await ref.read(punchSyncProvider.notifier).syncNow().timeout(const Duration(seconds: 8));
        } catch (_) {}
      }
      await ref.read(authControllerProvider.notifier).logout();
    }

    Future<void> logoutAll() async {
      if (!await confirmDialog(context, title: s.logoutAll, message: s.logoutAllConfirm, destructive: true)) return;
      if (!context.mounted) return;
      if (await runGuarded(context, api.logoutEverywhere)) {
        await ref.read(authControllerProvider.notifier).logout();
      }
    }

    final session = ref.watch(authControllerProvider);
    final pastSlips = ref.watch(pastPayslipsProvider).value ?? const [];
    final faceOn =
        session.company?.settings.faceMatchPolicy == 'review' || (session.employee?.faceStatus ?? 'none') != 'none';
    final w = p.work;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Hero(profile: p, showBack: showBack, onPhoto: changePhoto),
        if (p.missing.isNotEmpty) _NextStep(profile: p, onTap: openMissing),
        _Section(
          title: s.personalBi,
          children: [
            _Row(
              key: const Key('rowName'),
              icon: Icons.badge_rounded,
              label: s.fullName,
              value: p.name.isEmpty ? null : p.name,
              placeholder: s.notAdded,
              onTap: editName,
            ),
            _Row(
              key: const Key('rowPhone'),
              icon: Icons.phone_iphone_rounded,
              label: s.mobileLabel,
              value: Phones.display(p.phone),
              action: s.change,
              onTap: changePhone,
            ),
            _Row(
              key: const Key('rowEmail'),
              icon: Icons.alternate_email_rounded,
              label: s.emailLabel,
              value: p.email,
              placeholder: s.notAdded,
              onTap: editEmail,
            ),
          ],
        ),
        Padding(
          key: const Key('languageNote'),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(s.languageNote, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ),
        if (w != null)
          _Section(
            title: s.workBi,
            footer: s.setByOwner,
            children: [
              if (w.designation != null)
                _Row(icon: Icons.work_rounded, label: s.designationLabel, value: w.designation, locked: true),
              if (w.joiningDate != null)
                _Row(
                  icon: Icons.event_available_rounded,
                  label: s.joinedOn,
                  value: Dates.prettyApiDate(w.joiningDate!, s.languageCode),
                  locked: true,
                ),
              if (w.shiftStart != null)
                _Row(
                  icon: Icons.schedule_rounded,
                  label: s.shift,
                  value:
                      '${Dates.hhmmToDisplay(w.shiftStart!, s.languageCode)} – ${Dates.hhmmToDisplay(w.shiftEnd ?? '', s.languageCode)}',
                  locked: true,
                ),
              if (w.branchName != null)
                _Row(icon: Icons.storefront_rounded, label: s.branchLabel, value: w.branchName, locked: true),
              _Row(
                icon: Icons.currency_rupee_rounded,
                label: s.salaryLabel,
                value: w.wageType == 'daily'
                    ? s.perDay(Money.format(w.ratePaise))
                    : s.perMonth(Money.format(w.ratePaise)),
                locked: true,
              ),
            ],
          ),
        if (p.isStaff) ...[
          _SectionTitle(s.salaryAccountBi),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: p.bank == null
                ? _AddTile(
                    key: const Key('addBank'),
                    icon: Icons.account_balance_rounded,
                    title: s.addSalaryAccount,
                    subtitle: s.salaryAccountHint,
                    onTap: editBank,
                  )
                : BankCard(bank: p.bank!, onEdit: editBank),
          ),
          _SectionTitle(s.emergencyBi),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: p.emergencyContact == null
                ? _AddTile(
                    key: const Key('addEmergency'),
                    icon: Icons.contact_emergency_rounded,
                    title: s.emergencyBi.text,
                    subtitle: s.emergencyHint,
                    onTap: editEmergency,
                  )
                : Card(
                    margin: EdgeInsets.zero,
                    child: _Row(
                      key: const Key('rowEmergency'),
                      icon: Icons.contact_emergency_rounded,
                      label: [p.emergencyContact!.name, ?p.emergencyContact!.relation].join(' · '),
                      value: p.emergencyContact!.phone == null ? null : Phones.display(p.emergencyContact!.phone!),
                      onTap: editEmergency,
                    ),
                  ),
          ),
        ],
        if (!p.isStaff && p.companyName != null)
          _Section(
            title: s.businessBi,
            children: [
              _Row(
                icon: Icons.storefront_rounded,
                label: p.companyName!,
                value: s.businessTypeLabel(p.businessType ?? 'other'),
              ),
              if (p.planName != null)
                _Row(icon: Icons.workspace_premium_rounded, label: s.planLabel, value: p.planName),
              if (p.role == UserRole.owner)
                _Row(
                  icon: Icons.settings_rounded,
                  label: s.manageBusiness,
                  onTap: () => context.push(Routes.ownerSettings),
                ),
            ],
          ),
        _Section(
          title: s.accountsBi,
          children: [
            // Owner here, staff there: each business this number can open.
            if (session.hasManyAccounts)
              for (final m in session.memberships)
                _Row(
                  key: Key('profileAccount-${m.id}'),
                  icon: businessIcons[m.businessType] ?? Icons.storefront_rounded,
                  label: s.roleLabel(m.role),
                  value: m.companyName,
                  trailing: m.id == session.activeMembershipId
                      ? const Icon(Icons.check_circle_rounded, color: AppColors.mint)
                      : null,
                  onTap: m.id == session.activeMembershipId ? null : () => openAccount(context, ref, m),
                ),
            // Staff, managers and accountants can step away from a business themselves.
            if (session.activeMembership != null && session.activeMembership!.role != UserRole.owner)
              _Row(
                key: const Key('rowLeaveBusiness'),
                icon: Icons.exit_to_app_rounded,
                label: s.leaveBusiness,
                danger: true,
                onTap: () => _confirmLeave(context, ref, session.activeMembership!),
              ),
            _Row(
              key: const Key('rowNewBusiness'),
              icon: Icons.add_business_rounded,
              label: session.memberships.any((m) => m.role == UserRole.owner)
                  ? s.addAnotherBusiness
                  : s.startOwnBusiness,
              placeholder: s.ownBusinessHint,
              onTap: () => context.push(Routes.accountsNew),
            ),
          ],
        ),
        _Section(
          title: s.accountBi,
          children: [
            if (p.isStaff && faceOn)
              _Row(
                key: const Key('faceTile'),
                icon: Icons.face_retouching_natural_rounded,
                label: s.faceCheckBi.text,
                value: s.faceStatusLabel(session.employee?.faceStatus ?? 'none'),
                onTap: () => context.push(Routes.employeeFace),
              ),
            if (pastSlips.isNotEmpty)
              _Row(
                key: const Key('rowPastPayslips'),
                icon: Icons.receipt_long_rounded,
                label: s.pastPayslipsBi.text,
                onTap: () => context.push(Routes.accountsPayslips),
              ),
            _Row(key: const Key('rowLogout'), icon: Icons.logout_rounded, label: s.logout, danger: true, onTap: logout),
            _Row(
              key: const Key('rowLogoutAll'),
              icon: Icons.devices_other_rounded,
              label: s.logoutAll,
              danger: true,
              onTap: logoutAll,
            ),
            _Row(
              key: const Key('rowDeleteAccount'),
              icon: Icons.delete_forever_rounded,
              label: s.deleteAccount,
              danger: true,
              onTap: () => _confirmDelete(context, ref),
            ),
          ],
        ),
        if (p.memberSince != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            child: Text(
              s.memberSince(DateFormat.yMMMM(s.languageCode).format(p.memberSince!.toLocal())),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          )
        else
          const SizedBox(height: 32),
      ],
    );
  }
}

/// Delete the person: explain, send an OTP to their own number, confirm with it.
Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
  final s = context.s;
  final ok = await confirmDialog(
    context,
    title: s.deleteAccount,
    message: s.deleteAccountHint,
    confirmLabel: s.sendCode,
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  final phone = ref.read(authControllerProvider).user?.phone ?? '';
  try {
    await ref.read(authControllerProvider.notifier).requestOtp(phone);
  } catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (!context.mounted) return;
  final code = TextEditingController();
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.deleteAccount),
      content: TextField(
        key: const Key('deleteCode'),
        controller: code,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: s.codeSentToYou),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(s.deleteForever),
        ),
      ],
    ),
  );
  final c = code.text.trim();
  code.dispose();
  if (go != true || !context.mounted) return;
  try {
    await ref.read(authControllerProvider.notifier).deleteAccount(c);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

Future<void> _confirmLeave(BuildContext context, WidgetRef ref, Membership m) async {
  final s = context.s;
  final ok = await confirmDialog(
    context,
    title: s.leaveBusinessConfirm(m.companyName),
    message: s.leaveBusinessBody,
    confirmLabel: s.leaveBusiness,
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  try {
    await ref.read(authControllerProvider.notifier).leaveAccount(m.id);
    if (context.mounted) showSnack(context, s.leftBusiness(m.companyName));
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Ink header: photo with a camera badge, name, role chip, business and phone.
class _Hero extends StatelessWidget {
  const _Hero({required this.profile, required this.showBack, required this.onPhoto});
  final Profile profile;
  final bool showBack;
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = profile;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
          child: Column(
            children: [
              Row(
                children: [
                  if (showBack)
                    IconButton(
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      color: Colors.white,
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => context.pop(),
                    )
                  else
                    const SizedBox(width: 48),
                  Expanded(
                    child: Text(
                      s.navProfileBi.joined,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(right: 8), child: LangPill(inverted: true)),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                key: const Key('avatarButton'),
                onTap: onPhoto,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
                      child: p.photoUrl != null
                          ? CircleAvatar(
                              radius: 46,
                              backgroundImage: NetworkImage(p.photoUrl!),
                              backgroundColor: AppColors.mintLight,
                            )
                          : InitialsAvatar(p.name.isEmpty ? '?' : p.name, radius: 46),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.mint,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.ink, width: 3),
                        ),
                        child: const Icon(Icons.photo_camera_rounded, size: 17, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                p.name.isEmpty ? Phones.display(p.phone) : p.name,
                key: const Key('profileName'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      [s.roleLabel(p.role), ?p.work?.designation].join(' · '),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  if (p.companyName != null)
                    Text(p.companyName!, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                Phones.display(p.phone),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One useful next step with the reason, instead of a "25% complete" ring.
class _NextStep extends StatelessWidget {
  const _NextStep({required this.profile, required this.onTap});
  final Profile profile;
  final ValueChanged<String> onTap;

  static const _staffOrder = ['bank', 'emergency', 'name', 'photo', 'email'];
  static const _otherOrder = ['name', 'email', 'photo', 'bank', 'emergency'];

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final order = profile.isStaff ? _staffOrder : _otherOrder;
    final k = order.firstWhere(profile.missing.contains, orElse: () => profile.missing.first);
    final (icon, title, why) = switch (k) {
      'bank' => ('🏦', s.nextBank, s.nextBankWhy),
      'emergency' => ('🆘', s.nextEmergency, s.nextEmergencyWhy),
      'photo' => ('🙂', s.nextPhoto, s.nextPhotoWhy),
      'name' => ('👤', s.nextName, s.nextNameWhy),
      _ => ('✉️', s.nextEmail, s.nextEmailWhy),
    };
    return Card(
      key: const Key('nextStepCard'),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: AppColors.mintFaint,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                  const SizedBox(height: 2),
                  Text(why, style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(key: Key('missing_$k'), onPressed: () => onTap(k), child: Text(s.add)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final Bi title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title.text, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
        if (title.hint != null) ...[
          const SizedBox(width: 6),
          Text(title.hint!, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.footer});
  final Bi title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SectionTitle(title),
      Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 64, color: AppColors.lineSoft),
              children[i],
            ],
          ],
        ),
      ),
      if (footer != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(footer!, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Icon bubble, small label, bold value; chevron, lock or a custom trailing.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.trailing,
    this.action,
    this.locked = false,
    this.danger = false,
    this.placeholder,
  });
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? action;
  final bool locked;
  final bool danger;

  /// Shown under the label when a data field is empty ("Not added").
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.red : AppColors.mintDark;
    final hasValue = value != null && value!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: danger ? AppColors.redLight : AppColors.mintLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: danger ? AppColors.red : (hasValue ? AppColors.muted : AppColors.ink),
                      fontSize: hasValue ? 13 : 15.5,
                      fontWeight: danger || !hasValue ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (hasValue)
                    Text(value!, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))
                  else if (placeholder != null)
                    Text(placeholder!, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                ],
              ),
            ),
            ?trailing,
            if (trailing == null && action != null)
              Text(
                action!,
                style: const TextStyle(color: AppColors.mintDark, fontWeight: FontWeight.w700),
              ),
            if (trailing == null && action == null && locked)
              const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.muted),
            if (trailing == null && action == null && !locked && onTap != null && !danger)
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Dashed "add" tile for an empty salary account / emergency contact.
class _AddTile extends StatelessWidget {
  const _AddTile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.mintFaint,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: AppColors.mint, width: 1.4),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
              child: const Icon(Icons.add_rounded, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                  Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                ],
              ),
            ),
            Icon(icon, color: AppColors.mintDark),
          ],
        ),
      ),
    ),
  );
}

/// Salary account as a card: masked number, IFSC, holder, and UPI.
class BankCard extends StatelessWidget {
  const BankCard({super.key, required this.bank, this.onEdit});
  final BankInfo bank;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Container(
      key: const Key('bankCard'),
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [AppColors.mintDark, Color(0xFF0E4F33)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [BoxShadow(color: Color(0x33157A4C), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_rounded, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.salaryAccountBi.text,
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                ),
              ),
              if (onEdit != null)
                IconButton(
                  key: const Key('editBank'),
                  tooltip: s.edit,
                  color: Colors.white,
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  onPressed: onEdit,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (bank.hasAccount) ...[
            Text(
              '••••  ••••  ${bank.accountLast4}',
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 2),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _CardField(label: s.accountHolder, value: bank.holderName),
                ),
                if (bank.ifsc != null) _CardField(label: 'IFSC', value: bank.ifsc!),
                const SizedBox(width: 8),
              ],
            ),
          ] else
            _CardField(label: s.accountHolder, value: bank.holderName),
          if (bank.upiId != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'UPI · ${bank.upiId}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardField extends StatelessWidget {
  const _CardField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
      Text(
        value,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ],
  );
}
