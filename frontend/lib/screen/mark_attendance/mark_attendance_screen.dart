import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../config/env.dart';
import '../../config/di/service_locator.dart';
import '../../widgets/camera_status_view.dart';
import '../../widgets/pose_camera_view.dart';
import '../../widgets/loading_overlay.dart';
import '../../bloc/auth/auth_cubit.dart';
import '../../bloc/mark_attendance/mark_attendance_cubit.dart';
import '../../bloc/mark_attendance/mark_attendance_state.dart';
import '../../config/theme/app_icons.dart';
import '../../widgets/app_back_button.dart';

class MarkAttendanceScreen extends StatelessWidget {
  const MarkAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.read<AuthCubit>().state.session!;
    return BlocProvider(
      create: (_) => sl<MarkAttendanceCubit>(param1: session.staffId!)..initializeCamera(),
      child: const _MarkAttendanceView(),
    );
  }
}

/// Pushed from the staff home screen; the app bar's back arrow returns
/// there. Pops with `true` once attendance has been recorded.
class _MarkAttendanceView extends StatelessWidget {
  const _MarkAttendanceView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const AppBackButton(onDark: true),
        leadingWidth: AppBackButton.leadingWidth,
        title: const Text('Mark attendance'),
        titleTextStyle: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: BlocConsumer<MarkAttendanceCubit, MarkAttendanceState>(
        listenWhen: (previous, current) =>
            current.status == MarkAttendanceStatus.cameraReady && current.errorMessage != null,
        listener: (context, state) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.errorMessage!), behavior: SnackBarBehavior.floating));
        },
        builder: (context, state) => _buildBody(context, state),
      ),
    );
  }

  /// Calibration aid (see [Env.showMatchScore]); empty in normal builds.
  String _scoreNote(MarkAttendanceState state) {
    final similarity = state.similarity;
    if (!Env.showMatchScore || similarity == null) return '';
    return '\n\nMatch score ${similarity.toStringAsFixed(2)} (needs ${Env.faceMatchThreshold.toStringAsFixed(2)})';
  }

  Widget _buildBody(BuildContext context, MarkAttendanceState state) {
    final cubit = context.read<MarkAttendanceCubit>();

    switch (state.status) {
      case MarkAttendanceStatus.initial:
        return const Center(child: CircularProgressIndicator(color: Colors.white));

      case MarkAttendanceStatus.error:
        return CameraStatusView(
          icon: AppIcons.cameraOff,
          color: Theme.of(context).colorScheme.primaryFixedDim,
          title: 'Camera unavailable',
          message: state.errorMessage ?? 'Something went wrong',
          primaryLabel: 'Try again',
          onPrimary: cubit.initializeCamera,
          secondaryLabel: 'Open Settings',
          onSecondary: Geolocator.openAppSettings,
        );

      case MarkAttendanceStatus.matchFailed:
        return CameraStatusView(
          icon: AppIcons.faceOff,
          color: Theme.of(context).colorScheme.error,
          title: 'Face not recognised',
          message:
              'Your face did not match the enrolled photo, so attendance was not recorded.'
              '${_scoreNote(state)}${_attemptsNote(cubit, state)}',
          primaryLabel: 'Try again',
          onPrimary: cubit.retry,
        );

      case MarkAttendanceStatus.livenessFailed:
        return CameraStatusView(
          icon: AppIcons.faceOff,
          color: Theme.of(context).colorScheme.error,
          title: 'Check not passed',
          message: '${state.errorMessage ?? 'The head-turn check did not pass.'}${_attemptsNote(cubit, state)}',
          primaryLabel: 'Try again',
          onPrimary: cubit.retry,
        );

      case MarkAttendanceStatus.lockedOut:
        return CameraStatusView(
          icon: AppIcons.faceOff,
          color: Theme.of(context).colorScheme.error,
          title: 'Having trouble?',
          message:
              'The check did not pass after ${cubit.maxFailures} tries, so attendance was not recorded. '
              'Please ask your admin for help.',
          primaryLabel: 'Back',
          onPrimary: () => context.pop(false),
        );

      case MarkAttendanceStatus.success:
        return CameraStatusView(
          icon: AppIcons.success,
          color: Theme.of(context).colorScheme.primaryFixedDim,
          title: 'Attendance recorded',
          message: 'Your face, time and location were saved.${_scoreNote(state)}',
          primaryLabel: 'Done',
          onPrimary: () => context.pop(true),
        );

      case MarkAttendanceStatus.processing:
      case MarkAttendanceStatus.cameraReady:
        if (cubit.camera.controller == null) return const SizedBox.shrink();
        final processing = state.status == MarkAttendanceStatus.processing;
        return Stack(
          children: [
            PoseCameraView(camera: cubit.camera, guidance: cubit.guidance, onFrame: cubit.onFrame, busy: processing),
            LoadingOverlay(visible: processing, message: 'Verifying…'),
          ],
        );
    }
  }

  /// How many tries are left before the person is told to ask their admin.
  String _attemptsNote(MarkAttendanceCubit cubit, MarkAttendanceState state) {
    final left = cubit.maxFailures - state.failedAttempts;
    if (left <= 0) return '';
    return '\n\n$left ${left == 1 ? 'try' : 'tries'} left.';
  }
}
