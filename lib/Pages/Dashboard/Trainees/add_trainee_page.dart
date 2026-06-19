import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class AddTraineePage extends StatefulWidget {
  final String sessionId;

  const AddTraineePage({
    super.key,
    required this.sessionId,
  });

  @override
  State<AddTraineePage> createState() => _AddTraineePageState();
}

class _AddTraineePageState extends State<AddTraineePage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final List<Map<String, dynamic>> _selectedRoles = [];
  bool _isLoading = true;
  bool _isSaving = false;
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _availableRoles = [];

  @override
  void initState() {
    super.initState();
    _fetchRoles();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _fetchRoles() async {
    try {
      final cached = AppCache.instance.get<List<dynamic>>('roles');
      final data = cached ?? await supabase.from('roles').select().order('name');
      if (cached == null) {
        AppCache.instance.set('roles', data, ttl: const Duration(minutes: 30));
      }
      setState(() {
        _availableRoles = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching roles: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveTrainee({bool addAnother = false}) async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name')),
      );
      return;
    }

    if (_selectedRoles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one role')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final roleNames = _selectedRoles.map((r) => r['name'].toString()).toList();

      final traineeData = await supabase.from('trainees').insert({
        'full_name': _nameController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'role': roleNames,
        'creator_id': supabase.auth.currentUser!.id,
      }).select().single();

      final traineeId = traineeData['id'];

      await supabase.from('session_trainees').insert({
        'session_id': widget.sessionId,
        'trainee_id': traineeId,
      });

      final List<Map<String, dynamic>> roleAssignments = _selectedRoles.map((role) => {
        'trainee_id': traineeId,
        'role_id': role['id'],
      }).toList();

      await supabase.from('trainee_roles').insert(roleAssignments);
      AppCache.instance.invalidate('trainees');
      AppCache.instance.invalidate('st_full:${widget.sessionId}');

      if (mounted) {
        if (addAnother) {
          _nameController.clear();
          _emailController.clear();
          setState(() {
            _selectedRoles.clear();
            _isSaving = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Member added. You can add another.')),
          );
        } else {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Add New Member',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: kForegroundMuted),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: AppBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: kAccent))
            : SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(kPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Avatar preview
                            Center(
                              child: AnimatedBuilder(
                                animation: _nameController,
                                builder: (context, _) {
                                  final initials = _nameController.text.trim().isEmpty
                                      ? '?'
                                      : _getInitials(_nameController.text.trim());
                                  return Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: kAccent.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: kAccent.withValues(alpha: 0.3), width: 2),
                                    ),
                                    child: Center(
                                      child: Text(
                                        initials,
                                        style: AppTypography.h2.copyWith(color: kAccent, fontSize: 26),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Identity card
                            AppCard(
                              padding: const EdgeInsets.all(kPaddingLarge),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: kAccent.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(kRadiusSmall),
                                        ),
                                        child: const Icon(Icons.badge_outlined, size: 16, color: kAccent),
                                      ),
                                      const SizedBox(width: 12),
                                      const SectionHeader(
                                        title: 'Identity',
                                        subtitle: 'Basic member information',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  AppTextField(
                                    label: 'Full Name',
                                    hint: 'Enter full name',
                                    controller: _nameController,
                                    icon: Icons.person_outline_rounded,
                                  ),
                                  const SizedBox(height: 16),
                                  AppTextField(
                                    label: 'Email (Optional)',
                                    hint: 'Enter email address',
                                    controller: _emailController,
                                    icon: Icons.alternate_email_rounded,
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Role card
                            AppCard(
                              padding: const EdgeInsets.all(kPaddingLarge),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: kInfo.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(kRadiusSmall),
                                        ),
                                        child: const Icon(Icons.psychology_outlined, size: 16, color: kInfo),
                                      ),
                                      const SizedBox(width: 12),
                                      const SectionHeader(
                                        title: 'Position',
                                        subtitle: 'Assign one or more roles',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  if (_availableRoles.isEmpty)
                                    const Center(
                                      child: Text('No roles available', style: AppTypography.caption),
                                    )
                                  else
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 10,
                                      children: _availableRoles.map((role) {
                                        final isSelected = _selectedRoles.any((r) => r['id'] == role['id']);
                                        return GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              if (isSelected) {
                                                _selectedRoles.removeWhere((r) => r['id'] == role['id']);
                                              } else {
                                                _selectedRoles.add(role);
                                              }
                                            });
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 180),
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                                            decoration: BoxDecoration(
                                              color: isSelected ? kAccent.withValues(alpha: 0.12) : kSurfaceElevated,
                                              borderRadius: BorderRadius.circular(kRadiusSmall),
                                              border: Border.all(
                                                color: isSelected ? kAccent : kBorder,
                                                width: isSelected ? 1.5 : 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                                                  size: 15,
                                                  color: isSelected ? kAccent : kForegroundDisabled,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  role['name'].toString(),
                                                  style: AppTypography.body.copyWith(
                                                    color: isSelected ? kForeground : kForegroundMuted,
                                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),

                    // Action buttons
                    Padding(
                      padding: const EdgeInsets.fromLTRB(kPadding, 0, kPadding, kPadding),
                      child: Row(
                        children: [
                          Expanded(
                            child: AppButton(
                              label: 'Add Another',
                              onTap: _isSaving ? null : () => _saveTrainee(addAnother: true),
                              isLoading: _isSaving,
                              isSecondary: true,
                              icon: Icons.add_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: AppButton(
                              label: 'Finish',
                              onTap: _isSaving ? null : () => _saveTrainee(addAnother: false),
                              isLoading: _isSaving,
                              icon: Icons.check_circle_outline_rounded,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
