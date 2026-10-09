import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_bottom_bar.dart';
import '../../../core/widgets/common.dart';
import '../../assistant/assistant_controller.dart';
import '../../assistant/mint_sheet.dart';
import '../../assistant/voice_recorder.dart';

/// Owner/manager shell: आज · स्टाफ़ · [🎙 Mint] · सैलरी · और.
/// Tap the mic for Mint as a sheet over the current tab; hold it to talk.
class OwnerShell extends ConsumerStatefulWidget {
  const OwnerShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends ConsumerState<OwnerShell> {
  final _voice = VoiceRecorder();
  bool _recording = false;

  @override
  void dispose() {
    _voice.dispose();
    super.dispose();
  }

  Future<void> _holdStart() async {
    final ok = await _voice.press();
    if (!mounted) return;
    if (!ok) {
      showSnack(context, context.s.micPermissionDenied, error: true);
      return;
    }
    setState(() => _recording = _voice.isRecording);
  }

  Future<void> _holdEnd() async {
    final label = context.s.voiceNote;
    setState(() => _recording = false);
    try {
      final clip = await _voice.release();
      if (clip == null || !mounted) return;
      ref
          .read(assistantControllerProvider.notifier)
          .sendVoice(clip.base64, clip.mime, label, duration: clip.duration)
          .ignore();
      await showMintSheet(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final shell = widget.navigationShell;
    return Scaffold(
      body: shell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_recording)
            Container(
              key: const Key('micRecordingBanner'),
              width: double.infinity,
              color: AppColors.redLight,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.fiber_manual_record, color: AppColors.red, size: 16),
                  const SizedBox(width: 6),
                  Text(s.listening, style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          AppBottomBar(
            currentIndex: shell.currentIndex,
            onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
            items: [
              NavItem(icon: Icons.menu_book_outlined, activeIcon: Icons.menu_book_rounded, label: s.navTodayBi),
              NavItem(icon: Icons.people_outline, activeIcon: Icons.people_rounded, label: s.navStaffBi),
              NavItem(
                icon: Icons.currency_rupee_rounded,
                activeIcon: Icons.currency_rupee_rounded,
                label: s.navSalaryBi,
              ),
              NavItem(icon: Icons.menu_rounded, activeIcon: Icons.menu_rounded, label: s.navMoreBi),
            ],
            center: MintMicButton(
              recording: _recording,
              semanticLabel: '${s.mint} · ${s.holdToTalk}',
              onTap: () => showMintSheet(context),
              onHoldStart: _holdStart,
              onHoldEnd: _holdEnd,
            ),
          ),
        ],
      ),
    );
  }
}
