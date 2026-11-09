import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/profile.dart';
import '../../services/analytics_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/validators.dart';
import '../widgets/logo_lockup.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();

  bool _isSignUp = false;
  bool _googleBusy = false;
  bool _emailBusy = false;
  String? _notice;
  bool _handledSession = false;
  StreamSubscription<AuthState>? _authSub;

  /// Role chosen on sign-up: Client (book appointments) or Service Provider
  /// (run a shop). Providers are routed into the guided setup wizard right
  /// after their account is created — see AuthGate in main.dart.
  UserRole _selectedRole = UserRole.client;

  @override
  void initState() {
    super.initState();
    _authSub = SupabaseService.instance.onAuthStateChange.listen((state) {
      if (state.session != null) _handleSession();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _handleSession() async {
    if (_handledSession) return;
    _handledSession = true;
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _googleBusy = true);
    try {
      final launched =
          await SupabaseService.instance.signInWithGoogle(role: _selectedRole);
      AnalyticsService.instance.logLogin(method: 'google');
      if (!launched && mounted) {
        _showError('Could not open Google sign-in. Please try again.');
      }
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _submitEmail() async {
    FocusScope.of(context).unfocus();
    final service = SupabaseService.instance;
    final email = _email.text.trim();
    final password = _password.text;

    final validationError = _isSignUp
        ? Validators.required(_fullName.text,
                message: 'Please enter your full name.') ??
            Validators.email(email) ??
            Validators.password(password)
        : Validators.email(email) ?? Validators.password(password);
    if (validationError != null) {
      _showError(validationError);
      return;
    }

    setState(() {
      _emailBusy = true;
      _notice = null;
    });
    try {
      if (_isSignUp) {
        final response = await service.signUpWithEmail(
          email: email,
          password: password,
          fullName: _fullName.text.trim(),
          phoneNumber: _phone.text.trim().isEmpty
              ? null
              : Validators.normalizeCameroonPhone(_phone.text),
          role: _selectedRole,
        );
        AnalyticsService.instance.logSignUp(method: 'email');
        AnalyticsService.instance.setUserRole(_selectedRole.name);
        if (response.session == null && mounted) {
          setState(() {
            _notice =
                'Account created - check your email to confirm, then sign in.';
          });
        }
      } else {
        await service.signInWithEmail(email: email, password: password);
        AnalyticsService.instance.logLogin(method: 'email');
      }
      if (service.currentSession != null) await _handleSession();
    } on AuthException catch (e) {
      _showError(e.message);
    } on PostgrestException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _emailBusy = false);
    }
  }

  Future<void> _showForgotPassword() async {
    final controller = TextEditingController(text: _email.text.trim());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your email to receive a password reset link.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.mail_outline, size: 20),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0x14000000)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFA5252),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send Reset Link'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final email = controller.text.trim();
    final emailError = Validators.email(email);
    if (emailError != null) {
      _showError(emailError);
      return;
    }
    try {
      await SupabaseService.instance.resetPasswordForEmail(email);
      if (!mounted) return;
      setState(() {
        _notice = 'Password reset email sent - check your inbox.';
      });
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFFDFBF7),
                gradient: RadialGradient(
                  center: Alignment(-0.8, -1.05),
                  radius: 1.35,
                  colors: [
                    Color(0x4DFA5252),
                    Color(0x339333EA),
                    Color(0x00FDFBF7),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 18),
                const Center(child: LogoLockup(compact: true)),
                const SizedBox(height: 6),
                const Text(
                  'Discover and Book Stylists Near You.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF6E6A76)),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_notice != null) ...[
                          _noticeBox(_notice!),
                          const SizedBox(height: 16),
                        ],
                        if (_isSignUp) ...[
                          _roleSelector(),
                          const SizedBox(height: 18),
                        ],
                        _googleButton(busy: _googleBusy),
                        const SizedBox(height: 18),
                        const _OrDivider(
                          label:
                              'or continue with email / ou avec votre e-mail',
                        ),
                        const SizedBox(height: 18),
                        _emailView(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle? _segmentedStyle() => SegmentedButton.styleFrom(
        backgroundColor: const Color(0x14000000),
        selectedBackgroundColor: const Color(0xFFFA5252),
        selectedForegroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F2937),
        side: BorderSide.none,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        visualDensity: VisualDensity.compact,
      );
  Widget _googleButton({required bool busy}) {
    return FilledButton(
      onPressed: busy ? null : _signInWithGoogle,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        backgroundColor: const Color(0xFFFA5252),
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0x55FA5252),
        elevation: 2,
        shadowColor: const Color(0x33FA5252),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: Colors.white),
            )
          : const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _GoogleMark(),
                SizedBox(width: 12),
                Text(
                  'Continue with Google',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
    );
  }

  /// "I am a…" role gate: Client books appointments, Service Provider runs
  /// a shop. Providers land in the guided setup wizard after sign-up.
  Widget _roleSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'I am a… / Je suis…',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6E6A76),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _roleCard(
                icon: Icons.person_outline_rounded,
                title: 'Client',
                subtitle: 'Book appointments',
                subtitleFr: 'Réserver',
                selected: _selectedRole == UserRole.client,
                onTap: () => setState(() => _selectedRole = UserRole.client),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _roleCard(
                icon: Icons.storefront_rounded,
                title: 'Service Provider',
                subtitle: 'Run my shop',
                subtitleFr: 'Gérer mon salon',
                selected: _selectedRole == UserRole.provider,
                onTap: () => setState(() => _selectedRole = UserRole.provider),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _roleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String subtitleFr,
    required bool selected,
    required VoidCallback onTap,
  }) {
    // The auth screen paints a fixed light background, so the cards stay
    // light-themed regardless of app dark mode.
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFFFA5252) : const Color(0x14000000),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFFFA5252).withValues(alpha: .18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0x14FA5252)
                        : const Color(0x0F000000),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 19,
                    color: selected
                        ? const Color(0xFFFA5252)
                        : const Color(0xFF6E6A76),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        selected ? const Color(0xFFFA5252) : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? const Color(0xFFFA5252)
                          : const Color(0x33000000),
                      width: 1.6,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 13, color: Colors.white)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$subtitle / $subtitleFr',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9A95A3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emailView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Sign In')),
            ButtonSegment(value: true, label: Text('Sign Up')),
          ],
          selected: {_isSignUp},
          onSelectionChanged: (s) => setState(() => _isSignUp = s.first),
          showSelectedIcon: false,
          style: _segmentedStyle(),
        ),
        const SizedBox(height: 16),
        if (_isSignUp) ...[
          _field(_fullName, 'Full name / Nom complet', Icons.person_outline,
              textCapitalization: TextCapitalization.words),
          const SizedBox(height: 12),
          _field(_phone, 'Phone (e.g. 6XX XX XX XX)', Icons.phone_outlined,
              keyboardType: TextInputType.phone),
          const SizedBox(height: 12),
        ],
        _field(_email, 'Email', Icons.mail_outline,
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 12),
        _field(_password, 'Password (min. 6 characters)', Icons.lock_outline,
            obscure: true),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _showForgotPassword,
            child: const Text(
              'Forgot Password? / Mot de passe oublie ?',
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFFFA5252),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _emailBusy ? null : _submitEmail,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: const Color(0xFFFA5252),
            disabledBackgroundColor: const Color(0x22FA5252),
          ),
          child: _emailBusy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Colors.white),
                )
              : Text(
                  _isSignUp ? 'Create Account' : 'Sign In',
                  style: const TextStyle(fontSize: 15),
                ),
        ),
      ],
    );
  }

  Widget _noticeBox(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDEDED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33FA5252)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFFB3261E),
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      textInputAction: obscure ? TextInputAction.done : TextInputAction.next,
      onSubmitted: obscure ? (_) => _submitEmail() : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x14000000)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x14000000)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFA5252), width: 1.6),
        ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'G',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          foreground: Paint()
            ..shader = const LinearGradient(
              colors: [
                Color(0xFF4285F4),
                Color(0xFF34A853),
                Color(0xFFFBBC05),
                Color(0xFFEA4335),
              ],
            ).createShader(const Rect.fromLTWH(0, 0, 22, 22)),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0x1A000000))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF9A95A3)),
          ),
        ),
        const Expanded(child: Divider(color: Color(0x1A000000))),
      ],
    );
  }
}
