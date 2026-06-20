import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class _SubActivityDraft {
  final TextEditingController nameController = TextEditingController();
  String scoringDirection = 'higher_is_better';
  _SubActivityDraft();
}

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
  // '__all__' sentinel = activity applies to all roles (target_role_id stays null in DB)
  String? _targetRoleId;
  bool _isLoading = false;
  bool _isFetchingRoles = true;
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _roles = [];
  final List<_SubActivityDraft> _subDrafts = [];

  @override
  void initState() {
    super.initState();
    _targetRoleId = widget.inheritedRoleId;
    _fetchRoles();
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final d in _subDrafts) {
      d.nameController.dispose();
    }
    super.dispose();
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
        const SnackBar(content: Text('Please assign a position or select All Positions')),
      );
      return;
    }

    final namedSubs = _subDrafts.where((d) => d.nameController.text.trim().isNotEmpty).toList();
    if (_subDrafts.isNotEmpty && namedSubs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name for each sub-activity or remove empty ones')),
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
        'is_graded': namedSubs.isEmpty,
        'scoring_direction': _scoringDirection,
        'order_index': nextIndex,
      };

      final isAllRoles = _targetRoleId == '__all__';
      if (!isAllRoles && _targetRoleId != null) {
        insertData['target_role_id'] = _targetRoleId;
        final role = _roles.cast<Map<String, dynamic>?>().firstWhere(
          (r) => r?['id'].toString() == _targetRoleId,
          orElse: () => null,
        );
        if (role != null) insertData['target_role'] = role['name'];
      }

      final parentData = await supabase.from('activities').insert(insertData).select().single();
      final parentId = parentData['id'] as String;

      if (namedSubs.isNotEmpty) {
        final subInserts = namedSubs.asMap().entries.map((e) {
          final Map<String, dynamic> sub = {
            'session_id': widget.sessionId,
            'parent_id': parentId,
            'name': e.value.nameController.text.trim(),
            'is_graded': true,
            'scoring_direction': e.value.scoringDirection,
            'order_index': e.key,
          };
          if (!isAllRoles && _targetRoleId != null) {
            sub['target_role_id'] = _targetRoleId;
            sub['target_role'] = insertData['target_role'];
          }
          return sub;
        }).toList();

        await supabase.from('activities').insert(subInserts);
      }

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
                        // Parent activity config card
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

                        // Sub-activities section (only for parent activities)
                        if (!isSubActivity) ...[
                          const SizedBox(height: 16),
                          _buildSubActivitiesSection(),
                        ],

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

  Widget _buildSubActivitiesSection() {
    return AppCard(
      padding: const EdgeInsets.all(kPaddingLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kInfo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(kRadiusSmall),
                ),
                child: const Icon(Icons.account_tree_outlined, size: 18, color: kInfo),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: SectionHeader(
                  title: 'Sub-activities',
                  subtitle: 'Optional — break this activity into steps',
                ),
              ),
            ],
          ),
          if (_subDrafts.isNotEmpty) ...[
            const SizedBox(height: 20),
            ...List.generate(_subDrafts.length, (i) => _buildSubActivityRow(i)),
          ],
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              setState(() => _subDrafts.add(_SubActivityDraft()));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: kAccent.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(kRadius),
                border: Border.all(
                  color: kAccent.withValues(alpha: 0.3),
                  style: BorderStyle.solid,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_rounded, size: 18, color: kAccent),
                  const SizedBox(width: 8),
                  Text(
                    'Add Sub-activity',
                    style: AppTypography.body.copyWith(color: kAccent, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubActivityRow(int index) {
    final draft = _subDrafts[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kSurfaceElevated,
          borderRadius: BorderRadius.circular(kRadius),
          border: Border.all(color: kBorder.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: kAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: AppTypography.caption.copyWith(color: kAccent, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: draft.nameController,
                    style: AppTypography.body.copyWith(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Sub-activity name...',
                      hintStyle: AppTypography.label.copyWith(color: kForegroundDisabled),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    draft.nameController.dispose();
                    setState(() => _subDrafts.removeAt(index));
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.close_rounded, size: 18, color: kForegroundDisabled.withValues(alpha: 0.6)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(width: 32),
                _buildScoringToggle(draft),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoringToggle(_SubActivityDraft draft) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Score: ', style: AppTypography.caption.copyWith(fontSize: 11)),
        _scoringChip(
          label: 'Higher ▲',
          value: 'higher_is_better',
          draft: draft,
        ),
        const SizedBox(width: 6),
        _scoringChip(
          label: 'Lower ▼',
          value: 'lower_is_better',
          draft: draft,
        ),
      ],
    );
  }

  Widget _scoringChip({required String label, required String value, required _SubActivityDraft draft}) {
    final isSelected = draft.scoringDirection == value;
    return GestureDetector(
      onTap: () => setState(() => draft.scoringDirection = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? kAccent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(kRadiusSmall),
          border: Border.all(
            color: isSelected ? kAccent : kBorder.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: isSelected ? kAccent : kForegroundMuted,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 11,
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
                    items: [
                      DropdownMenuItem<String>(
                        value: '__all__',
                        child: Row(
                          children: [
                            const Icon(Icons.groups_rounded, size: 16, color: kAccent),
                            const SizedBox(width: 8),
                            Text(
                              'All Positions',
                              style: AppTypography.bodyLg.copyWith(
                                color: kAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ..._roles.map((role) => DropdownMenuItem<String>(
                            value: role['id'].toString(),
                            child: Text(role['name'].toString()),
                          )),
                    ],
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
