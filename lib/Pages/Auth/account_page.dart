import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
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
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
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
      if (mounted) Navigator.of(context).pop();
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  Future<void> _editField({
    required String label,
    required String field,
    required String currentValue,
    required IconData icon,
  }) async {
    final controller = TextEditingController(text: currentValue);
    bool isSaving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadius)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                kPadding,
                kPadding,
                kPadding,
                MediaQuery.of(ctx).viewInsets.bottom + kPadding,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 15, color: kAccent),
                      const SizedBox(width: 8),
                      Text(
                        label.toUpperCase(),
                        style: AppTypography.overline.copyWith(color: kAccent, letterSpacing: 1.1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        style: AppTypography.body.copyWith(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Enter $label...',
                          hintStyle: AppTypography.label.copyWith(color: kForegroundDisabled, fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Save',
                    icon: Icons.check_rounded,
                    isLoading: isSaving,
                    onTap: isSaving
                        ? null
                        : () async {
                            final value = controller.text.trim();
                            if (value.isEmpty) return;
                            setModalState(() => isSaving = true);
                            try {
                              final user = supabase.auth.currentUser;
                              if (user == null) return;
                              await supabase
                                  .from('user_accounts')
                                  .update({field: value})
                                  .eq('id', user.id);
                              if (mounted) {
                                setState(() => _userData = {...?_userData, field: value});
                                Navigator.of(ctx).pop();
                              }
                            } catch (e, stackTrace) {
                              await Sentry.captureException(e, stackTrace: stackTrace);
                              setModalState(() => isSaving = false);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error saving: $e')),
                                );
                              }
                            }
                          },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: kBackground,
        elevation: 0,
        toolbarHeight: 44,
        title: const Text('Account', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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
                      _buildAvatar(),
                      const SizedBox(height: 20),
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            _buildEditableRow(
                              icon: Icons.person_outline_rounded,
                              label: 'Name',
                              value: _userData?['full_name'] ?? '',
                              placeholder: 'Not set',
                              onEdit: () => _editField(
                                label: 'Name',
                                field: 'full_name',
                                currentValue: _userData?['full_name'] ?? '',
                                icon: Icons.person_outline_rounded,
                              ),
                            ),
                            const Divider(height: 1, color: kBorder, indent: 44),
                            _buildReadOnlyRow(
                              icon: Icons.email_outlined,
                              value: _userData?['email'] ?? 'Not set',
                              isLast: true,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      AppButton(
                        label: 'Sign Out',
                        color: kError.withValues(alpha: 0.1),
                        textColor: kError,
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

  Widget _buildAvatar() {
    final name = _userData?['full_name'] as String? ?? '';
    final avatarUrl = _userData?['avatar_url'] as String?;
    return Center(
      child: avatarUrl != null
          ? CircleAvatar(
              radius: 36,
              backgroundColor: kSurface,
              backgroundImage: NetworkImage(avatarUrl),
            )
          : Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: kAccent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: kAccent.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: Text(
                  name.isEmpty ? '?' : _getInitials(name),
                  style: AppTypography.h2.copyWith(color: kAccent),
                ),
              ),
            ),
    );
  }

  Widget _buildEditableRow({
    required IconData icon,
    required String label,
    required String value,
    required String placeholder,
    required VoidCallback onEdit,
    bool isLast = false,
  }) {
    final displayValue = value.isEmpty ? placeholder : value;
    final isEmpty = value.isEmpty;
    return InkWell(
      onTap: onEdit,
      borderRadius: isLast
          ? const BorderRadius.vertical(bottom: Radius.circular(kRadius))
          : BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 17, color: kAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayValue,
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isEmpty ? kForegroundDisabled : kForeground,
                ),
              ),
            ),
            const Icon(Icons.edit_rounded, size: 14, color: kForegroundDisabled),
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyRow({required IconData icon, required String value, bool isLast = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 17, color: kForegroundMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: AppTypography.body.copyWith(fontSize: 13, color: kForegroundMuted),
            ),
          ),
        ],
      ),
    );
  }
}
