import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final data = await supabase
            .from('user_accounts')
            .select()
            .eq('id', user.id)
            .single();
        setState(() {
          _userData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading account: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await GoogleSignIn().signOut();
      await supabase.auth.signOut();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBackground,
        title: const Text('Account', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: AppBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: kAccent))
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(kPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: CircleAvatar(
                          radius: 60,
                          backgroundColor: kSurface,
                          backgroundImage: _userData?['avatar_url'] != null
                              ? NetworkImage(_userData!['avatar_url'])
                              : null,
                          child: _userData?['avatar_url'] == null
                              ? const Icon(Icons.person_outline_rounded, size: 60, color: kForegroundMuted)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 32),
                      AppCard(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoRow('Name', _userData?['full_name'] ?? 'Not set'),
                            const Divider(height: 32, color: kBorder),
                            _buildInfoRow('Email', _userData?['email'] ?? 'Not set'),
                            const Divider(height: 32, color: kBorder),
                            _buildInfoRow('Position', _userData?['position'] ?? 'Not set'),
                          ],
                        ),
                      ),
                      const Spacer(),
                      AppButton(
                        label: 'Sign Out',
                        color: kError,
                        icon: Icons.logout_rounded,
                        onTap: _signOut,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.label,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
