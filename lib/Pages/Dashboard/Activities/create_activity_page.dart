import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class CreateActivityPage extends StatefulWidget {
  final String sessionId;
  final String? parentId;
  final String? parentName;
  final String? inheritedRoleId;

  const CreateActivityPage({
    super.key,
    required this.sessionId,
    this.parentId,
    this.parentName,
    this.inheritedRoleId,
  });

  @override
  State<CreateActivityPage> createState() => _CreateActivityPageState();
}

class _CreateActivityPageState extends State<CreateActivityPage> {
  final _nameController = TextEditingController();
  String _scoringDirection = 'higher_is_better';
  String? _targetRoleId;
  bool _isLoading = false;
  bool _isFetchingRoles = true;
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _roles = [];

  @override
  void initState() {
    super.initState();
    _targetRoleId = widget.inheritedRoleId;
    _fetchRoles();
  }

  Future<void> _fetchRoles() async {
    setState(() => _isFetchingRoles = true);
    try {
      final cached = AppCache.instance.get<List<dynamic>>('roles');
      final data = cached ??
          await supabase.from('roles').select().order('name');
      if (cached == null) {
        AppCache.instance.set('roles', data, ttl: const Duration(minutes: 30));
      }
      setState(() {
        _roles = List<Map<String, dynamic>>.from(data);
        _isFetchingRoles = false;
      });
    } catch (e) {
      debugPrint('Error fetching roles: $e');
      setState(() => _isFetchingRoles = false);
    }
  }

  Future<void> _saveActivity() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an activity name')),
      );
      return;
    }

    final isSubActivity = widget.parentId != null;
    if (!isSubActivity && _targetRoleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please assign a position to this activity')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final currentActivities = await supabase
          .from('activities')
          .select('order_index')
          .eq('session_id', widget.sessionId)
          .filter('parent_id', widget.parentId == null ? 'is' : 'eq', widget.parentId);

      int nextIndex = 0;
      if (currentActivities.isNotEmpty) {
        nextIndex = (currentActivities.map((a) => a['order_index'] as int).reduce((a, b) => a > b ? a : b)) + 1;
      }

      final Map<String, dynamic> insertData = {
        'session_id': widget.sessionId,
        'parent_id': widget.parentId,
        'name': _nameController.text.trim(),
        'is_graded': true,
        'scoring_direction': _scoringDirection,
        'order_index': nextIndex,
      };

      if (_targetRoleId != null) {
        insertData['target_role_id'] = _targetRoleId;
        final role = _roles.cast<Map<String, dynamic>?>().firstWhere(
          (r) => r?['id'].toString() == _targetRoleId,
          orElse: () => null,
        );
        if (role != null) insertData['target_role'] = role['name'];
      }

      await supabase.from('activities').insert(insertData);
      AppCache.instance.invalidateWhere((k) => k.startsWith('acts:') && k.contains(widget.sessionId));

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving activity: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSubActivity = widget.parentId != null;

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          isSubActivity ? 'Add Sub-activity' : 'New Activity',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppCard(
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
                                    child: Icon(
                                      isSubActivity ? Icons.subdirectory_arrow_right_rounded : Icons.add_task_rounded,
                                      size: 18,
                                      color: kAccent,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: SectionHeader(
                                      title: 'Configuration',
                                      subtitle: isSubActivity
                                          ? 'Sub-activity of: ${widget.parentName}'
                                          : 'Defining a primary assessment activity',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 28),
                              AppTextField(
                                label: 'Activity Name',
                                hint: 'e.g., Technical Assessment, Physical Training...',
                                controller: _nameController,
                                icon: Icons.add_task_rounded,
                              ),
                              const SizedBox(height: 24),
                              _buildScoringDirectionDropdown(),
                              const SizedBox(height: 24),
                              if (!isSubActivity)
                                _buildRoleAssignmentDropdown()
                              else if (widget.inheritedRoleId != null)
                                _buildLockedRoleDisplay(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildProTip(isSubActivity),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AppButton(
                  label: isSubActivity ? 'Create Sub-activity' : 'Create Activity',
                  onTap: _saveActivity,
                  isLoading: _isLoading,
                  icon: Icons.add_task_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleAssignmentDropdown() {
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
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent))),
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

  Widget _buildLockedRoleDisplay() {
    final inheritedRole = _roles.cast<Map<String, dynamic>?>().firstWhere(
      (r) => r?['id'].toString() == widget.inheritedRoleId,
      orElse: () => null,
    );
    final roleName = inheritedRole?['name']?.toString() ?? 'Inherited from parent';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Assigned Role', style: AppTypography.label),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: kAccent.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(kRadiusSmall),
            border: Border.all(color: kAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 16, color: kAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roleName,
                      style: AppTypography.bodyLg.copyWith(color: kAccent, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Inherited from parent activity',
                      style: AppTypography.caption.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
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
                DropdownMenuItem(
                  value: 'higher_is_better',
                  child: Text('Higher is better (%)'),
                ),
                DropdownMenuItem(
                  value: 'lower_is_better',
                  child: Text('Lower is better (Time/Errors)'),
                ),
              ],
              onChanged: (v) => setState(() => _scoringDirection = v!),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProTip(bool isSubActivity) {
    return AppCard(
      color: kInfo.withValues(alpha: 0.05),
      border: Border.all(color: kInfo.withValues(alpha: 0.2)),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline_rounded, color: kInfo, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isSubActivity
                  ? 'Sub-activities inherit their role assignment from the parent activity.'
                  : 'When an activity has sub-activities, only the sub-activities are scored. The parent acts as a grouping header.',
              style: const TextStyle(color: kForegroundMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
