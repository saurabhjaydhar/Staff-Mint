import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_exception.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/json.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/common.dart';

/// Opens a rounded, keyboard-aware bottom sheet. Resolves to true when it saved.
Future<bool> showEditSheet(BuildContext context, Widget child) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), child: child),
      ),
    ) ??
    false;

/// Error from the API, pinned to a field when the server names one.
({String? field, String message}) apiFieldError(BuildContext context, Object e) {
  if (e is ApiException) {
    final d = e.details;
    final field = d is Map ? d['field']?.toString() : null;
    return (field: field, message: errorMessage(context, e));
  }
  return (field: null, message: errorMessage(context, e));
}

class SheetTitle extends StatelessWidget {
  const SheetTitle(this.title, {super.key, this.subtitle, this.icon});
  final String title;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: AppColors.mintDark),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 13.5)),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Primary save button with a spinner.
class SaveButton extends StatelessWidget {
  const SaveButton({super.key, required this.label, required this.busy, required this.onPressed});
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: FilledButton(
      key: const Key('sheetSave'),
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
            )
          : Text(label),
    ),
  );
}

/// One text value: name or email.
class TextFieldSheet extends StatefulWidget {
  const TextFieldSheet({
    super.key,
    required this.title,
    required this.initial,
    required this.onSave,
    this.icon,
    this.hint,
    this.keyboardType,
    this.validator,
    this.allowEmpty = false,
  });
  final String title;
  final String initial;
  final IconData? icon;
  final String? hint;
  final TextInputType? keyboardType;
  final String? Function(String)? validator;
  final bool allowEmpty;
  final Future<void> Function(String value) onSave;

  @override
  State<TextFieldSheet> createState() => _TextFieldSheetState();
}

class _TextFieldSheetState extends State<TextFieldSheet> {
  late final _c = TextEditingController(text: widget.initial);
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(_c.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = apiFieldError(context, e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(widget.title, subtitle: widget.hint, icon: widget.icon),
          TextFormField(
            key: const Key('sheetField'),
            controller: _c,
            autofocus: true,
            keyboardType: widget.keyboardType,
            textCapitalization: widget.keyboardType == TextInputType.emailAddress
                ? TextCapitalization.none
                : TextCapitalization.words,
            decoration: InputDecoration(labelText: widget.title, errorText: _error),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return widget.allowEmpty ? null : s.requiredField;
              return widget.validator?.call(t);
            },
            onFieldSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 20),
          SaveButton(label: s.save, busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}

final emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
final ifscRe = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
final upiRe = RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$');

/// Bank account or UPI for salary. The account number is typed twice.
class BankSheet extends StatefulWidget {
  const BankSheet({super.key, this.initial, required this.defaultHolder, required this.onSave, this.onRemove});
  final BankInfo? initial;
  final String defaultHolder;
  final Future<void> Function(Json bank) onSave;
  final Future<void> Function()? onRemove;

  @override
  State<BankSheet> createState() => _BankSheetState();
}

class _BankSheetState extends State<BankSheet> {
  final _form = GlobalKey<FormState>();
  late final _holder = TextEditingController(text: widget.initial?.holderName ?? widget.defaultHolder);
  final _account = TextEditingController();
  final _confirm = TextEditingController();
  late final _ifsc = TextEditingController(text: widget.initial?.ifsc ?? '');
  late final _upi = TextEditingController(text: widget.initial?.upiId ?? '');
  bool _busy = false;
  String? _error;
  final Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    for (final c in [_holder, _account, _confirm, _ifsc, _upi]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The server only ever returns the last 4 digits, so an existing account
  /// must be typed again on edit (see the validator); otherwise saving would
  /// silently drop it.
  Future<void> _save() async {
    final s = context.s;
    setState(() {
      _error = null;
      _fieldErrors.clear();
    });
    if (!_form.currentState!.validate()) return;
    final account = _account.text.replaceAll(' ', '');
    final upi = _upi.text.trim();
    if (account.isEmpty && upi.isEmpty) {
      setState(() => _error = s.bankOrUpi);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSave({
        'holderName': _holder.text.trim(),
        'accountNumber': account.isEmpty ? null : account,
        'ifsc': account.isEmpty ? null : _ifsc.text.trim().toUpperCase(),
        'upiId': upi.isEmpty ? null : upi,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final err = apiFieldError(context, e);
      setState(() => err.field == null ? _error = err.message : _fieldErrors[err.field!] = err.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final s = context.s;
    if (!await confirmDialog(context, title: s.removeSalaryAccount, destructive: true)) return;
    setState(() => _busy = true);
    try {
      await widget.onRemove!();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = apiFieldError(context, e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final hadAccount = widget.initial?.hasAccount ?? false;
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(s.salaryAccountBi.text, subtitle: s.salaryAccountHint, icon: Icons.account_balance_rounded),
          TextFormField(
            key: const Key('bankHolder'),
            controller: _holder,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: s.accountHolder, errorText: _fieldErrors['holderName']),
            validator: (v) => (v ?? '').trim().length < 2 ? s.requiredField : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('bankAccount'),
            controller: _account,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(18)],
            decoration: InputDecoration(
              labelText: s.accountNumber,
              hintText: hadAccount ? '•••• ${widget.initial!.accountLast4}' : null,
              errorText: _fieldErrors['accountNumber'],
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return hadAccount ? s.retypeAccount : null;
              return RegExp(r'^\d{9,18}$').hasMatch(t) ? null : s.invalidAccount;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('bankAccountConfirm'),
            controller: _confirm,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(18)],
            decoration: InputDecoration(labelText: s.confirmAccountNumber),
            validator: (v) => _account.text.isNotEmpty && v != _account.text ? s.accountsDontMatch : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('bankIfsc'),
            controller: _ifsc,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [LengthLimitingTextInputFormatter(11)],
            decoration: InputDecoration(
              labelText: s.ifscLabel,
              hintText: 'SBIN0001234',
              errorText: _fieldErrors['ifsc'],
            ),
            validator: (v) {
              final t = (v ?? '').trim().toUpperCase();
              if (_account.text.isEmpty) return null;
              if (t.isEmpty) return s.requiredField;
              return ifscRe.hasMatch(t) ? null : s.invalidIfsc;
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(s.or, style: const TextStyle(color: AppColors.muted)),
                ),
                const Expanded(child: Divider()),
              ],
            ),
          ),
          TextFormField(
            key: const Key('bankUpi'),
            controller: _upi,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: s.upiLabel,
              hintText: 'name@okaxis',
              prefixIcon: const Icon(Icons.qr_code_2_rounded),
              errorText: _fieldErrors['upiId'],
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              return t.isEmpty || upiRe.hasMatch(t) ? null : s.invalidUpi;
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 18, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(s.ownerNotifiedBank, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                key: const Key('sheetError'),
                style: const TextStyle(color: AppColors.red),
              ),
            ),
          const SizedBox(height: 18),
          SaveButton(label: s.save, busy: _busy, onPressed: _save),
          if (widget.initial != null && widget.onRemove != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
              onPressed: _busy ? null : _remove,
              child: Text(s.removeLabel),
            ),
        ],
      ),
    );
  }
}

/// Emergency contact: name, phone and a relation picked from chips.
class EmergencySheet extends StatefulWidget {
  const EmergencySheet({super.key, this.initial, required this.onSave});
  final EmergencyContact? initial;
  final Future<void> Function(EmergencyContact? contact) onSave;

  @override
  State<EmergencySheet> createState() => _EmergencySheetState();
}

class _EmergencySheetState extends State<EmergencySheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _phone = TextEditingController(text: Phones.normalize(widget.initial?.phone ?? '') ?? '');
  late String? _relation = widget.initial?.relation;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save({bool clear = false}) async {
    if (!clear && !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(
        clear
            ? null
            : EmergencyContact(
                name: _name.text.trim(),
                phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                relation: _relation,
              ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = apiFieldError(context, e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(s.emergencyBi.text, subtitle: s.emergencyHint, icon: Icons.contact_emergency_rounded),
          TextFormField(
            key: const Key('emergencyName'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: s.contactName),
            validator: (v) => (v ?? '').trim().length < 2 ? s.requiredField : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('emergencyPhone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            decoration: InputDecoration(labelText: s.contactPhone, prefixText: '+91 '),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return s.requiredField;
              return Phones.normalize(t) == null ? s.invalidPhone : null;
            },
          ),
          const SizedBox(height: 14),
          Text(s.relationLabel, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in s.relations)
                ChoiceChip(
                  label: Text(r),
                  selected: _relation == r,
                  onSelected: (on) => setState(() => _relation = on ? r : null),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: const TextStyle(color: AppColors.red)),
            ),
          const SizedBox(height: 20),
          SaveButton(label: s.save, busy: _busy, onPressed: _save),
          if (widget.initial != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
              onPressed: _busy ? null : () => _save(clear: true),
              child: Text(s.removeLabel),
            ),
        ],
      ),
    );
  }
}

/// New mobile number → code on that number → verified change.
class PhoneChangeSheet extends StatefulWidget {
  const PhoneChangeSheet({super.key, required this.onRequest, required this.onVerify});
  final Future<String?> Function(String phone) onRequest;
  final Future<void> Function(String phone, String code) onVerify;

