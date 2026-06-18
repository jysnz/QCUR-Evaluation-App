import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _availableRoles = [];

  @override
  void initState() {
    super.initState();
    _fetchRoles();
  }

  Future<void> _fetchRoles() async {
    try {
      final data = await supabase.from('roles').select().order('name');
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
        const SnackBar(content: Text('Please enter name')),
      );
      return;
    }

    if (_selectedRoles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a role')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final roleNames = _selectedRoles.map((r) => r['name'].toString()).toList();
      
      final traineeData = await supabase.from('trainees').insert({
        'full_name': _nameController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'role': roleNames,
        'creator_id': supabase.auth.currentUser!.id,
      }).select().single();

      final traineeId = traineeData['id'];

      // 1. Automatically assign to session
      await supabase.from('session_trainees').insert({
        'session_id': widget.sessionId,
        'trainee_id': traineeId,
      });

      // 2. Assign roles in trainee_roles table
      final List<Map<String, dynamic>> roleAssignments = _selectedRoles.map((role) => {
        'trainee_id': traineeId,
        'role_id': role['id'],
      }).toList();

      await supabase.from('trainee_roles').insert(roleAssignments);

      if (mounted) {
        if (addAnother) {
          _nameController.clear();
          _emailController.clear();
          setState(() {
            _selectedRoles.clear();
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Added. You can add another one.')),
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
        setState(() => _isLoading = false);
      }
    }
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
        child: _isLoading && _availableRoles.isEmpty
            ? const Center(child: CircularProgressIndicator(color: kAccent))
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(kPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppCard(
                        padding: const EdgeInsets.all(kPaddingLarge),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionHeader(
                              title: 'Who is this?',
                              subtitle: 'Enter their full name',
                            ),
                            const SizedBox(height: 32),
                            AppTextField(
                              label: 'Full Name',
                              hint: 'Enter name here',
                              controller: _nameController,
                              icon: Icons.person_outline_rounded,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      AppCard(
                        padding: const EdgeInsets.all(kPaddingLarge),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionHeader(
                              title: 'Position',
                              subtitle: 'Select their positions',
                            ),
                            const SizedBox(height: 24),
                            Wrap(
                              spacing: 8,
                              runSpacing: 12,
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
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isSelected ? kAccent.withValues(alpha: 0.1) : kSurfaceElevated,
                                      borderRadius: BorderRadius.circular(kRadiusSmall),
                                      border: Border.all(
                                        color: isSelected ? kAccent : kBorder,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                                          size: 16,
                                          color: isSelected ? kAccent : kForegroundDisabled,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          role['name'].toString(),
                                          style: AppTypography.body.copyWith(
                                            color: isSelected ? kForeground : kForegroundMuted,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: AppButton(
                              label: 'Add More',
                              onTap: () => _saveTrainee(addAnother: true),
                              isLoading: _isLoading,
                              isSecondary: true,
                              icon: Icons.add_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppButton(
                              label: 'Finish',
                              onTap: () => _saveTrainee(addAnother: false),
                              isLoading: _isLoading,
                              icon: Icons.check_circle_outline_rounded,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
