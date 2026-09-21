import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../config/di/service_locator.dart';
import '../../widgets/camera_status_view.dart';
import '../../widgets/pose_camera_view.dart';
import '../../widgets/loading_overlay.dart';
import '../../bloc/face_enrolment/face_enrolment_cubit.dart';
import '../../bloc/face_enrolment/face_enrolment_state.dart';
import '../../bloc/face_capture/face_capture_cubit.dart';
import '../../bloc/face_capture/face_capture_state.dart';
import '../../config/theme/app_spacing.dart';
import '../../config/theme/app_icons.dart';
import '../../widgets/app_back_button.dart';
import '../../models/face_match_result.dart';
import './enrolment_dialogs.dart';

class FaceEnrolmentScreen extends StatelessWidget {
  const FaceEnrolmentScreen({super.key, required this.staffId, required this.staffName, this.isReEnrol = false});

  final String staffId;
  final String staffName;

  /// Replacing an existing enrolment: the admin is asked why before it is saved.
  final bool isReEnrol;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<FaceCaptureCubit>()..initializeCamera()),
        BlocProvider(create: (_) => sl<FaceEnrolmentCubit>()),
      ],
      child: _FaceEnrolmentView(staffId: staffId, staffName: staffName, isReEnrol: isReEnrol),
    );
  }
}

class _FaceEnrolmentView extends StatefulWidget {
  const _FaceEnrolmentView({required this.staffId, required this.staffName, required this.isReEnrol});

  final String staffId;
  final String staffName;
  final bool isReEnrol;

  @override
  State<_FaceEnrolmentView> createState() => _FaceEnrolmentViewState();
}

class _FaceEnrolmentViewState extends State<_FaceEnrolmentView> {
  /// Why an existing enrolment is being replaced (re-enrolment only).
  String? _reEnrolReason;

  Future<void> _save(List<FaceSample> shots) async {
    if (widget.isReEnrol) {
      final reason = await askReEnrolReason(context);
      if (reason == null || !mounted) return;
      _reEnrolReason = reason;
    }
    if (!mounted) return;
    context.read<FaceEnrolmentCubit>().submit(staffId: widget.staffId, shots: shots, reason: _reEnrolReason);
  }

  /// The backend says this face already belongs to someone else. The admin can
  /// cancel, or enrol anyway with a reason (which is audited).
  Future<void> _onDuplicate(FaceEnrolmentSubmitState state) async {
    final enrolment = context.read<FaceEnrolmentCubit>();
    final shots = context.read<FaceCaptureCubit>().state.shots;

    final reason = await confirmDuplicate(context, state.duplicates);
    if (reason == null || !mounted) {
      enrolment.dismissDuplicate();
      return;
    }
    enrolment.submit(staffId: widget.staffId, shots: shots, reason: reason, allowDuplicate: true);
  }

