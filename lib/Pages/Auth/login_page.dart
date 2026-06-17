import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Pages/Auth/auth_widgets.dart';
import 'package:qcur_evaluation/Pages/Auth/register_page.dart';
import 'package:qcur_evaluation/Pages/Auth/forgot_password_page.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback? onRegister;

  const LoginPage({super.key, this.onRegister});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _signIn() async {
    if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password')),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unexpected error occurred')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];

      if (webClientId == null) {
        throw 'GOOGLE_WEB_CLIENT_ID not found in .env';
      }

      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: webClientId,
      );

      // Force account selection by signing out first
      await googleSignIn.signOut();

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }
      
      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null) throw 'No Access Token found.';
      if (idToken == null) throw 'No ID Token found.';

      final res = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      // Check if user has a profile
      if (res.user != null) {
        final profile = await Supabase.instance.client
            .from('user_accounts')
            .select()
            .eq('id', res.user!.id)
            .maybeSingle();
            
        if (profile == null && mounted) {
          // If no profile, navigate to RegisterPage to complete profile
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => RegisterPage(
                isGoogleSignUp: true,
                initialEmail: res.user!.email,
                initialName: res.user!.userMetadata?['full_name'],
                initialImageUrl: res.user!.userMetadata?['avatar_url'],
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Google Sign-in failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToRegister() {
    if (widget.onRegister != null) {
      widget.onRegister!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const RegisterPage()),
      );
    }
  }

  void _navigateToForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ForgotPasswordPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: Stack(
        children: [
          const AuthBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: kAccent.withValues(alpha: 0.2)),
                      ),
                      child: const Icon(Icons.hub_outlined, size: 48, color: kAccent),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'LOGIN',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: kForeground,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'AUTHENTICATE TO ACCESS THE ARENA',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: kForegroundMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 48),
                    AuthGlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AuthTextField(
                            controller: _emailController,
                            label: 'Access Email',
                            icon: Icons.alternate_email_rounded,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 20),
                          AuthTextField(
                            controller: _passwordController,
                            label: 'Security Key',
                            icon: Icons.key_rounded,
                            obscureText: true,
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _navigateToForgotPassword,
                              style: TextButton.styleFrom(
                                foregroundColor: kAccent.withValues(alpha: 0.6),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text('FORGOT CREDENTIALS?', 
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: kAccent,
                                  fontWeight: FontWeight.w900,
                                )),
                            ),
                          ),
                          const SizedBox(height: 32),
                          AuthButton(
                            label: 'Establish Session',
                            onPressed: _signIn,
                            isLoading: _isLoading,
                          ),
                          const SizedBox(height: 32),
                          Row(
                            children: [
                              Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.05))),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  'EXTERNAL AUTH',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: kForeground.withValues(alpha: 0.2),
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                              Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.05))),
                            ],
                          ),
                          const SizedBox(height: 32),
                          TechnicalButton(
                            label: 'Sign in with Google',
                            color: Colors.white,
                            onTap: _isLoading ? () {} : _signInWithGoogle,
                            icon: Icons.g_mobiledata_rounded,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "New to the platform?",
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: kForegroundMuted,
                          ),
                        ),
                        TextButton(
                          onPressed: _navigateToRegister,
                          style: TextButton.styleFrom(
                            foregroundColor: kAccent,
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                          ),
                          child: const Text('CREATE ACCOUNT'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
