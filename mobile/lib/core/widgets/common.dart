import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_exception.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';

/// Localised, human-friendly text for any error.
String errorMessage(BuildContext context, Object error) {
  final s = context.s;
  if (error is ApiException) {
    if (error.isNetwork) return s.networkError;
    switch (error.code) {
      case ApiErrorCode.planLimit:
      case ApiErrorCode.featureNotInPlan:
        return error.message.isNotEmpty ? error.message : s.planLimitError;
      case ApiErrorCode.deviceNotBound:
        return s.deviceNotBound;
      case ApiErrorCode.otpInvalid:
        return s.otpInvalid;
      case ApiErrorCode.forbidden:
        return error.message.isNotEmpty ? error.message : s.forbiddenError;
    }
    return error.message.isNotEmpty ? error.message : s.genericError;
  }
  return s.genericError;
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? AppColors.absent : null));
}

void showError(BuildContext context, Object error) => showSnack(context, errorMessage(context, error), error: true);

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final s = context.s;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.absent) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel ?? s.confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> openUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) showSnack(context, context.s.couldNotOpen, error: true);
}

/// Runs [action], showing errors as a snackbar. Returns true on success.
Future<bool> runGuarded(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showSnack(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
  );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isNetwork = error is ApiException && (error as ApiException).isNetwork;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isNetwork ? Icons.wifi_off_rounded : Icons.error_outline_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              errorMessage(context, error),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(context.s.retry)),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.message, this.icon = Icons.inbox_outlined, this.action});
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey.shade700),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

/// Renders an [AsyncValue] with standard loading / error states.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.data, this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return data(value.requireValue);
    if (value.hasError) return ErrorView(error: value.error!, onRetry: onRetry);
    return const LoadingView();
  }
}

/// A list that supports pull-to-refresh even when it is empty or errored.
class RefreshableList extends StatelessWidget {
  const RefreshableList({super.key, required this.onRefresh, required this.children, this.padding});
  final Future<void> Function() onRefresh;
  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding ?? const EdgeInsets.only(bottom: 96),
      children: children,
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.dense = false});
  final String? status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 12, vertical: dense ? 3 : 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(
        context.s.statusLabel(status),
        style: TextStyle(
          color: Color.lerp(color, Colors.black, 0.35),
          fontWeight: FontWeight.w700,
          fontSize: dense ? 12 : 14,
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 12, 6),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.black87)),
        ),
        ?trailing,
      ],
    ),
  );
}

class FlagChips extends StatelessWidget {
  const FlagChips({super.key, required this.flags});
  final List<String> flags;

  @override
  Widget build(BuildContext context) {
    if (flags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final f in flags)
          Chip(
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.flag_rounded, size: 16, color: AppColors.late),
            label: Text(context.s.flagLabel(f), style: const TextStyle(fontSize: 13)),
            backgroundColor: AppColors.late.withValues(alpha: 0.1),
            side: BorderSide.none,
          ),
      ],
    );
  }
}

/// Small avatar with the person's initials.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.radius = 22});
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first.characters.first.toUpperCase()
        : (parts.first.characters.first + parts.last.characters.first).toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.mintLight,
      child: Text(
        initials,
        style: TextStyle(color: AppColors.mintDark, fontWeight: FontWeight.w700, fontSize: radius * 0.7),
      ),
    );
  }
}

/// Language toggle (English / हिन्दी) as a segmented button.
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    segments: [
      ButtonSegment(value: 'en', label: Text(context.s.english)),
      ButtonSegment(value: 'hi', label: Text(context.s.hindi)),
    ],
    selected: {value},
    showSelectedIcon: false,
    onSelectionChanged: (v) => onChanged(v.first),
  );
}
