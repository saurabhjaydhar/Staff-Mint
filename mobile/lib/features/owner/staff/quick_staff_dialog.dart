import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';

/// Minimal "name + phone + monthly salary" dialog used during setup.
Future<NewEmployee?> showQuickStaffDialog(BuildContext context) {
  final name = TextEditingController();
  final phone = TextEditingController();
  final salary = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final s = context.s;
  return showDialog<NewEmployee>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.addStaff),
      content: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: s.name),
                validator: (v) => (v ?? '').trim().isEmpty ? s.required : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                decoration: InputDecoration(labelText: s.phone, prefixText: '+91 '),
                validator: (v) => Phones.isValid(v ?? '') ? null : s.invalidPhone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: salary,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: '${s.monthlySalary} (${s.optional})', prefixText: '₹ '),
                validator: (v) => (v ?? '').trim().isEmpty || Money.parseRupees(v!) != null ? null : s.invalidAmount,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
        FilledButton(
          onPressed: () {
            if (!(formKey.currentState?.validate() ?? false)) return;
            final rate = Money.parseRupees(salary.text);
            Navigator.pop(
              ctx,
              NewEmployee(
                name: name.text.trim(),
                phone: Phones.normalize(phone.text)!,
                wageType: rate == null ? null : 'monthly',
                ratePaise: rate,
              ),
            );
          },
          child: Text(s.add),
        ),
      ],
    ),
  );
}
