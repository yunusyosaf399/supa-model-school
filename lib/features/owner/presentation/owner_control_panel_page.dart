import 'package:flutter/material.dart';

import '../../auth/data/owner_auth_gateway.dart';

/// Authorized Owner settings. The database is read-only until audited settings
/// mutations are deployed; only password changes use the Supabase Auth API.
class OwnerControlPanelPage extends StatefulWidget {
  const OwnerControlPanelPage({
    super.key,
    required this.owner,
    required this.onChangePassword,
    required this.onPasswordChanged,
  });

  final OwnerAccess owner;
  final Future<void> Function(String currentPassword, String newPassword)
      onChangePassword;
  final VoidCallback onPasswordChanged;

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
    final owner = widget.owner;
    final pendingCurrency = owner.currencyCode == 'XXX';
    final pendingTimezone = owner.timezoneName == 'Etc/UTC';
    final pendingCampus = owner.campuses.any(
      (c) => c.name.contains('Setup Pending'),
    );

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
                Text('Setup status: ${pendingCurrency || pendingTimezone || pendingCampus ? 'Pending' : 'Review required'}'),
                const SizedBox(height: 12),
                _field('School', owner.schoolName),
                _field('Currency', pendingCurrency
                    ? 'Not configured (XXX)' : owner.currencyCode),
                _field('Timezone', pendingTimezone
                    ? 'Not configured (Etc/UTC)' : owner.timezoneName),
                _field('Campus', owner.campuses.map((c) => c.name).join(', ')),
                const SizedBox(height: 8),
                const Text('School and campus changes are read-only for now. '
                    'Owner-only updates, auditing and validations will be '
                    'enabled after the Settings service passes security tests.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
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
