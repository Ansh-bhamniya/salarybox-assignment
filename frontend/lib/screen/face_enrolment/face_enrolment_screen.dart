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
import '../../widgets/primary_button.dart';
import '../../bloc/face_enrolment/face_enrolment_cubit.dart';
import '../../bloc/face_enrolment/face_enrolment_state.dart';
import '../../bloc/face_capture/face_capture_cubit.dart';
import '../../bloc/face_capture/face_capture_state.dart';
import '../../config/theme/app_spacing.dart';
import '../../config/theme/app_icons.dart';

class FaceEnrolmentScreen extends StatelessWidget {
  const FaceEnrolmentScreen({
    super.key,
    required this.staffId,
    required this.staffName,
  });

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
        title: Text('Enrol face — $staffName'),
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
            ..showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                behavior: SnackBarBehavior.floating,
              ),
            );
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
              BlocBuilder<FaceCaptureCubit, FaceCaptureState>(
                builder: (context, state) => _buildBody(context, state),
              ),
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
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );

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
            FaceCameraView(
              camera: cubit.camera,
              busy: processing,
              onCapture: cubit.captureAndProcess,
            ),
            LoadingOverlay(visible: processing, message: 'Analyzing face…'),
          ],
        );

      case FaceCaptureStatus.ready:
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
                          shape: OvalBorder(
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.primaryFixedDim,
                              width: 3,
                            ),
                          ),
                        ),
                        // The live preview is mirrored but the saved photo isn't,
                        // so un-flipped it would "jump" the moment you tap the
                        // shutter. Show it mirrored to match what you just saw;
                        // the file that gets uploaded stays true-orientation.
                        child: ClipOval(
                          child: Transform.flip(
                            flipX: true,
                            child: Image.file(
                              File(state.photoPath!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Face captured',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Check that your face is clear and well lit.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: cubit.retake,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Save enrolment',
                        onPressed: () =>
                            context.read<FaceEnrolmentCubit>().submit(
                              staffId: staffId,
                              photoPath: state.photoPath!,
                              embedding: state.embedding!,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
    }
  }
}
