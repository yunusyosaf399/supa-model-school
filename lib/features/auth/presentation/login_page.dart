import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../ui/school_brand.dart';
import '../../../ui/school_theme.dart';

/// Auth UI preview. No password is persisted, and no local demo flow creates
/// an authenticated session. Real sign-in must be wired after DB01 RLS tests.
class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required this.onOpenDemo,
    required this.onSignIn,
    required this.onRecoverPassword,
    required this.authConfigured,
  });

  final Future<void> Function(String email, String password) onSignIn;
  final Future<void> Function(String email) onRecoverPassword;
  final bool authConfigured;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final VoidCallback onOpenDemo;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _remember = false;
  bool _showPassword = false;
  bool _working = false;
  String _campus = 'campus-a';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submitSignIn() async {
    if (!_formKey.currentState!.validate() || _working) return;
    setState(() => _working = true);
    try {
      await widget.onSignIn(_email.text.trim(), _password.text);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.authConfigured
            ? 'Sign-in failed, or this account lacks active Owner access.'
            : 'Supabase Auth is not configured in this build.'),
      ));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter your email address first.'),
      ));
      return;
    }
    try {
      await widget.onRecoverPassword(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('If an account exists, follow the recovery instructions.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Password recovery is not yet configured. '
            'Contact your administrator for secure assistance.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, limits) {
          final wide = limits.maxWidth >= 900 && limits.maxHeight >= 720;
          if (wide) {
            return Row(children: [
              Expanded(
                flex: 6,
                child: _desktopBrand(),
              ),
              Expanded(
                flex: 5,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(30),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 490),
                      child: _loginCard(false),
                    ),
                  ),
                ),
              ),
            ]);
          }
          return ListView(
            key: const Key('login-mobile-layout'),
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: _themeButton(),
              ),
              const Center(child: SchoolMark(size: 88)),
              const SizedBox(height: 8),
              Text('Supa Model School',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary,
                  )),
              const SizedBox(height: 4),
              const Text('School Management System',
                  textAlign: TextAlign.center),
              const SizedBox(height: 26),
              _loginCard(true),
              const SizedBox(height: 16),
              const SchoolScene(height: 185),
            ],
          );
        }),
      ),
    );
  }

  Widget _themeButton() => PopupMenuButton<ThemeMode>(
        tooltip: 'Change appearance',
        icon: Icon(widget.themeMode == ThemeMode.dark
            ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
        onSelected: widget.onThemeChanged,
        itemBuilder: (context) => const [
          PopupMenuItem(value: ThemeMode.system, child: Text('System theme')),
          PopupMenuItem(value: ThemeMode.light, child: Text('Light theme')),
          PopupMenuItem(value: ThemeMode.dark, child: Text('Dark theme')),
        ],
      );

  Widget _desktopBrand() {
    return Container(
      padding: const EdgeInsets.fromLTRB(38, 26, 38, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: Theme.of(context).brightness == Brightness.dark
              ? [const Color(0xFF0A282B), const Color(0xFF153541)]
              : [const Color(0xFFEDF8FB), const Color(0xFFDCECF8)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const SchoolMark(size: 96),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Supa Model School',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.primary,
                    )),
                Text('School Management System',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            )),
            _themeButton(),
          ]),
          const SizedBox(height: 34),
          Container(width: 82, height: 4, color: SchoolPalette.teal),
          const SizedBox(height: 16),
          Text('A modern, easy-to-use platform\nto manage your school smarter.',
              style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          const SchoolScene(height: 360),
          const SizedBox(height: 18),
          const Row(children: [
            Icon(Icons.verified_user_outlined, size: 20),
            SizedBox(width: 8),
            Flexible(child: Text('Secure access for authorized staff only')),
          ]),
        ],
      ),
    );
  }

  Widget _loginCard(bool mobile) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(mobile ? 22 : 30),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(mobile ? 'Welcome back' : 'Sign In to Supa Model School',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.primary)),
              const SizedBox(height: 7),
              const Text('Access your school management system',
                  textAlign: TextAlign.center),
              const SizedBox(height: 27),
              const Text('School / Campus'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                key: const Key('login-campus'),
                initialValue: widget.authConfigured ? 'after-auth' : _campus,
                isExpanded: true,
                items: widget.authConfigured
                    ? const [
                        DropdownMenuItem(
                          value: 'after-auth',
                          child: Text('Campus chosen after secure sign-in'),
                        ),
                      ]
                    : const [
                        DropdownMenuItem(
                          value: 'campus-a',
                          child: Text('Sample Campus A (demo)'),
                        ),
                        DropdownMenuItem(
                          value: 'campus-b',
                          child: Text('Sample Campus B (demo)'),
                        ),
                      ],
                onChanged: widget.authConfigured ? null : (value) {
                  if (value != null) setState(() => _campus = value);
                },
              ),
              const SizedBox(height: 17),
              Text(widget.authConfigured ? 'Email address' : 'Email or Username'),
              const SizedBox(height: 6),
              TextFormField(
                key: const Key('login-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  hintText: 'Enter your email address',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (s) => (s == null || s.trim().isEmpty)
                    ? 'Enter your email or username' : null,
              ),
              const SizedBox(height: 17),
              const Text('Password'),
              const SizedBox(height: 6),
              TextFormField(
                key: const Key('login-password'),
                controller: _password,
                obscureText: !_showPassword,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  hintText: 'Enter your password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    key: const Key('toggle-password'),
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    icon: Icon(_showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () => setState(
                        () => _showPassword = !_showPassword),
                  ),
                ),
                validator: (s) => (s == null || s.isEmpty)
                    ? 'Enter your password' : null,
              ),
              const SizedBox(height: 13),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Checkbox(
                      value: widget.authConfigured ? false : _remember,
                      onChanged: widget.authConfigured
                          ? null
                          : (v) => setState(() => _remember = v ?? false),
                    ),
                    Text(widget.authConfigured
                        ? 'Remember me (disabled for security)' : 'Remember me'),
                  ]),
                  TextButton(
                    onPressed: _resetPassword,
                    child: const Text('Forgot Password?'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('login-sign-in'),
                onPressed: _working ? null : _submitSignIn,
                icon: const Icon(Icons.login),
                label: Text(_working ? 'Signing In...' : 'Sign In'),
              ),
              const SizedBox(height: 13),
              if (kDebugMode) OutlinedButton.icon(
                key: const Key('open-demo-dashboard'),
                onPressed: widget.onOpenDemo,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Preview Dashboard'),
              ),
              const SizedBox(height: 12),
              Text(widget.authConfigured
                  ? 'OWNER SIGN-IN • verified school role required'
                  : 'DESIGN PREVIEW — no authenticated access',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall),
              const Divider(height: 32),
              const Center(child: Text('Need help? Contact administrator')),
              const SizedBox(height: 12),
              const Center(child: Text('English first • Windows & Android')),
            ],
          ),
        ),
      ),
    );
  }
}
