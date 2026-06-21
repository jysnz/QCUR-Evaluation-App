import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:qcur_evaluation/Pages/Auth/auth_widgets.dart';

class RegisterPage extends StatefulWidget {
  final String? initialEmail;
  final String? initialName;
  final String? initialImageUrl;
  final bool isGoogleSignUp;
  final VoidCallback? onProfileComplete;
  final VoidCallback? onRegistrationSuccess;

  const RegisterPage({
    super.key,
    this.initialEmail,
    this.initialName,
    this.initialImageUrl,
    this.isGoogleSignUp = false,
    this.onProfileComplete,
    this.onRegistrationSuccess,
  });

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmPasswordController;
  late final TextEditingController _nameController;
  
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  bool _isRegistering = false;

  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasNumber = false;
  bool _hasSpecialChar = false;
  bool _passwordsMatch = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _nameController = TextEditingController(text: widget.initialName);
    
    _passwordController.addListener(_validatePassword);
    _confirmPasswordController.addListener(_validateConfirmPassword);
  }

  void _validatePassword() {
    final password = _passwordController.text;
    setState(() {
      _hasMinLength = password.length >= 8;
      _hasUppercase = password.contains(RegExp(r'[A-Z]'));
      _hasNumber = password.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    });
  }

  bool get _isPasswordValid =>
      _hasMinLength && _hasUppercase && _hasNumber && _hasSpecialChar;

  void _validateConfirmPassword() {
    setState(() {
      _passwordsMatch = _confirmPasswordController.text == _passwordController.text;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<void> _showSuccessDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: kSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: kAccent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, size: 48, color: Colors.white),
              ),
              const SizedBox(height: 24),
              const Text(
                'Registration Complete!',
                textAlign: TextAlign.center,
                style: AppTypography.h3,
              ),
              const SizedBox(height: 12),
              Text(
                'Welcome! Your profile has been created.',
                textAlign: TextAlign.center,
                style: AppTypography.caption,
              ),
              const SizedBox(height: 32),
              AppButton(
                label: 'Go to Dashboard',
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  if (widget.isGoogleSignUp) {
                    widget.onProfileComplete?.call();
                  } else {
                    widget.onRegistrationSuccess?.call();
                  }
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showErrorDialog(String message) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: kSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
          title: const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
              SizedBox(width: 10),
              Text('Error', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK', style: TextStyle(color: kAccent, fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showRateLimitDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // Illustration
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.mark_email_unread_rounded, size: 52, color: Color(0xFFE6A817)),
                  Positioned(
                    bottom: 12,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE6A817),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.hourglass_top_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Too Many Attempts',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'We\'ve sent too many emails in a short time. Please wait a few minutes before trying again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This is a temporary limit to protect against spam.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE6A817),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                  elevation: 0,
                ),
                child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _register() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty || _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields')));
      return;
    }

    if (!_isPasswordValid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please meet all password requirements')));
      return;
    }

    if (!_passwordsMatch) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }

    setState(() => _isRegistering = true);
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      
      String? avatarUrl = widget.initialImageUrl;

      // Handle image upload if selected
      if (_imageFile != null && user != null) {
        final fileExt = _imageFile!.path.split('.').last;
        final fileName = '${user.id}.$fileExt';
        final filePath = 'avatars/$fileName';
        
        await supabase.storage.from('user_assets').upload(
          filePath,
          _imageFile!,
          fileOptions: const FileOptions(upsert: true),
        );
        
        avatarUrl = supabase.storage.from('user_assets').getPublicUrl(filePath);
      }

      if (user != null || widget.isGoogleSignUp) {
        final targetUser = user ?? supabase.auth.currentUser;
        if (targetUser != null) {
          if (_passwordController.text.isNotEmpty) {
            await supabase.auth.updateUser(
              UserAttributes(password: _passwordController.text.trim()),
            );
          }
          await supabase.from('user_accounts').upsert({
            'id': targetUser.id,
            'email': _emailController.text.trim(),
            'full_name': _nameController.text.trim(),
            'avatar_url': avatarUrl,
            'profile_complete': true,
          });
        }
      } else {
        final response = await supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          data: {
            'full_name': _nameController.text.trim(),
          }
        );

        // If email confirmation is required there is no active session yet.
        // The DB trigger already created the user_accounts row — skip the upsert
        // here or it will fail RLS (auth.uid() is null without a session).
        if (response.session == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account created! Please confirm your email.')),
          );
          Navigator.of(context).pop();
          return;
        }

        // Session exists → user is authenticated; update their full profile.
        if (response.user != null) {
          await supabase.from('user_accounts').upsert({
            'id': response.user!.id,
            'email': _emailController.text.trim(),
            'full_name': _nameController.text.trim(),
            'avatar_url': avatarUrl,
            'profile_complete': true,
          });
        }
      }
      
      if (mounted) {
        setState(() => _isRegistering = false);
        await _showSuccessDialog();
      }
    } on AuthException catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isRegistering = false);
        final msg = e.message.toLowerCase();
        if (msg.contains('rate limit') || msg.contains('over_email_send_rate_limit') || msg.contains('email rate')) {
          _showRateLimitDialog();
        } else {
          _showErrorDialog(e.message);
        }
      }
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isRegistering = false);
        final msg = e.toString().toLowerCase();
        if (msg.contains('rate limit') || msg.contains('over_email_send_rate_limit') || msg.contains('email rate')) {
          _showRateLimitDialog();
        } else {
          _showErrorDialog(e.toString());
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: kBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 40,
          automaticallyImplyLeading: false,
          leading: widget.isGoogleSignUp
            ? IconButton(
                icon: const Icon(Icons.logout_rounded, color: Colors.white38, size: 20),
                onPressed: () async {
                  await GoogleSignIn().signOut();
                  await Supabase.instance.client.auth.signOut();
                },
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
        ),
        body: Stack(
          children: [
            const AuthBackground(),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: kPadding, vertical: 4.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.isGoogleSignUp ? 'Finish Profile' : 'Sign Up',
                        textAlign: TextAlign.center,
                        style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.isGoogleSignUp
                          ? 'Please add your info'
                          : 'Create a new account',
                        textAlign: TextAlign.center,
                        style: AppTypography.caption.copyWith(color: kForegroundMuted, fontSize: 10),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: kAccent.withValues(alpha: 0.3)),
                            ),
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 40,
                                  backgroundColor: kSurface,
                                  backgroundImage: _imageFile != null
                                      ? FileImage(_imageFile!)
                                      : (widget.initialImageUrl != null
                                          ? NetworkImage(widget.initialImageUrl!)
                                          : null),
                                  child: (_imageFile == null && widget.initialImageUrl == null)
                                      ? const Icon(Icons.person_outline, size: 36, color: Colors.white24)
                                      : null,
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: kAccent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.camera_alt_outlined, size: 9, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      AuthGlassCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AuthTextField(
                              controller: _emailController,
                              label: 'Email',
                              hint: 'Enter your email address',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              enabled: !widget.isGoogleSignUp,
                              dense: true,
                            ),
                            const SizedBox(height: 8),
                            AuthTextField(
                              controller: _nameController,
                              label: 'Full Name',
                              hint: 'Enter your full name',
                              icon: Icons.badge_outlined,
                              dense: true,
                            ),
                            const SizedBox(height: 8),
                            AuthTextField(
                              controller: _passwordController,
                              label: 'Password',
                              hint: 'Choose a strong password',
                              icon: Icons.lock_outline,
                              obscureText: true,
                              dense: true,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text('Password Rules',
                                  style: AppTypography.label.copyWith(color: kForegroundDisabled, fontSize: 9)),
                                const SizedBox(width: 6),
                                Expanded(child: Divider(color: kBorder.withValues(alpha: 0.3))),
                              ],
                            ),
                            const SizedBox(height: 4),
                            _PasswordRequirement(label: '8+ characters', isValid: _hasMinLength),
                            _PasswordRequirement(label: 'Uppercase (A-Z)', isValid: _hasUppercase),
                            _PasswordRequirement(label: 'Number (0-9)', isValid: _hasNumber),
                            _PasswordRequirement(label: 'Special character', isValid: _hasSpecialChar),
                            const SizedBox(height: 8),
                            AuthTextField(
                              controller: _confirmPasswordController,
                              label: 'Confirm Password',
                              hint: 'Repeat your password',
                              icon: Icons.lock_reset_rounded,
                              obscureText: true,
                              dense: true,
                            ),
                            const SizedBox(height: 4),
                            if (_confirmPasswordController.text.isNotEmpty)
                              _PasswordRequirement(label: 'Passwords Match', isValid: _passwordsMatch),
                            const SizedBox(height: 12),
                            AuthButton(
                              label: widget.isGoogleSignUp ? 'Save Profile' : 'Create Account',
                              onPressed: _register,
                              isLoading: _isRegistering,
                              dense: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!widget.isGoogleSignUp)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Already have an account?',
                              style: AppTypography.caption.copyWith(color: kForegroundMuted, fontSize: 10),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: TextButton.styleFrom(
                                foregroundColor: kAccent,
                                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                minimumSize: Size.zero,
                              ),
                              child: const Text('Log In'),
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
      ),
    );
  }
}

class _PasswordRequirement extends StatelessWidget {
  final String label;
  final bool isValid;

  const _PasswordRequirement({
    required this.label,
    required this.isValid,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 2),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
            size: 11,
            color: isValid ? kAccent : Colors.white12,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isValid ? Colors.white70 : Colors.white24,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
