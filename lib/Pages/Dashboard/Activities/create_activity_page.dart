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
        const SnackBar(content: Text('Please enter a name for each question or remove empty ones')),
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
        // Sub-activities are always directly graded; parent activities are graded only if no subs
        'is_graded': isSubActivity || namedSubs.isEmpty,
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
        if (isSubActivity) {
          // Create as siblings under the same parent activity
          final siblingInserts = namedSubs.asMap().entries.map((e) {
            final Map<String, dynamic> sub = {
              'session_id': widget.sessionId,
              'parent_id': widget.parentId,
              'name': e.value.nameController.text.trim(),
              'is_graded': true,
              'scoring_direction': e.value.scoringDirection,
              'order_index': nextIndex + 1 + e.key,
            };
            if (!isAllRoles && _targetRoleId != null) {
              sub['target_role_id'] = _targetRoleId;
              sub['target_role'] = insertData['target_role'];
            }
            return sub;
          }).toList();
          await supabase.from('activities').insert(siblingInserts);
        } else {
          // Create as children of the newly created parent activity
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
      }

      AppCache.instance.invalidateWhere((k) => k.startsWith('acts:') && k.contains(widget.sessionId));

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: kSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(color: kSuccess, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 32, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(
                  isSubActivity ? 'Sub-activity Created!' : 'Activity Created!',
                  style: AppTypography.h3,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  '"${_nameController.text.trim()}" has been added successfully.',
                  style: AppTypography.caption.copyWith(color: kForegroundMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                AppButton(
                  label: 'Done',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop(true);
                  },
                ),
              ],
            ),
          ),
        );
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
        toolbarHeight: 44,
        title: Text(
          isSubActivity ? 'Add Sub-activity' : 'New Activity',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: kForegroundMuted, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: ResponsiveContainer(
            maxWidth: kMaxWidthForm,
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
                          padding: EdgeInsets.zero,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _field(
                                icon: isSubActivity ? Icons.subdirectory_arrow_right_rounded : Icons.add_task_rounded,
                                hint: 'Activity name...',
                                controller: _nameController,
                              ),
                              const Divider(height: 1, color: kBorder, indent: 40),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    const Icon(Icons.trending_up_rounded, size: 15, color: kAccent),
                                    const SizedBox(width: 10),
                                    Text('Scoring', style: AppTypography.caption.copyWith(color: kForegroundMuted, fontSize: 11)),
                                    const Spacer(),
                                    _mainScoringChip(label: 'Higher ▲', value: 'higher_is_better'),
                                    const SizedBox(width: 5),
                                    _mainScoringChip(label: 'Lower ▼', value: 'lower_is_better'),
                                  ],
                                ),
                              ),
                              if (!isSubActivity) ...[
                                const Divider(height: 1, color: kBorder, indent: 40),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.psychology_outlined, size: 15, color: kAccent),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: DropdownButtonHideUnderline(
                                          child: _isFetchingRoles
                                              ? const Padding(
                                                  padding: EdgeInsets.symmetric(vertical: 8),
                                                  child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)),
                                                )
                                              : DropdownButton<String>(
                                                  value: _targetRoleId,
                                                  isExpanded: true,
                                                  hint: Text('Select a position', style: AppTypography.label.copyWith(color: kForegroundDisabled, fontSize: 12)),
                                                  dropdownColor: kSurfaceElevated,
                                                  style: AppTypography.body.copyWith(fontSize: 12, color: kForeground),
                                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kAccent, size: 15),
                                                  isDense: true,
                                                  items: [
                                                    DropdownMenuItem<String>(
                                                      value: '__all__',
                                                      child: Row(children: [
                                                        const Icon(Icons.groups_rounded, size: 13, color: kAccent),
                                                        const SizedBox(width: 6),
                                                        Text('All Positions', style: AppTypography.body.copyWith(color: kAccent, fontSize: 12)),
                                                      ]),
                                                    ),
                                                    ..._roles.map((role) => DropdownMenuItem<String>(
                                                      value: role['id'].toString(),
                                                      child: Text(role['name'].toString(), style: AppTypography.body.copyWith(fontSize: 12)),
                                                    )),
                                                  ],
                                                  onChanged: (v) => setState(() => _targetRoleId = v),
                                                ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (widget.inheritedRoleId != null) ...[
                                const Divider(height: 1, color: kBorder, indent: 40),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.lock_outline_rounded, size: 15, color: kAccent),
                                      const SizedBox(width: 10),
                                      Text(
                                        _getInheritedRoleName(),
                                        style: AppTypography.body.copyWith(fontSize: 12, color: kAccent, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(width: 6),
                                      Text('(inherited)', style: AppTypography.caption.copyWith(fontSize: 10, color: kForegroundDisabled)),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Sub-activities / additional questions section
                        const SizedBox(height: 16),
                        if (isSubActivity)
                          _buildSubActivitiesSection(
                            title: 'MORE QUESTIONS',
                            addLabel: 'Add Question',
                          )
                        else
                          _buildSubActivitiesSection(),

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
      ),
    );
  }

  Widget _buildSubActivitiesSection({
    String title = 'SUB-ACTIVITIES',
    String addLabel = 'Add Sub-activity',
  }) {
    return AppCard(
      padding: const EdgeInsets.all(kPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree_outlined, size: 14, color: kInfo),
              const SizedBox(width: 6),
              Text(title, style: AppTypography.overline.copyWith(color: kInfo, fontSize: 10, letterSpacing: 1.1)),
              const Spacer(),
              Text('Optional', style: AppTypography.caption.copyWith(fontSize: 10)),
            ],
          ),
          if (_subDrafts.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...List.generate(_subDrafts.length, (i) => _buildSubActivityRow(i)),
          ],
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => _subDrafts.add(_SubActivityDraft())),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: kAccent.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(kRadius),
                border: Border.all(color: kAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_rounded, size: 15, color: kAccent),
                  const SizedBox(width: 6),
                  Text(addLabel, style: AppTypography.body.copyWith(color: kAccent, fontWeight: FontWeight.w600, fontSize: 12)),
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: kSurfaceElevated,
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: kAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: AppTypography.caption.copyWith(color: kAccent, fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: draft.nameController,
                    style: AppTypography.body.copyWith(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Sub-activity name...',
                      hintStyle: AppTypography.label.copyWith(color: kForegroundDisabled, fontSize: 12),
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
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.close_rounded, size: 15, color: kForegroundDisabled.withValues(alpha: 0.6)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 26),
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
        Text('Score: ', style: AppTypography.caption.copyWith(fontSize: 10)),
        _scoringChip(label: 'Higher ▲', value: 'higher_is_better', draft: draft),
        const SizedBox(width: 5),
        _scoringChip(label: 'Lower ▼', value: 'lower_is_better', draft: draft),
      ],
    );
  }

  Widget _scoringChip({required String label, required String value, required _SubActivityDraft draft}) {
    final isSelected = draft.scoringDirection == value;
    return GestureDetector(
      onTap: () => setState(() => draft.scoringDirection = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? kAccent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(kRadiusSmall),
          border: Border.all(color: isSelected ? kAccent : kBorder.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: isSelected ? kAccent : kForegroundMuted,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 10,
          ),
        ),
      ),
    );
  }

  String _getInheritedRoleName() {
    if (_isFetchingRoles) return 'Loading...';
    final role = _roles.cast<Map<String, dynamic>?>().firstWhere(
      (r) => r?['id'].toString() == widget.inheritedRoleId,
      orElse: () => null,
    );
    return role?['name']?.toString() ?? 'Inherited from parent';
  }

  Widget _field({required IconData icon, required String hint, required TextEditingController controller}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 15, color: kAccent),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              style: AppTypography.body.copyWith(fontSize: 13),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppTypography.label.copyWith(color: kForegroundDisabled, fontSize: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mainScoringChip({required String label, required String value}) {
    final isSelected = _scoringDirection == value;
    return GestureDetector(
      onTap: () => setState(() => _scoringDirection = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? kAccent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(kRadiusSmall),
          border: Border.all(color: isSelected ? kAccent : kBorder.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: isSelected ? kAccent : kForegroundMuted,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildProTip(bool isSubActivity) {
    return AppCard(
      color: kInfo.withValues(alpha: 0.05),
      border: Border.all(color: kInfo.withValues(alpha: 0.2)),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline_rounded, color: kInfo, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isSubActivity
                  ? 'Use "Add Question" to create multiple sub-activities at once. They inherit the role from their parent activity.'
                  : 'When an activity has sub-activities, only the sub-activities are scored. The parent acts as a grouping header.',
              style: const TextStyle(color: kForegroundMuted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
