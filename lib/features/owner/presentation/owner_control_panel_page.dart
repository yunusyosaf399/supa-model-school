import 'package:flutter/material.dart';

import '../../auth/data/owner_auth_gateway.dart';
import 'owner_initial_setup_form.dart';
import '../data/owner_user_management_repository.dart';
import 'owner_user_control_panel_page.dart';

/// Owner Settings: atomic, audited one-time school setup; password management
/// stays in Supabase Auth. Further school changes require a future workflow.
class OwnerControlPanelPage extends StatefulWidget {
  const OwnerControlPanelPage({
    super.key,
    required this.owner,
    required this.onChangePassword,
    required this.onPasswordChanged,
    required this.onSaveSetup,
    required this.onSetupSaved,
    required this.onOpenAcademicStructure,
    this.userManagementRepository,
  });

  final OwnerAccess owner;
  final Future<void> Function(String currentPassword, String newPassword)
      onChangePassword;
  final VoidCallback onPasswordChanged;
  final Future<OwnerAccess> Function(OwnerInitialSetupRequest) onSaveSetup;
  final ValueChanged<OwnerAccess> onSetupSaved;
  final VoidCallback onOpenAcademicStructure;
  final OwnerUserManagementRepository? userManagementRepository;

  @override
  State<OwnerControlPanelPage> createState() =>
      _OwnerControlPanelPageState();
}

class _OwnerControlPanelPageState extends State<OwnerControlPanelPage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  bool _passwordVisible = false;
  bool _showUserManagement = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onChangePassword(_current.text, _new.text);
      _current.clear();
      _new.clear();
      _confirm.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
            'Password updated. Sign in again with your new password.')),
      );
      widget.onPasswordChanged();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Password could not be changed. Verify your current '
            'password, strength requirements and account session.'),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo=widget.userManagementRepository;
    if(_showUserManagement && repo!=null) {
      return OwnerUserControlPanelPage(
        owner:widget.owner,
        repository:repo,
        onBack:()=>setState(()=>_showUserManagement=false),
      );
    }
    final owner = widget.owner;
    final pendingCurrency = owner.currencyCode == 'XXX';
    final pendingTimezone = owner.timezoneName == 'Etc/UTC';

    return ListView(
      key: const Key('owner-control-panel'),
      padding: const EdgeInsets.all(18),
      children: [
        Text('Owner Control Panel',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            )),
        const SizedBox(height: 6),
        Text('School setup and account security • ${owner.schoolName}'),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('School configuration',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('Setup status: ${owner.setupComplete ? 'Complete' : 'Pending'}'),
                const SizedBox(height: 12),
                _field('School', owner.schoolName),
                _field('Currency', pendingCurrency
                    ? 'Not configured (XXX)' : owner.currencyCode),
                _field('Timezone', pendingTimezone
                    ? 'Not configured (Etc/UTC)' : owner.timezoneName),
                _field('Campus', owner.campuses.map((c) => c.name).join(', ')),
                _field('Academic year', owner.activeYearLabel ??
                    'Not configured'),
                if (owner.activeYearStartsOn != null)
                  _field('Dates', '${owner.activeYearStartsOn} to '
                      '${owner.activeYearEndsOn}'),
                const SizedBox(height: 8),
                Text(owner.setupComplete
                    ? 'Initial setup is complete. Future updates will use '
                      'separately audited Owner Settings operations.'
                    : 'Please enter actual school settings below. '
                      'The temporary configuration cannot be used for '
                      'real finance or attendance operations.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (owner.setupComplete && widget.userManagementRepository!=null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Users & Access Control',
                    style:Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height:8),
                  const Text('Invite Principals, teachers and other staff. '
                    'Assign a campus, review invitations and activate or '
                    'deactivate roles. User passwords remain private.'),
                  const SizedBox(height:12),
                  FilledButton.icon(
                    key:const Key('owner-open-user-management'),
                    icon:const Icon(Icons.manage_accounts_outlined),
                    onPressed:()=>setState(()=>_showUserManagement=true),
                    label:const Text('Manage Users & Roles'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height:12),
        ],
        if (owner.setupComplete) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Academic Structure',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const Text('Create classes and sections for your active '
                      'academic year. Student admissions will use these '
                      'authorized campus/class/section records.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('open-academic-setup'),
                    onPressed: widget.onOpenAcademicStructure,
                    icon: const Icon(Icons.school_outlined),
                    label: const Text('Manage Classes & Sections'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (!owner.setupComplete) ...[
          OwnerInitialSetupForm(
            owner: owner,
            onSave: widget.onSaveSetup,
            onSaved: widget.onSetupSaved,
          ),
          const SizedBox(height: 12),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Account & Security',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text('Change your Supabase Auth password. '
                      'You will need to sign in again afterwards.'),
                  const SizedBox(height: 18),
                  TextFormField(
                    key: const Key('owner-current-password'),
                    controller: _current,
                    obscureText: !_passwordVisible,
                    decoration: const InputDecoration(
                      labelText: 'Current password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (v) => v == null || v.isEmpty
                        ? 'Enter current password' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('owner-new-password'),
                    controller: _new,
                    obscureText: !_passwordVisible,
                    decoration: const InputDecoration(
                      labelText: 'New password',
                      helperText: 'Use at least 12 characters.',
                      prefixIcon: Icon(Icons.key),
                    ),
                    validator: (v) {
                      if (v == null || v.length < 12) {
                        return 'Use at least 12 characters';
                      }
                      if (v == _current.text) {
                        return 'Choose a different password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('owner-confirm-password'),
                    controller: _confirm,
                    obscureText: !_passwordVisible,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                    validator: (v) => v != _new.text
                        ? 'Passwords do not match' : null,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _passwordVisible,
                    title: const Text('Show passwords'),
                    onChanged: (value) => setState(
                      () => _passwordVisible = value ?? false),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const Key('owner-change-password'),
                    onPressed: _saving ? null : _changePassword,
                    icon: const Icon(Icons.shield_outlined),
                    label: Text(_saving
                        ? 'Updating password...' : 'Change password'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(String name, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 100,
        child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      Expanded(child: Text(value)),
    ]),
  );
}
