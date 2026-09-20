import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../config/di/service_locator.dart';
import '../../widgets/content_width.dart';
import '../../widgets/primary_button.dart';
import '../../bloc/add_staff/add_staff_cubit.dart';
import '../../bloc/add_staff/add_staff_state.dart';
import '../../config/theme/app_spacing.dart';
import '../../config/theme/app_icons.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/step_progress.dart';

class AddStaffScreen extends StatefulWidget {
  const AddStaffScreen({super.key});

  @override
  State<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<AddStaffScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _employeeIdController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _employeeIdController.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    context.read<AddStaffCubit>().submit(
      name: _nameController.text.trim(),
      employeeId: _employeeIdController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AddStaffCubit>(),
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          leadingWidth: AppBackButton.leadingWidth,
          title: const Text('Add staff'),
        ),
        body: BlocConsumer<AddStaffCubit, AddStaffState>(
          listener: (context, state) {
            if (state.status == AddStaffStatus.error) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(state.errorMessage ?? 'Failed to add staff')));
            }
            if (state.status == AddStaffStatus.success) {
              // Hand the new staff back to the list, which shows it and then
              // opens face enrolment (an unenrolled staff member can't mark
              // attendance yet).
              context.pop(state.staff);
            }
          },
          builder: (context, state) {
            final submitting = state.status == AddStaffStatus.submitting;
            return SafeArea(
              child: ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.s,
                    AppSpacing.gutter,
                    AppSpacing.xxl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const StepProgress(step: 1, total: 2, title: 'Staff details'),
                      const SizedBox(height: 24),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: _nameController,
                                  autofocus: true,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Full name',
                                    prefixIcon: Icon(AppIcons.person),
                                  ),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the staff name' : null,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _employeeIdController,
                                  textInputAction: TextInputAction.done,
                                  decoration: const InputDecoration(
                                    labelText: 'Employee ID',
                                    helperText: 'They will use this to log in',
                                    prefixIcon: Icon(AppIcons.idBadge),
                                  ),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter an employee ID' : null,
                                  onFieldSubmitted: (_) => submitting ? null : _submit(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Primary action sits at the bottom, in easy thumb reach.
                      PrimaryButton(
                        label: 'Next: Enrol face',
                        loading: submitting,
                        onPressed: submitting ? null : () => _submit(context),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
