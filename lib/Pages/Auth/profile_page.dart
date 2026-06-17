import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../Widgets/design_system.dart';
import '../../Services/user_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final UserService _userService = UserService();
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final profile = await _userService.getCurrentUserProfile();
      if (mounted) {
        setState(() {
          _userProfile = profile;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pop(); // Back to dashboard which will trigger AuthWrapper redirect
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? 'No Email';
    final fullName = _userProfile?['full_name'] ?? 'User';
    final position = _userProfile?['position'] ?? 'Member';

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'PROFILE',
          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          const TechnicalGridBackground(),
          SafeArea(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: kAccent))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(kPadding),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      // Avatar Section
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: kAccent.withValues(alpha: 0.3), width: 2),
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: kSurface,
                            backgroundImage: _userProfile?['avatar_url'] != null 
                              ? NetworkImage(_userProfile!['avatar_url']) 
                              : null,
                            child: _userProfile?['avatar_url'] == null 
                              ? Text(
                                  fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U',
                                  style: const TextStyle(color: kAccent, fontWeight: FontWeight.bold, fontSize: 32),
                                )
                              : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Info Section
                      TechnicalCard(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            _ProfileInfoRow(
                              icon: Icons.person_outline,
                              label: 'Full Name',
                              value: fullName,
                            ),
                            const Divider(color: Colors.white10, height: 32),
                            _ProfileInfoRow(
                              icon: Icons.email_outlined,
                              label: 'Email Address',
                              value: email,
                            ),
                            const Divider(color: Colors.white10, height: 32),
                            _ProfileInfoRow(
                              icon: Icons.work_outline,
                              label: 'Position',
                              value: position,
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // Logout Button
                      TechnicalButton(
                        label: 'Logout Account',
                        color: Colors.redAccent,
                        icon: Icons.logout_rounded,
                        onTap: _signOut,
                      ),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: kAccent, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
