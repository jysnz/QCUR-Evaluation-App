import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:qcur_evaluation/Pages/Auth/login_page.dart';
import 'package:qcur_evaluation/Pages/Dashboard/dashboard_page.dart';
import 'package:qcur_evaluation/Pages/Auth/register_page.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  await SentryFlutter.init(
    (options) {
      options.dsn = dotenv.env['SENTRY_DSN']!;
      options.tracesSampleRate = 1.0;
      options.environment = 'development';
    },
    appRunner: () => runApp(const MyApp()),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QCU Training Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kAccent,
          brightness: Brightness.dark,
          surface: kSurface,
        ),
        useMaterial3: true,
      ),
      home: const AuthRouter(),
    );
  }
}

class AuthRouter extends StatefulWidget {
  const AuthRouter({super.key});

  @override
  State<AuthRouter> createState() => _AuthRouterState();
}

class _AuthRouterState extends State<AuthRouter> {
  bool _checkingProfile = false;
  bool _hasProfile = false;
  Session? _session;

  @override
  void initState() {
    super.initState();
    _session = Supabase.instance.client.auth.currentSession;
    if (_session != null) {
      _checkProfile();
    }
    _setupAuthListener();
  }

  void _setupAuthListener() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        setState(() {
          _session = data.session;
        });
        if (_session != null) {
          _checkProfile();
        } else {
          Sentry.configureScope((scope) => scope.setUser(null));
          setState(() {
            _hasProfile = false;
            _checkingProfile = false;
          });
        }
      }
    });
  }

  Future<void> _checkProfile() async {
    if (_session == null) return;

    setState(() => _checkingProfile = true);
    try {
      final profile = await Supabase.instance.client
          .from('user_accounts')
          .select()
          .eq('id', _session!.user.id)
          .maybeSingle();

      final isComplete = profile != null && profile['profile_complete'] == true;
      if (mounted) {
        if (isComplete) {
          await Sentry.configureScope((scope) {
            scope.setUser(SentryUser(
              id: _session!.user.id,
              email: _session!.user.email,
              name: profile!['full_name']?.toString(),
            ));
          });
        }
        setState(() {
          _hasProfile = isComplete;
          _checkingProfile = false;
        });
      }
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _checkingProfile = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) {
      return LoginPage(onRegistrationSuccess: _checkProfile);
    }

    if (_checkingProfile) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: kAccent),
        ),
      );
    }

    if (!_hasProfile) {
      final user = _session!.user;
      return RegisterPage(
        isGoogleSignUp: true,
        initialEmail: user.email,
        initialName: user.userMetadata?['full_name'],
        initialImageUrl: user.userMetadata?['avatar_url'],
        onProfileComplete: () => _checkProfile(),
      );
    }

    return const DashboardPage();
  }
}
