import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class _SubActivityEdit {
  final String? id; // null = newly added, not yet in DB
  final TextEditingController nameController;
  String scoringDirection;

  _SubActivityEdit({
    this.id,
    String name = '',
    this.scoringDirection = 'higher_is_better',
  }) : nameController = TextEditingController(text: name);

  bool get isNew => id == null;
  void dispose() => nameController.dispose();
}

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
  bool _isFetchingSubs = false;
  List<Map<String, dynamic>> _roles = [];
  List<_SubActivityEdit> _subEdits = [];
  final List<String> _deletedSubIds = [];
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
    _scoringDirection = widget.currentScoringDirection;
    _targetRoleId = widget.currentRoleId;
    if (widget.canChangeRole) {
      _fetchRoles();
      _fetchSubActivities();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final s in _subEdits) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchRoles() async {
    setState(() => _isFetchingRoles = true);
    try {
      final cached = AppCache.instance.get<List<dynamic>>('roles');
      final data = cached ?? await supabase.from('roles').select().order('name');
      if (cached == null) AppCache.instance.set('roles', data, ttl: const Duration(minutes: 30));
      setState(() {
        _roles = List<Map<String, dynamic>>.from(data);
        _isFetchingRoles = false;
      });
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      setState(() => _isFetchingRoles = false);
    }
  }

  Future<void> _fetchSubActivities() async {
    setState(() => _isFetchingSubs = true);
    try {
      final data = await supabase
          .from('activities')
          .select()
          .eq('parent_id', widget.activityId)
          .order('order_index');
      setState(() {
        _subEdits = (data as List).map((s) => _SubActivityEdit(
          id: s['id'] as String,
          name: s['name'] as String,
          scoringDirection: s['scoring_direction'] as String? ?? 'higher_is_better',
        )).toList();
        _isFetchingSubs = false;
      });
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      setState(() => _isFetchingSubs = false);
    }
  }

  Future<void> _removeSub(int index) async {
    final sub = _subEdits[index];
    final name = sub.nameController.text.trim();

    // Only confirm for existing (saved) sub-activities
    if (!sub.isNew) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
          title: const Text('Remove Sub-activity?', style: AppTypography.h3),
          content: Text(
            name.isNotEmpty
                ? 'Are you sure you want to remove "$name"? This cannot be undone after saving.'
                : 'Are you sure you want to remove this sub-activity? This cannot be undone after saving.',
            style: AppTypography.body.copyWith(fontSize: 13, color: kForegroundMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove', style: TextStyle(color: kError, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      _deletedSubIds.add(sub.id!);
    }

    sub.dispose();
    setState(() => _subEdits.removeAt(index));
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
      // Update parent activity
      final updateData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'scoring_direction': _scoringDirection,
      };
      if (widget.canChangeRole) {
        if (_targetRoleId != null) {
          updateData['target_role_id'] = _targetRoleId;
          final role = _roles.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['id'].toString() == _targetRoleId, orElse: () => null);
          if (role != null) updateData['target_role'] = role['name'];
        } else {
          updateData['target_role_id'] = null;
          updateData['target_role'] = null;
        }
      }
      await supabase.from('activities').update(updateData).eq('id', widget.activityId);

      // Save sub-activities
      for (int i = 0; i < _subEdits.length; i++) {
        final sub = _subEdits[i];
        if (sub.nameController.text.trim().isEmpty) continue;
        if (sub.isNew) {
          await supabase.from('activities').insert({
            'session_id': widget.sessionId,
            'parent_id': widget.activityId,
            'name': sub.nameController.text.trim(),
            'is_graded': true,
            'scoring_direction': sub.scoringDirection,
            'order_index': i,
          });
        } else {
          await supabase.from('activities').update({
            'name': sub.nameController.text.trim(),
            'scoring_direction': sub.scoringDirection,
          }).eq('id', sub.id!);
        }
      }

      // Delete removed sub-activities
      for (final id in _deletedSubIds) {
        await supabase.from('activities').delete().eq('id', id);
      }

      AppCache.instance.invalidateWhere((k) => k.startsWith('acts:'));
      AppCache.instance.invalidateWhere((k) => k.startsWith('subs:'));
      AppCache.instance.invalidateWhere((k) => k.startsWith('st:'));

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
                  decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 32, color: Colors.white),
                ),
                const SizedBox(height: 16),
                const Text('Activity Updated!', style: AppTypography.h3, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(
                  '"${_nameController.text.trim()}" has been saved successfully.',
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
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteActivity() async {
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : widget.currentName;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
        title: const Text('Delete Activity?', style: AppTypography.h3),
        content: Text(
          widget.canChangeRole && _subEdits.isNotEmpty
              ? '"$name" has ${_subEdits.length} sub-activit${_subEdits.length == 1 ? 'y' : 'ies'}. Deleting it will permanently remove all of them.'
              : 'This will permanently delete "$name". This cannot be undone.',
          style: AppTypography.body.copyWith(fontSize: 13, color: kForegroundMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: kError, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await supabase.from('activities').delete().eq('parent_id', widget.activityId);
      await supabase.from('activities').delete().eq('id', widget.activityId);

      AppCache.instance.invalidateWhere((k) => k.startsWith('acts:'));
      AppCache.instance.invalidateWhere((k) => k.startsWith('subs:'));
      AppCache.instance.invalidateWhere((k) => k.startsWith('st:'));

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
                  decoration: BoxDecoration(color: kError.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.delete_rounded, size: 32, color: kError),
                ),
                const SizedBox(height: 16),
                const Text('Activity Deleted', style: AppTypography.h3, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(
                  '"$name" has been permanently deleted.',
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
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
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
        elevation: 0,
        toolbarHeight: 44,
        title: const Text('Edit Activity', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: kForegroundMuted, size: 20),
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
                        // Parent activity card
                        AppCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              _field(
                                icon: Icons.edit_rounded,
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
                                    _scoringChip(label: 'Higher ▲', value: 'higher_is_better'),
                                    const SizedBox(width: 5),
                                    _scoringChip(label: 'Lower ▼', value: 'lower_is_better'),
                                  ],
                                ),
                              ),
                              if (widget.canChangeRole) ...[
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
                                                  value: _targetRoleId ?? '__all__',
                                                  isExpanded: true,
                                                  dropdownColor: kSurfaceElevated,
                                                  style: AppTypography.body.copyWith(fontSize: 12, color: kForeground),
                                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kAccent, size: 15),
                                                  isDense: true,
                                                  items: [
                                                    DropdownMenuItem<String>(
                                                      value: '__all__',
                                                      child: Text(
                                                        'All Positions',
                                                        style: AppTypography.body.copyWith(fontSize: 12, color: kForegroundMuted),
                                                      ),
                                                    ),
                                                    ..._roles.map((role) => DropdownMenuItem(
                                                      value: role['id'].toString(),
                                                      child: Text(role['name'].toString()),
                                                    )),
                                                  ],
                                                  onChanged: (v) => setState(() => _targetRoleId = v == '__all__' ? null : v),
                                                ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Sub-activities section (only for parent activities)
                        if (widget.canChangeRole) ...[
                          const SizedBox(height: 12),
                          _buildSubActivitiesSection(),
                        ],

                        const SizedBox(height: 12),
                        AppCard(
                          color: kInfo.withValues(alpha: 0.05),
                          border: Border.all(color: kInfo.withValues(alpha: 0.2)),
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              const Icon(Icons.lightbulb_outline_rounded, color: kInfo, size: 15),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Changing the scoring type will affect how existing scores are ranked.',
                                  style: TextStyle(color: kForegroundMuted, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                const SizedBox(height: 8),
                AppButton(
                  label: 'Delete Activity',
                  onTap: _isLoading ? null : _deleteActivity,
                  icon: Icons.delete_outline_rounded,
                  color: kError.withValues(alpha: 0.1),
                  textColor: kError,
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
      padding: const EdgeInsets.all(kPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree_outlined, size: 13, color: kInfo),
              const SizedBox(width: 6),
              Text('SUB-ACTIVITIES', style: AppTypography.overline.copyWith(color: kInfo, fontSize: 10, letterSpacing: 1.1)),
              const Spacer(),
              if (_isFetchingSubs)
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: kAccent)),
            ],
          ),
          if (!_isFetchingSubs) ...[
            if (_subEdits.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...List.generate(_subEdits.length, (i) => _buildSubRow(i)),
            ],
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _subEdits.add(_SubActivityEdit())),
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
                    Text('Add Sub-activity', style: AppTypography.body.copyWith(color: kAccent, fontWeight: FontWeight.w600, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubRow(int index) {
    final sub = _subEdits[index];
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
                    color: sub.isNew ? kSuccess.withValues(alpha: 0.15) : kAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: AppTypography.caption.copyWith(
                        color: sub.isNew ? kSuccess : kAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: sub.nameController,
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
                  onTap: () async => _removeSub(index),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.close_rounded, size: 15, color: kError.withValues(alpha: 0.6)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 26),
                Text('Score: ', style: AppTypography.caption.copyWith(fontSize: 10)),
                _subScoringChip(sub: sub, label: 'Higher ▲', value: 'higher_is_better'),
                const SizedBox(width: 5),
                _subScoringChip(sub: sub, label: 'Lower ▼', value: 'lower_is_better'),
              ],
            ),
          ],
        ),
      ),
    );
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

  Widget _scoringChip({required String label, required String value}) {
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

  Widget _subScoringChip({required _SubActivityEdit sub, required String label, required String value}) {
    final isSelected = sub.scoringDirection == value;
    return GestureDetector(
      onTap: () => setState(() => sub.scoringDirection = value),
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
}
