import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import 'auth_controller.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final session = ref.watch(authControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.mint,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 88, inverted: true),
            const SizedBox(height: 16),
            Text(
              s.appName,
              style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                s.tagline,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            const SizedBox(height: 32),
            if (session.restoreFailed) ...[
              Text(s.networkError, style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.mintDark),
                onPressed: () => ref.read(authControllerProvider.notifier).restore(),
                child: Text(s.retry),
              ),
            ] else
              const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}

/// Simple brand mark (rounded square with a leaf-like "S").
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 64, this.inverted = false});
  final double size;
  final bool inverted;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: inverted ? Colors.white : AppColors.mint,
      borderRadius: BorderRadius.circular(size * 0.28),
    ),
    child: Icon(Icons.eco_rounded, size: size * 0.6, color: inverted ? AppColors.mint : Colors.white),
  );
}