  @override
  Widget build(BuildContext context) {
    // The camera is always dark; the review of the photos afterwards follows the app's light or dark theme.
    final followsTheme = context.select<FaceCaptureCubit, bool>(
      (cubit) => cubit.state.status == FaceCaptureStatus.ready,
    );
    final theme = Theme.of(context);
    final foreground = followsTheme ? theme.colorScheme.onSurface : Colors.white;

    return Scaffold(
      backgroundColor: followsTheme ? theme.colorScheme.surface : Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: AppBackButton(onDark: !followsTheme),
        leadingWidth: AppBackButton.leadingWidth,
        title: Text('Enrol face — ${widget.staffName}'),
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(color: foreground, fontWeight: FontWeight.w800),
        backgroundColor: Colors.transparent,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: followsTheme
            ? (theme.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            : SystemUiOverlayStyle.light,
      ),
      body: BlocListener<FaceCaptureCubit, FaceCaptureState>(
        listenWhen: (previous, current) => current.errorMessage != null,
        listener: (context, state) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.errorMessage!), behavior: SnackBarBehavior.floating));
        },
        child: BlocListener<FaceEnrolmentCubit, FaceEnrolmentSubmitState>(
          listenWhen: (previous, current) => current.status != previous.status,
          listener: (context, state) {
            if (state.status == FaceEnrolmentSubmitStatus.duplicateFound) {
              _onDuplicate(state);
            }
            if (state.status == FaceEnrolmentSubmitStatus.error) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(state.errorMessage ?? 'Enrolment failed'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            }
            if (state.status == FaceEnrolmentSubmitStatus.success) {
              // Enrolment complete — collapse back to the staff list rather
              // than leaving the admin stuck on the review screen.
              while (context.canPop()) {
                context.pop();
              }
            }
          },
          child: Stack(
            children: [
              BlocBuilder<FaceCaptureCubit, FaceCaptureState>(builder: (context, state) => _buildBody(context, state)),
              BlocBuilder<FaceEnrolmentCubit, FaceEnrolmentSubmitState>(
                builder: (context, state) => LoadingOverlay(
                  visible: state.status == FaceEnrolmentSubmitStatus.submitting,
                  message: 'Saving enrolment…',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, FaceCaptureState state) {
    final cubit = context.read<FaceCaptureCubit>();

    switch (state.status) {
      case FaceCaptureStatus.initial:
        return const Center(child: CircularProgressIndicator(color: Colors.white));

      case FaceCaptureStatus.error:
        return CameraStatusView(
          icon: AppIcons.cameraOff,
          color: Theme.of(context).colorScheme.primaryFixedDim,
          title: 'Camera unavailable',
          message: state.errorMessage ?? 'Could not open the camera.',
          primaryLabel: 'Try again',
          onPrimary: cubit.initializeCamera,
          secondaryLabel: 'Open Settings',
          onSecondary: Geolocator.openAppSettings,
        );

      case FaceCaptureStatus.cameraReady:
      case FaceCaptureStatus.processing:
        if (cubit.camera.controller == null) return const SizedBox.shrink();
        final processing = state.status == FaceCaptureStatus.processing;
        return Stack(
          children: [
            PoseCameraView(
              camera: cubit.camera,
              guidance: cubit.guidance,
              onFrame: (frame) => cubit.onObservation(frame.observation),
              busy: processing,
            ),
            LoadingOverlay(visible: processing, message: 'Analyzing face…'),
          ],
        );

      case FaceCaptureStatus.ready:
        return _ReviewView(shots: state.shots, onSave: () => _save(state.shots), onRetake: cubit.retake);
    }
  }
}

/// Shown once all the photos are taken: the first one large, the rest as small
/// thumbnails, then one clear primary action (save) with a quieter secondary
/// one (retake) stacked underneath.
class _ReviewView extends StatelessWidget {
  const _ReviewView({required this.shots, required this.onSave, required this.onRetake});

  final List<FaceSample> shots;
  final VoidCallback onSave;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: Column(
          children: [
            const SizedBox(height: kToolbarHeight),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1 / 1.3,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: ShapeDecoration(
                      shape: OvalBorder(side: BorderSide(color: theme.colorScheme.primary, width: 3)),
                    ),
                    // The live preview is mirrored but the saved photo isn't,
                    // so un-flipped it would "jump" the moment you tap the
                    // shutter. Show it mirrored to match what you just saw;
                    // the file that gets uploaded stays true-orientation.
                    child: ClipOval(
                      child: Transform.flip(
                        flipX: true,
                        child: Image.file(File(shots.first.imagePath), fit: BoxFit.cover),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (shots.length > 1) ...[
              const SizedBox(height: AppSpacing.m),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final shot in shots.skip(1))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: ClipOval(
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: Transform.flip(
                            flipX: true,
                            child: Image.file(File(shot.imagePath), fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            Text(
              '${shots.length} photo${shots.length == 1 ? '' : 's'} captured',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              'Check that the face is clear and well lit in each one.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.section),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: onSave, child: const Text('Save enrolment')),
            ),
            const SizedBox(height: AppSpacing.m),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: onRetake, child: const Text('Retake all')),
            ),
            const SizedBox(height: AppSpacing.l),
          ],
        ),
      ),
    );
  }
}
