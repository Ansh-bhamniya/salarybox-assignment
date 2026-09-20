import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../config/di/service_locator.dart';
import '../../widgets/camera_status_view.dart';
import '../../widgets/face_camera_view.dart';
import '../../widgets/loading_overlay.dart';
import '../../bloc/face_enrolment/face_enrolment_cubit.dart';
import '../../bloc/face_enrolment/face_enrolment_state.dart';
import '../../bloc/face_capture/face_capture_cubit.dart';
import '../../bloc/face_capture/face_capture_state.dart';
import '../../config/theme/app_spacing.dart';
import '../../config/theme/app_icons.dart';
import '../../widgets/app_back_button.dart';

class FaceEnrolmentScreen extends StatelessWidget {
  const FaceEnrolmentScreen({super.key, required this.staffId, required this.staffName});

  final String staffId;
  final String staffName;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<FaceCaptureCubit>()..initializeCamera()),
        BlocProvider(create: (_) => sl<FaceEnrolmentCubit>()),
      ],
      child: _FaceEnrolmentView(staffId: staffId, staffName: staffName),
    );
  }
}

class _FaceEnrolmentView extends StatelessWidget {
  const _FaceEnrolmentView({required this.staffId, required this.staffName});

  final String staffId;
  final String staffName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(onDark: true),
        leadingWidth: AppBackButton.leadingWidth,
        title: Text('Enrol face — $staffName'),
        titleTextStyle: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
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
            FaceCameraView(camera: cubit.camera, busy: processing, onCapture: cubit.captureAndProcess),
            LoadingOverlay(visible: processing, message: 'Analyzing face…'),
          ],
        );

      case FaceCaptureStatus.ready:
        return _ReviewView(
          photoPath: state.photoPath!,
          onSave: () => context.read<FaceEnrolmentCubit>().submit(
            staffId: staffId,
            photoPath: state.photoPath!,
            embedding: state.embedding!,
          ),
          onRetake: cubit.retake,
        );
    }
  }
}

/// Shown right after a capture: the photo, then one clear primary action
/// (save) with a quieter secondary one (retake) stacked underneath.
class _ReviewView extends StatelessWidget {
  const _ReviewView({required this.photoPath, required this.onSave, required this.onRetake});

  final String photoPath;
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
                      shape: OvalBorder(side: BorderSide(color: theme.colorScheme.primaryFixedDim, width: 3)),
                    ),
                    // The live preview is mirrored but the saved photo isn't,
                    // so un-flipped it would "jump" the moment you tap the
                    // shutter. Show it mirrored to match what you just saw;
                    // the file that gets uploaded stays true-orientation.
                    child: ClipOval(
                      child: Transform.flip(flipX: true, child: Image.file(File(photoPath), fit: BoxFit.cover)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              'Face captured',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              'Check that your face is clear and well lit.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.section),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onSave,
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                child: const Text('Save enrolment'),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onRetake,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retake'),
              ),
            ),
            const SizedBox(height: AppSpacing.l),
          ],
        ),
      ),
    );
  }
}
