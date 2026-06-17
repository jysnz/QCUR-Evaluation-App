import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Pages/Dashboard/dashboard_page.dart';
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
  
  String _selectedPosition = 'Media';
  final List<String> _positions = ['Media', 'Member', 'Team Player'];
  
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
                'You are registered!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Welcome! Your profile is ready.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),
              TechnicalButton(
                label: 'Go to Dashboard',
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const DashboardPage()),
                    (route) => false,
                  );
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
            'position': _selectedPosition,
            'avatar_url': avatarUrl,
          });
        }
      } else {
        final response = await supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          data: {
            'full_name': _nameController.text.trim(),
            'position': _selectedPosition,
          }
        );

        if (response.user != null) {
          await supabase.from('user_accounts').upsert({
            'id': response.user!.id,
            'email': _emailController.text.trim(),
            'full_name': _nameController.text.trim(),
            'position': _selectedPosition,
            'avatar_url': avatarUrl,
          });
        }

        if (response.session == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account created! Please confirm your email.')),
          );
          Navigator.of(context).pop();
          return;
        }
      }
      
      if (mounted) {
        setState(() => _isRegistering = false);
        await _showSuccessDialog();
        if (!mounted) return;
        if (widget.isGoogleSignUp) {
          widget.onProfileComplete?.call();
        } else {
          widget.onRegistrationSuccess?.call();
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _isRegistering = false);
        _showErrorDialog(e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRegistering = false);
        _showErrorDialog(e.toString());
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
          automaticallyImplyLeading: false,
          leading: widget.isGoogleSignUp 
            ? IconButton(
                icon: const Icon(Icons.logout_rounded, color: Colors.white38),
                onPressed: () async {
                  await GoogleSignIn().signOut();
                  await Supabase.instance.client.auth.signOut();
                },
              )
            : null,
        ),
        body: Stack(
          children: [
            const AuthBackground(),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.isGoogleSignUp ? 'Finish Profile' : 'Sign Up',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.isGoogleSignUp 
                          ? 'Please add your info' 
                          : 'Create a new account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.3),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 32),
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
                                  radius: 44,
                                  backgroundColor: kSurface,
                                  backgroundImage: _imageFile != null
                                      ? FileImage(_imageFile!)
                                      : (widget.initialImageUrl != null
                                          ? NetworkImage(widget.initialImageUrl!)
                                          : null),
                                  child: (_imageFile == null && widget.initialImageUrl == null)
                                      ? const Icon(Icons.person_outline, size: 40, color: Colors.white24)
                                      : null,
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: kAccent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.camera_alt_outlined, size: 14, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      AuthGlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AuthTextField(
                              controller: _emailController,
                              label: 'Access Email',
                              hint: 'Enter your email address',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              enabled: !widget.isGoogleSignUp,
                            ),
                            const SizedBox(height: 16),
                            AuthTextField(
                              controller: _nameController,
                              label: 'Full Name',
                              hint: 'Enter your full name',
                              icon: Icons.badge_outlined,
                            ),
                            const SizedBox(height: 16),
                            AuthTextField(
                              controller: _passwordController,
                              label: 'Your Password',
                              hint: 'Choose a strong password',
                              icon: Icons.lock_outline,
                              obscureText: true,
                            ),
                            const SizedBox(height: 16),
                            
                            Row(
                              children: [
                                Text('PASSWORD RULES', 
                                  style: AppTypography.overline.copyWith(color: kForegroundDisabled)),
                                const SizedBox(width: 8),
                                Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.05))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            
                            _PasswordRequirement(label: '8 or more letters', isValid: _hasMinLength),
                            _PasswordRequirement(label: 'At least 1 BIG letter (A-Z)', isValid: _hasUppercase),
                            _PasswordRequirement(label: 'At least 1 number (0-9)', isValid: _hasNumber),
                            _PasswordRequirement(label: '1 special mark (@, #, !, etc.)', isValid: _hasSpecialChar),
                            
                            const SizedBox(height: 16),
                            
                            AuthTextField(
                              controller: _confirmPasswordController,
                              label: 'Confirm Password',
                              hint: 'Repeat your password',
                              icon: Icons.lock_reset_outlined,
                              obscureText: true,
                            ),
                            const SizedBox(height: 12),
                            if (_confirmPasswordController.text.isNotEmpty)
                              _PasswordRequirement(label: 'Passwords Match', isValid: _passwordsMatch),
                            
                            const SizedBox(height: 24),
                            
                            const Text('Job / Position', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: kBackground.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(kRadius),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedPosition,
                                  isExpanded: true,
                                  dropdownColor: kSurface,
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kAccent),
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                  items: _positions.map((String position) {
                                    return DropdownMenuItem<String>(
                                      value: position,
                                      child: Text(position),
                                    );
                                  }).toList(),
                                  onChanged: (String? newValue) {
                                    if (newValue != null) {
                                      setState(() {
                                        _selectedPosition = newValue;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            AuthButton(
                              label: widget.isGoogleSignUp ? 'Save Profile' : 'Create Account',
                              onPressed: _register,
                              isLoading: _isRegistering,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (!widget.isGoogleSignUp)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Already have an account?",
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: TextButton.styleFrom(
                                foregroundColor: kAccent,
                                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
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
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
            size: 14,
            color: isValid ? kAccent : Colors.white12,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isValid ? Colors.white70 : Colors.white24,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
