import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/profile.dart';
import 'providers/language_provider.dart';
import 'providers/theme_provider.dart';
import 'services/notification_service.dart';
import 'services/supabase_service.dart';
import 'views/auth/auth_screen.dart';
import 'views/client/client_shell.dart';
import 'views/provider/provider_shell.dart';

/// StyleLink project credentials. The anon key doubles as the publishable
/// key in the current Supabase API — safe for client builds because
/// row-level security in the database guards all data access.
const String supabaseUrl = 'https://mzmumrggvwzwrootgcie.supabase.co';
const String supabasePublishableKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im16bXVtcmdndnd6d3Jvb3RnY2llIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY4NzEwMDAsImV4cCI6MjEwMjQ0NzAwMH0.b73QSTnUALpw6Ffa-o-B86kSGcM2D5hWX2GCV6izJog';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (required for FCM).
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase config may be missing on web — app still works without FCM.
    debugPrint('Firebase init skipped: $e');
  }

  // Single point of initialization — required before any Supabase call.
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );

  // Initialize local push notifications.
  await NotificationService.instance.init();

  runApp(const StyleLinkApp());
}

/// StyleLink visual identity: soft off-white surfaces, coral seed color,
/// lavender accents (mirrors the mobile design language).
class StyleLinkApp extends StatefulWidget {
  const StyleLinkApp({super.key});

  @override
  State<StyleLinkApp> createState() => _StyleLinkAppState();
}

class _StyleLinkAppState extends State<StyleLinkApp> {
  final _themeProvider = ThemeProvider();
  final _languageProvider = LanguageProvider();

  @override
  void initState() {
    super.initState();
    _themeProvider.load();
    _languageProvider.load();
  }

  @override
  void dispose() {
    _themeProvider.dispose();
    _languageProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const coral = Color(0xFFF4665C);
    const lavender = Color(0xFF9E86E6);
    return LanguageScope(
      provider: _languageProvider,
      child: ThemeScope(
        provider: _themeProvider,
        child: ListenableBuilder(
          listenable: Listenable.merge([_themeProvider, _languageProvider]),
          builder: (context, _) {
            return MaterialApp(
              title: 'StyleLink',
              debugShowCheckedModeBanner: false,
              locale: _languageProvider.locale,
              supportedLocales: const [Locale('en'), Locale('fr')],
              localeResolutionCallback: (locale, supported) {
                return _languageProvider.locale;
              },
              themeMode: _themeProvider.mode,
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.light,
              colorScheme: ColorScheme.fromSeed(
                seedColor: coral,
                secondary: lavender,
                surface: const Color(0xFFFAF7F3),
              ),
              scaffoldBackgroundColor: const Color(0xFFFAF7F3),
              fontFamilyFallback: const ['sans-serif'],
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              colorScheme: ColorScheme.fromSeed(
                seedColor: coral,
                secondary: lavender,
                brightness: Brightness.dark,
                surface: const Color(0xFF1A1720),
              ),
              scaffoldBackgroundColor: const Color(0xFF1A1720),
              fontFamilyFallback: const ['sans-serif'],
            ),
              home: const AuthGate(),
            );
          },
        ),
      ),
    );
  }
}

/// Single entry point for the authenticated app.
///
/// All users (client and provider) land here after sign-in. The gate resolves
/// the profile role and mounts the appropriate shell. Role selection has been
/// removed — every new user defaults to 'client'. Providers can be created
/// later via the in-app "Become a Provider" flow.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _authSub;

  /// When true, the provider-mode shell is shown instead of the client shell.
  bool _showProviderMode = false;

  /// Monotonically increasing key that forces the FutureBuilder to re-resolve
  /// the role after a provider upgrade.  Incremented by ClientShell's
  /// upgrade callback.
  int _roleKey = 0;

  @override
  void initState() {
    super.initState();
    _authSub = SupabaseService.instance.onAuthStateChange.listen((authState) {
      if (mounted) setState(() {});
      // Start or stop notification listeners based on auth state.
      final session = authState.session;
      if (session != null) {
        // Safety net: ensure a profile row exists.  The DB trigger
        // handle_new_user() normally creates it, but when it fails
        // (RLS, race conditions, OAuth quirks) this fills the gap.
        SupabaseService.instance.ensureProfileExists();
        NotificationService.instance.startListening();
        NotificationService.instance.requestPermission();
      } else {
        NotificationService.instance.stopListening();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    NotificationService.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: SupabaseService.instance.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;
        if (session == null) {
          _showProviderMode = false;
          return const AuthScreen();
        }
        return FutureBuilder<UserRole?>(
          // Changing [future] forces the FutureBuilder to re-evaluate.
          key: ValueKey('role-$_roleKey-${session.user.id}'),
          future: SupabaseService.instance.currentRole(),
          builder: (context, roleSnapshot) {
            if (roleSnapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final error = roleSnapshot.error;
            if (error != null) {
              return _ErrorScreen(error: error);
            }
            final role = roleSnapshot.data;
            final isProvider = role == UserRole.provider;

            // Workspace toggle: providers can switch between client and
            // provider mode; clients always see ClientShell.
            if (isProvider && _showProviderMode) {
              return ProviderShell(
                onSwitchToClient: () =>
                    setState(() => _showProviderMode = false),
              );
            }
            final cb = isProvider
                ? () => setState(() => _showProviderMode = true)
                : null;
            return ClientShell(
              onSwitchToProvider: cb,
              onRoleChanged: () {
                // Force the FutureBuilder to re-resolve the role.
                setState(() => _roleKey++);
              },
            );
          },
        );
      },
    );
  }
}

/// Shown when the profile query fails (e.g. schema not deployed).
class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    color: Color(0xFFF4665C), size: 44),
                const SizedBox(height: 16),
                const Text(
                  'No profile found',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'We could not read your profile.\n'
                  'Run supabase/schema.sql in the Supabase SQL editor, then '
                  'sign out and back in.\n'
                  'Votre profil est introuvable.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6E6A76),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFFB3261E)),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => SupabaseService.instance.signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ThemeScope — lightweight InheritedWidget for theme access
// =============================================================================

/// Provides [ThemeProvider] to the entire widget tree without the `provider`
/// package. Access via `ThemeScope.of(context)` or the extension below.
class ThemeScope extends InheritedWidget {
  const ThemeScope({
    super.key,
    required this.provider,
    required super.child,
  });

  final ThemeProvider provider;

  static ThemeProvider of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'No ThemeScope found in context');
    return scope!.provider;
  }

  @override
  bool updateShouldNotify(ThemeScope oldWidget) =>
      provider != oldWidget.provider;
}

/// Convenience extension on BuildContext.
extension ThemeScopeExtension on BuildContext {
  ThemeProvider get theme => ThemeScope.of(this);
}
