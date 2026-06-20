import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class EditTraineePage extends StatefulWidget {
  final Map<String, dynamic> trainee;
  final String sessionId;

  const EditTraineePage({
    super.key,
    required this.trainee,
    required this.sessionId,
  });

  @override
  State<EditTraineePage> createState() => _EditTraineePageState();
}

class _EditTraineePageState extends State<EditTraineePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  final List<Map<String, dynamic>> _selectedRoles = [];
  List<Map<String, dynamic>> _availableRoles = [];
  bool _isLoading = true;
  bool _isSaving = false;
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.trainee['full_name']?.toString() ?? '');
    _emailController = TextEditingController(text: widget.trainee['email']?.toString() ?? '');
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final cached = AppCache.instance.get<List<dynamic>>('roles');
      final rolesData = cached ?? await supabase.from('roles').select().order('name');
      if (cached == null) {
        AppCache.instance.set('roles', rolesData, ttl: const Duration(minutes: 30));
      }
      final roles = List<Map<String, dynamic>>.from(rolesData);

      final assignedRoles = await supabase
          .from('trainee_roles')
          .select('role_id')
          .eq('trainee_id', widget.trainee['id']);

      final assignedIds = Set<String>.from(
        (assignedRoles as List).map((r) => r['role_id'].toString()),
      );

      setState(() {
        _availableRoles = roles;
        _selectedRoles.addAll(roles.where((r) => assignedIds.contains(r['id'].toString())));
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading trainee data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
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
      final traineeId = widget.trainee['id'] as String;
      final roleNames = _selectedRoles.map((r) => r['name'].toString()).toList();

      final updateData = <String, dynamic>{
        'full_name': _nameController.text.trim(),
        'role': roleNames,
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      };

      await supabase.from('trainees').update(updateData).eq('id', traineeId);

      await supabase.from('trainee_roles').delete().eq('trainee_id', traineeId);
      await supabase.from('trainee_roles').insert(
        _selectedRoles.map((r) => {'trainee_id': traineeId, 'role_id': r['id']}).toList(),
      );

      AppCache.instance.invalidate('trainees');
      AppCache.instance.invalidate('st_full:${widget.sessionId}');
      AppCache.instance.invalidateWhere((k) => k.startsWith('st:'));

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
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
        title: const Text('Edit Trainee', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: kForegroundMuted),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: AppBackground(
        child: _isLoading
            ? const AppLoader()
            : SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(kPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Compact profile preview
                            _buildProfilePreview(),
                            const SizedBox(height: 20),

                            // Info fields
                            AppCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  _field(
                                    icon: Icons.person_outline_rounded,
                                    hint: 'Full Name',
                                    controller: _nameController,
                                  ),
                                  const Divider(height: 1, color: kBorder, indent: 44),
                                  _field(
                                    icon: Icons.email_outlined,
                                    hint: 'Email (optional)',
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Position card
                            AppCard(
                              padding: const EdgeInsets.all(kPadding),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.psychology_outlined, size: 14, color: kInfo),
                                      const SizedBox(width: 6),
                                      Text(
                                        'POSITION',
                                        style: AppTypography.overline.copyWith(
                                          color: kInfo, fontSize: 10, letterSpacing: 1.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (_availableRoles.isEmpty)
                                    const Center(child: Text('No roles available', style: AppTypography.caption))
                                  else
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 8,
                                      children: _availableRoles.map((role) {
                                        final isSelected = _selectedRoles.any((r) => r['id'] == role['id']);
                                        return GestureDetector(
                                          onTap: () => setState(() {
                                            if (isSelected) {
                                              _selectedRoles.removeWhere((r) => r['id'] == role['id']);
                                            } else {
                                              _selectedRoles.add(role);
                                            }
                                          }),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 150),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                                                  isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                                                  size: 13,
                                                  color: isSelected ? kAccent : kForegroundDisabled,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  role['name'].toString(),
                                                  style: AppTypography.body.copyWith(
                                                    color: isSelected ? kForeground : kForegroundMuted,
                                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                                    fontSize: 12,
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
                          ],
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(kPadding, 0, kPadding, kPadding),
                      child: AppButton(
                        label: 'Save Changes',
                        onTap: _isSaving ? null : _save,
                        isLoading: _isSaving,
                        icon: Icons.check_rounded,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildProfilePreview() {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _nameController,
          builder: (_, child) {
            final name = _nameController.text.trim();
            return Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: kAccent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: kAccent.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: Text(
                  name.isEmpty ? '?' : _getInitials(name),
                  style: AppTypography.body.copyWith(
                    color: kAccent, fontWeight: FontWeight.w700, fontSize: 16,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedBuilder(
                animation: _nameController,
                builder: (_, child) => Text(
                  _nameController.text.trim().isEmpty ? 'Member' : _nameController.text.trim(),
                  style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              AnimatedBuilder(
                animation: _nameController,
                builder: (_, child) => Text(
                  _selectedRoles.isEmpty ? 'No role assigned' : _selectedRoles.map((r) => r['name']).join(', '),
                  style: AppTypography.caption.copyWith(
                    color: _selectedRoles.isEmpty ? kForegroundDisabled : kAccent,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field({
    required IconData icon,
    required String hint,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 17, color: kAccent),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: AppTypography.body.copyWith(fontSize: 13),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppTypography.label.copyWith(color: kForegroundDisabled, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
