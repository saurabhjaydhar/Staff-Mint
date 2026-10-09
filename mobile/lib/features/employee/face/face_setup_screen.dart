import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_controller.dart';
import '../punch/punch_capture.dart';

final myFaceProvider = FutureProvider.autoDispose<FaceInfo>((ref) => ref.watch(meApiProvider).myFace());

/// Staff face check: explicit consent, one live photo, then the owner
/// approves it. The photo can be retaken or removed (consent withdrawn).
class FaceSetupScreen extends ConsumerStatefulWidget {
  const FaceSetupScreen({super.key});

  @override
  ConsumerState<FaceSetupScreen> createState() => _FaceSetupScreenState();
}

class _FaceSetupScreenState extends ConsumerState<FaceSetupScreen> {
  bool _agreed = false;
  bool _busy = false;

  /// Shows the consent form again for a retake.
  bool _retaking = false;

  Future<void> _take() async {
    final s = context.s;
    final photo = await ref.read(punchCaptureProvider).selfie(context, live: true);
    if (photo == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(meApiProvider).enrollFace(photo);
      if (!mounted) return;
      showSnack(context, s.faceSent);
      setState(() {
        _retaking = false;
        _agreed = false;
      });
      ref.invalidate(myFaceProvider);
      await ref.read(authControllerProvider.notifier).refreshMe();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'FACE_NOT_CLEAR') {
        final reason = e.details is Map ? (e.details! as Map)['reason'] : null;
        showSnack(context, s.livenessHint(reason == 'many_faces' ? 'manyFaces' : 'noFace').joined, error: true);
      } else {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final s = context.s;
    if (!await confirmDialog(context, title: s.faceRemove, message: s.faceRemoveConfirm, destructive: true)) return;
    setState(() => _busy = true);
    try {
      await ref.read(meApiProvider).withdrawFace();
      if (!mounted) return;
      showSnack(context, s.faceRemoved);
      ref.invalidate(myFaceProvider);
      await ref.read(authControllerProvider.notifier).refreshMe();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final face = ref.watch(myFaceProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.faceCheckBi.joined)),
      body: face.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myFaceProvider)),
        data: (f) => f.isNone || _retaking ? _consent(s, retake: !f.isNone) : _status(s, f),
      ),
    );
  }

  Widget _consent(S s, {required bool retake}) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Center(child: Icon(Icons.face_retouching_natural_rounded, size: 72, color: AppColors.mint)),
      const SizedBox(height: 12),
      Text(s.faceSetupTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(
        s.faceSetupIntro,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 20),
      Card(
        child: CheckboxListTile(
          key: const Key('faceConsentBox'),
          value: _agreed,
          onChanged: _busy ? null : (v) => setState(() => _agreed = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(s.faceConsentText, style: const TextStyle(fontSize: 14, height: 1.4)),
        ),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        key: const Key('faceAgree'),
        onPressed: _agreed && !_busy ? _take : null,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.camera_front_rounded),
        label: Text(s.faceAgreeAndTake),
      ),
      TextButton(
        onPressed: _busy ? null : () => retake ? setState(() => _retaking = false) : Navigator.of(context).maybePop(),
        child: Text(retake ? s.cancel : s.faceNotNow),
      ),
    ],
  );

  Widget _status(S s, FaceInfo f) {
    final bi = f.isApproved ? s.faceApprovedBi : s.facePendingBi;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ClipOval(
            child: f.photoUrl == null
                ? const SizedBox(width: 160, height: 160, child: Icon(Icons.person, size: 80))
                : Image.network(
                    f.photoUrl!,
                    width: 160,
                    height: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const SizedBox(width: 160, height: 160, child: Icon(Icons.person, size: 80)),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              f.isApproved ? Icons.verified_rounded : Icons.hourglass_top_rounded,
              color: f.isApproved ? AppColors.mint : AppColors.amberDark,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(bi.text, key: const Key('faceStatusText'), style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        if (bi.hint != null)
          Text(
            bi.hint!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => setState(() => _retaking = true),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(s.faceRetake),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const Key('faceRemove'),
          style: TextButton.styleFrom(foregroundColor: AppColors.red),
          onPressed: _busy ? null : _remove,
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(s.faceRemove),
        ),
      ],
    );
  }
}
