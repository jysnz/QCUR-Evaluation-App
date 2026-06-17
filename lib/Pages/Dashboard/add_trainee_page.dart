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
  final List<String> _selectedRoles = [];
  bool _isLoading = false;
  final supabase = Supabase.instance.client;

  final List<String> _roles = [
    'Programmer',
    'Builder',
    'Designer',
    'Notebook Manager',
    'Driver',
    'Coach Driver'
  ];

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
      final traineeData = await supabase.from('trainees').insert({
        'full_name': _nameController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'role': _selectedRoles,
        'creator_id': supabase.auth.currentUser!.id,
      }).select().single();

      // Automatically assign to session
      await supabase.from('session_trainees').insert({
        'session_id': widget.sessionId,
        'trainee_id': traineeData['id'],
      });

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
        title: Text(
          'ADD NEW TRAINEE',
          style: AppTypography.h3.copyWith(letterSpacing: 2),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: kForegroundMuted),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          const TechnicalGridBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(kPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TechnicalCard(
                    padding: const EdgeInsets.all(kPaddingLarge),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(
                          title: 'Who is this?',
                          subtitle: 'Enter their name',
                        ),
                        const SizedBox(height: 32),
                        AppTextField(
                          label: 'FULL NAME',
                          hint: 'Enter name here',
                          controller: _nameController,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  TechnicalCard(
                    padding: const EdgeInsets.all(kPaddingLarge),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(
                          title: 'What do they do?',
                          subtitle: 'Select their roles',
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 8,
                          runSpacing: 12,
                          children: _roles.map((role) {
                            final isSelected = _selectedRoles.contains(role);
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedRoles.remove(role);
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
                                    color: isSelected ? kAccent : Colors.white10,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                                      size: 16,
                                      color: isSelected ? kAccent : kForegroundDisabled,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      role.toUpperCase(),
                                      style: AppTypography.overline.copyWith(
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
                        child: TechnicalButton(
                          label: 'ADD MORE',
                          onTap: () => _saveTrainee(addAnother: true),
                          isLoading: _isLoading,
                          isSecondary: true,
                          icon: Icons.add_to_photos_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TechnicalButton(
                          label: 'FINISH',
                          onTap: () => _saveTrainee(addAnother: false),
                          isLoading: _isLoading,
                          icon: Icons.check_circle_outline,
                        ),
                      ),
                    ],
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
