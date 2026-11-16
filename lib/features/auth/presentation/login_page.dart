import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../ui/school_theme.dart';

/// The supplied desktop and Android background artwork is intentionally
/// flattened (logo, school scene, header/footer already appear in the image).
/// Only the interactive login card is drawn above it: no duplicate artwork.
/// The optional image fallback keeps the app bootable while assets are being
/// installed locally; it is NOT intended as the released visual design.
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
  static const _teal = Color(0xFF005F5B);
  static const _desktopBackground = 'assets/login/signin_desktop.jpg';
  static const _mobileBackground = 'assets/login/signin_mobile.jpg';

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _working = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submitSignIn() async {
    if (_working || !_formKey.currentState!.validate()) return;
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

  void _help() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Contact your school administrator for account support.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Keep the image stationary when the mobile keyboard appears; scroll
      // the form above the keyboard instead of squashing/cropping the art.
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, viewport) {
          final width = viewport.maxWidth;
          final height = viewport.maxHeight;
          final desktop = width >= 900 && width > height;

          return Stack(
            fit: StackFit.expand,
            children: [
              _background(desktop),
              if (Theme.of(context).brightness == Brightness.dark)
                const ColoredBox(color: Color(0x33001620)),
              Positioned(
                top: desktop ? 7 : MediaQuery.paddingOf(context).top + 4,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _themeButton(const Color(0xFF005F5B)),
                    if (kDebugMode)
                      IconButton(
                        key: const Key('open-demo-dashboard'),
                        tooltip: 'Preview Dashboard',
                        onPressed: widget.onOpenDemo,
                        icon: const Icon(
                          Icons.preview_outlined,
                          color: Color(0xFF005F5B), size: 19),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
              if (desktop)
                Positioned(
                  right: math.max(22, width * 0.021),
                  top: math.max(24, height * 0.044),
                  bottom: math.max(22, height * 0.073),
                  width: math.min(550, width * 0.365),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SingleChildScrollView(
                      key: const Key('login-desktop-layout'),
                      child: _loginCard(mobile: false),
                    ),
                  ),
                )
              else
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, inner) => SingleChildScrollView(
                      key: const Key('login-mobile-layout'),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        18,
                        inner.maxHeight * 0.205,
                        18,
                        MediaQuery.viewInsetsOf(context).bottom + 26,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 470),
                          child: _loginCard(mobile: true),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _background(bool desktop) {
    return Image.asset(
      desktop ? _desktopBackground : _mobileBackground,
      key: Key(desktop ? 'login-desktop-background' : 'login-mobile-background'),
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEDF7FC), Color(0xFFD9E9F9)],
          ),
        ),
      ),
    );
  }

  Widget _loginCard({required bool mobile}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onCard = dark ? Colors.white : const Color(0xFF12191D);
    final muted = dark ? const Color(0xFFC8D8DB) : const Color(0xFF586873);
    final cardColor = dark
        ? const Color(0xFF162B30).withValues(alpha: 0.97)
        : Colors.white.withValues(alpha: 0.97);
    final space = mobile ? 11.0 : 16.0;

    return Material(
      key: const Key('login-form-card'),
      color: cardColor,
      elevation: 12,
      shadowColor: const Color(0x440A3540),
      borderRadius: BorderRadius.circular(mobile ? 26 : 24),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          mobile ? 20 : 40, mobile ? 19 : 32,
          mobile ? 20 : 40, mobile ? 16 : 28,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                mobile ? 'Welcome back' : 'Sign In to Supa Model School',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: mobile ? 27 : 27,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: dark ? const Color(0xFF6ED5C9) : _teal,
                ),
              ),
              SizedBox(height: mobile ? 2 : 5),
              Text(
                mobile
                    ? 'Sign in to continue to Supa Model School'
                    : 'Access your school management system',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: mobile ? 14 : 15),
              ),
              SizedBox(height: mobile ? 18 : 24),
              _fieldLabel('School / Campus', Icons.account_balance_outlined,
                  onCard, mobile),
              const SizedBox(height: 5),
              DropdownButtonFormField<String>(
                key: const Key('login-campus'),
                isExpanded: true,
                initialValue: null,
                hint: const Text('Select School / Campus'),
                disabledHint: const Text('Select School / Campus'),
                items: const [],
                onChanged: null,
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: muted),
                decoration: _inputDecoration(dark),
              ),
              SizedBox(height: space),
              _fieldLabel('Email or Username', Icons.person_rounded,
                  onCard, mobile),
              const SizedBox(height: 5),
              TextFormField(
                key: const Key('login-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                style: TextStyle(color: onCard, fontSize: 15),
                decoration: _inputDecoration(dark).copyWith(
                  hintText: 'Enter your email or username',
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? 'Enter your email or username'
                        : null,
              ),
              SizedBox(height: space),
              _fieldLabel('Password', Icons.lock_rounded, onCard, mobile),
              const SizedBox(height: 5),
              TextFormField(
                key: const Key('login-password'),
                controller: _password,
                obscureText: !_showPassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submitSignIn(),
                autofillHints: const [AutofillHints.password],
                style: TextStyle(color: onCard, fontSize: 15),
                decoration: _inputDecoration(dark).copyWith(
                  hintText: 'Enter your password',
                  suffixIcon: IconButton(
                    key: const Key('toggle-password'),
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: muted,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: (value) =>
                    value == null || value.isEmpty
                        ? 'Enter your password'
                        : null,
              ),
              SizedBox(height: mobile ? 6 : 10),
              Row(
                children: [
                  SizedBox(
                    width: 30,
                    height: 40,
                    child: Tooltip(
                      message: 'Remember me is disabled until encrypted '
                          'session storage is implemented.',
                      child: Checkbox(
                        value: false,
                        onChanged: null,
                        side: BorderSide(color: muted),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text('Remember me',
                        style: TextStyle(color: onCard, fontSize: 13)),
                  ),
                  TextButton(
                    onPressed: _resetPassword,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      foregroundColor: dark
                          ? const Color(0xFF77E1D4)
                          : _teal,
                    ),
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: mobile ? 9 : 17),
              SizedBox(
                height: mobile ? 49 : 57,
                child: FilledButton.icon(
                  key: const Key('login-sign-in'),
                  onPressed: _working ? null : _submitSignIn,
                  style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: _working
                      ? const SizedBox(
                          width: 17, height: 17,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.login_rounded, size: 25),
                  label: Text(
                    _working ? 'Signing In...' : 'Sign In',
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              SizedBox(height: mobile ? 7 : 14),
              Text(
                'English first • Windows & Android',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 12),
              ),
              Divider(height: mobile ? 17 : 25, color: muted.withValues(alpha: 0.17)),
              Center(
                child: TextButton.icon(
                  onPressed: _help,
                  style: TextButton.styleFrom(
                    foregroundColor:
                        dark ? const Color(0xFF77E1D4) : _teal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 0),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.headset_mic_outlined, size: 20),
                  label: const Text(
                    'Need help? Contact administrator',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline),
                  ),
                ),
              ),
              if (mobile)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.verified_user_outlined,
                          color: SchoolPalette.teal, size: 17),
                      const SizedBox(width: 6),
                      Text('Secure access for authorized staff only',
                          style: TextStyle(color: muted, fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(
      String text, IconData icon, Color color, bool mobile) {
    return Row(children: [
      Icon(icon, color: const Color(0xFF60737A), size: mobile ? 19 : 20),
      const SizedBox(width: 10),
      Text(text, style: TextStyle(
        color: color, fontSize: mobile ? 14 : 14,
        fontWeight: FontWeight.w700,
      )),
    ]);
  }

  InputDecoration _inputDecoration(bool dark) {
    final border = OutlineInputBorder(
      borderSide: BorderSide(
        color: dark ? const Color(0xFF56777C) : const Color(0xFFCBD3D9)),
      borderRadius: BorderRadius.circular(10),
    );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: dark ? const Color(0xFF1C363B) : const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: _teal, width: 2),
      ),
    );
  }

  Widget _themeButton(Color color) => PopupMenuButton<ThemeMode>(
        tooltip: 'Change appearance',
        icon: Icon(
          widget.themeMode == ThemeMode.dark
              ? Icons.dark_mode_outlined
              : Icons.light_mode_outlined,
          color: color, size: 19,
        ),
        onSelected: widget.onThemeChanged,
        itemBuilder: (context) => const [
          PopupMenuItem(value: ThemeMode.system, child: Text('System theme')),
          PopupMenuItem(value: ThemeMode.light, child: Text('Light theme')),
          PopupMenuItem(value: ThemeMode.dark, child: Text('Dark theme')),
        ],
      );
}
