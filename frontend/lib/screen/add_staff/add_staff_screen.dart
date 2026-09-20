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
    final theme = Theme.of(context);

    return BlocProvider(
      create: (_) => sl<AddStaffCubit>(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Add staff')),
        body: BlocConsumer<AddStaffCubit, AddStaffState>(
          listener: (context, state) {
            if (state.status == AddStaffStatus.error) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(state.errorMessage ?? 'Failed to add staff')));
            }
            if (state.status == AddStaffStatus.success) {
              // Staff record created — head straight into face enrolment
              // rather than dropping the admin back on the list, since an
              // unenrolled staff member can't mark attendance yet.
              context.pushReplacement('/staff/${state.staff!.id}/enroll', extra: state.staff!.name);
            }
          },
          builder: (context, state) {
            final submitting = state.status == AddStaffStatus.submitting;
            return SafeArea(
              child: ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.s, AppSpacing.gutter, AppSpacing.xxl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Step 1 of 2 • Staff details',
                        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: const LinearProgressIndicator(value: 0.5, minHeight: 6),
                      ),
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
