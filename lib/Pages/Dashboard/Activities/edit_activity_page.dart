import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class EditActivityPage extends StatefulWidget {
  final String activityId;
  final String sessionId;
  final String currentName;
  final String currentScoringDirection;
  final String? currentRoleId;
  final bool canChangeRole;

  const EditActivityPage({
    super.key,
    required this.activityId,
    required this.sessionId,
    required this.currentName,
    required this.currentScoringDirection,
    this.currentRoleId,
    this.canChangeRole = false,
  });

  @override
  State<EditActivityPage> createState() => _EditActivityPageState();
}

class _EditActivityPageState extends State<EditActivityPage> {
  late final TextEditingController _nameController;
  late String _scoringDirection;
  late String? _targetRoleId;
  bool _isLoading = false;
  bool _isFetchingRoles = false;
  List<Map<String, dynamic>> _roles = [];
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
    _scoringDirection = widget.currentScoringDirection;
    _targetRoleId = widget.currentRoleId;
    if (widget.canChangeRole) _fetchRoles();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _fetchRoles() async {
    setState(() => _isFetchingRoles = true);
    try {
      final cached = AppCache.instance.get<List<dynamic>>('roles');
      final data = cached ?? await supabase.from('roles').select().order('name');
      if (cached == null) {
        AppCache.instance.set('roles', data, ttl: const Duration(minutes: 30));
      }
      setState(() {
        _roles = List<Map<String, dynamic>>.from(data);
        _isFetchingRoles = false;
      });
    } catch (e) {
      setState(() => _isFetchingRoles = false);
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an activity name')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final updateData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'scoring_direction': _scoringDirection,
      };

      if (widget.canChangeRole && _targetRoleId != null) {
        updateData['target_role_id'] = _targetRoleId;
        final role = _roles.cast<Map<String, dynamic>?>().firstWhere(
          (r) => r?['id'].toString() == _targetRoleId,
          orElse: () => null,
        );
        if (role != null) updateData['target_role'] = role['name'];
      }

      await supabase.from('activities').update(updateData).eq('id', widget.activityId);

      AppCache.instance.invalidateWhere((k) => k.startsWith('acts:'));
      AppCache.instance.invalidateWhere((k) => k.startsWith('subs:'));
      AppCache.instance.invalidateWhere((k) => k.startsWith('st:'));

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Edit Activity', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: kForegroundMuted),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(kPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: AppCard(
                      padding: const EdgeInsets.all(kPaddingLarge),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: kAccent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(kRadiusSmall),
                                ),
                                child: const Icon(Icons.edit_rounded, size: 18, color: kAccent),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: SectionHeader(
                                  title: 'Edit Activity',
                                  subtitle: 'Update activity details',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          AppTextField(
                            label: 'Activity Name',
                            hint: 'Enter activity name',
                            controller: _nameController,
                            icon: Icons.add_task_rounded,
                          ),
                          const SizedBox(height: 24),
                          _buildScoringDirectionDropdown(),
                          if (widget.canChangeRole) ...[
                            const SizedBox(height: 24),
                            _buildRoleDropdown(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AppButton(
                  label: 'Save Changes',
                  onTap: _isLoading ? null : _save,
                  isLoading: _isLoading,
                  icon: Icons.check_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoringDirectionDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Scoring Type', style: AppTypography.label),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: kSurfaceElevated,
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(color: kBorder.withValues(alpha: 0.5)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _scoringDirection,
              isExpanded: true,
              dropdownColor: kSurfaceElevated,
              style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.bold),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kAccent),
              items: const [
                DropdownMenuItem(value: 'higher_is_better', child: Text('Higher is better (%)')),
                DropdownMenuItem(value: 'lower_is_better', child: Text('Lower is better (Time/Errors)')),
              ],
              onChanged: (v) => setState(() => _scoringDirection = v!),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Assign to Position', style: AppTypography.label),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: kSurfaceElevated,
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(color: kBorder.withValues(alpha: 0.5)),
          ),
          child: DropdownButtonHideUnderline(
            child: _isFetchingRoles
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)),
                    ),
                  )
                : DropdownButton<String>(
                    value: _targetRoleId,
                    isExpanded: true,
                    hint: const Text('Select a position', style: TextStyle(color: kForegroundDisabled, fontSize: 14)),
                    dropdownColor: kSurfaceElevated,
                    style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.bold),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kAccent),
                    items: _roles.map((role) => DropdownMenuItem(
                      value: role['id'].toString(),
                      child: Text(role['name'].toString()),
                    )).toList(),
                    onChanged: (v) => setState(() => _targetRoleId = v),
                  ),
          ),
        ),
      ],
    );
  }
}