  @override
  State<PhoneChangeSheet> createState() => _PhoneChangeSheetState();
}

class _PhoneChangeSheetState extends State<PhoneChangeSheet> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  String? _devCode;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() step) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await step();
    } catch (e) {
      if (mounted) setState(() => _error = apiFieldError(context, e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final phone = Phones.normalize(_phone.text);
    if (phone == null) {
      setState(() => _error = context.s.invalidPhone);
      return;
    }
    await _run(() async {
      final dev = await widget.onRequest(phone);
      if (mounted) {
        setState(() {
          _codeSent = true;
          _devCode = dev;
        });
      }
    });
  }

  Future<void> _verify() async {
    final phone = Phones.normalize(_phone.text)!;
    await _run(() async {
      await widget.onVerify(phone, _code.text.trim());
      if (mounted) Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle(
          s.changeMobile,
          subtitle: _codeSent ? s.codeSentTo(Phones.display(_phone.text)) : s.changeMobileHint,
          icon: Icons.phone_iphone_rounded,
        ),
        if (!_codeSent)
          TextField(
            key: const Key('newPhone'),
            controller: _phone,
            autofocus: true,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            decoration: InputDecoration(labelText: s.newMobile, prefixText: '+91 ', errorText: _error),
            onSubmitted: (_) => _send(),
          )
        else ...[
          if (_devCode != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.mintFaint, borderRadius: BorderRadius.circular(12)),
              child: Text(s.devCodeHint(_devCode!)),
            ),
          TextField(
            key: const Key('phoneCode'),
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.w700),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            decoration: InputDecoration(hintText: '••••••', errorText: _error),
            onSubmitted: (_) => _verify(),
          ),
        ],
        const SizedBox(height: 20),
        SaveButton(
          label: _codeSent ? s.verifyAndChange : s.sendCode,
          busy: _busy,
          onPressed: _codeSent ? _verify : _send,
        ),
      ],
    );
  }
}
