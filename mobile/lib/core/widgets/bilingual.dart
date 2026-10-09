import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
import '../api/providers.dart';
import '../i18n/locale_provider.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';

/// Hindi label with a small English hint underneath (only in Hindi mode).
class BilingualLabel extends StatelessWidget {
  const BilingualLabel(
    this.label, {
    super.key,
    this.style,
    this.hintStyle,
    this.textAlign,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.maxLines,
  });
  final Bi label;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final TextAlign? textAlign;
  final CrossAxisAlignment crossAxisAlignment;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final hint = label.hint;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(label.text, style: base, textAlign: textAlign, maxLines: maxLines, overflow: TextOverflow.ellipsis),
        if (hint != null)
          Text(
            hint,
            textAlign: textAlign,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                hintStyle ??
                base.copyWith(
                  fontSize: (base.fontSize ?? 15) * 0.72,
                  fontWeight: FontWeight.w500,
                  color: (base.color ?? AppColors.ink).withValues(alpha: 0.7),
                  height: 1.1,
                ),
          ),
      ],
    );
  }
}

/// Switches the UI language, persists it and tells the server (best effort).
void setAppLanguage(WidgetRef ref, String code) {
  ref.read(localeProvider.notifier).setLanguage(code);
  if (ref.read(authControllerProvider).isAuthenticated) {
    ref.read(meApiProvider).update(language: code).ignore();
  }
}

/// The small outlined "हि / En" pill in every screen header.
class LangPill extends ConsumerWidget {
  const LangPill({super.key, this.inverted = false});
  final bool inverted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeProvider);
    final color = inverted ? Colors.white : AppColors.ink;
    return Semantics(
      button: true,
      label: context.s.switchLanguage,
      excludeSemantics: true,
      child: InkWell(
        key: const Key('langPill'),
        borderRadius: BorderRadius.circular(999),
        onTap: () => setAppLanguage(ref, lang == 'hi' ? 'en' : 'hi'),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 1.5),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'हि',
                    style: TextStyle(fontWeight: lang == 'hi' ? FontWeight.w800 : FontWeight.w500),
                  ),
                  const TextSpan(text: ' / '),
                  TextSpan(
                    text: 'En',
                    style: TextStyle(fontWeight: lang == 'en' ? FontWeight.w800 : FontWeight.w500),
                  ),
                ],
              ),
              style: TextStyle(fontSize: 13.5, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tab-screen header from the design: small muted line, big ink title,
/// optional actions and the language pill.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.showLang = true});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showLang;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 8, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
                  ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.15),
                ),
              ],
            ),
          ),
          ...actions,
          if (showLang) const LangPill(),
        ],
      ),
    );
  }
}
