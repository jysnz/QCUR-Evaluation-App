import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Activities/create_activity_page.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Activities/edit_activity_page.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Scoring/score_trainees_page.dart';

class ActivityManagementView extends StatefulWidget {
  final String sessionId;
  final String sessionName;

  const ActivityManagementView({
    super.key,
    required this.sessionId,
    required this.sessionName,
  });

  @override
  State<ActivityManagementView> createState() => _ActivityManagementViewState();
}

class _ActivityManagementViewState extends State<ActivityManagementView> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _activities = [];
  List<Map<String, dynamic>> _sessionTrainees = [];

  bool _isLoading = true;
  final Set<String> _subExpandedIds = {};

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final cache = AppCache.instance;
      final actsKey = 'acts:${widget.sessionId}';
      final stKey = 'st_full:${widget.sessionId}';
      const assignKey = 'act_assignments';

      // Fetch activities with role info
      final cachedActs = cache.get<List<dynamic>>(actsKey);
      final activitiesData = cachedActs ??
          await supabase
              .from('activities')
              .select('*, roles(name)')
              .eq('session_id', widget.sessionId)
              .order('order_index');
      if (cachedActs == null) cache.set(actsKey, activitiesData);

      // Fetch ONLY trainees assigned to this session with their structured roles
      final cachedSt = cache.get<List<dynamic>>(stKey);
      final sessionMembersData = cachedSt ??
          await supabase
              .from('session_trainees')
              .select('''
                trainee_id,
                trainees!inner (
                  *,
                  trainee_roles (
                    role_id
                  )
                )
              ''')
              .eq('session_id', widget.sessionId);
      if (cachedSt == null) {
        cache.set(stKey, sessionMembersData, ttl: const Duration(minutes: 3));
      }

      final traineesList = sessionMembersData
          .map((m) => m['trainees'] as Map<String, dynamic>)
          .toList();

      // Fetch manual activity assignments
      final cachedAssign = cache.get<List<dynamic>>(assignKey);
      final assignmentsData = cachedAssign ??
          await supabase.from('activity_trainees').select('activity_id, trainee_id');
      if (cachedAssign == null) cache.set(assignKey, assignmentsData);

      setState(() {
        _activities = List<Map<String, dynamic>>.from(activitiesData);
        _sessionTrainees = traineesList;
        
        // Map assignments to activities
        for (var activity in _activities) {
          if (activity['target_role_id'] != null) {
            // Role-based assignment: find trainees in this session with the matching role_id
            final targetRoleId = activity['target_role_id'];
            activity['trainee_ids'] = _sessionTrainees
                .where((t) {
                  final List<dynamic> traineeRoles = t['trainee_roles'] ?? [];
                  return traineeRoles.any((tr) => tr['role_id'] == targetRoleId);
                })
                .map((t) => t['id'])
                .toList();
            
            // For UI display, ensure role name is available
            if (activity['roles'] != null) {
              activity['display_role'] = activity['roles']['name'];
            }
          } else {
            // All Positions: include all session trainees
            activity['trainee_ids'] = _sessionTrainees.map((t) => t['id']).toList();
          }
        }
        
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching data: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _editActivity(Map<String, dynamic> activity) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditActivityPage(
          activityId: activity['id'] as String,
          sessionId: widget.sessionId,
          currentName: activity['name'].toString(),
          currentScoringDirection: activity['scoring_direction']?.toString() ?? 'higher_is_better',
          currentRoleId: activity['target_role_id'] as String?,
          canChangeRole: activity['parent_id'] == null,
        ),
      ),
    );
    if (result == true) _fetchData();
  }

  Future<void> _deleteActivity(Map<String, dynamic> activity) async {
    final hasSubActivities = _activities.any((a) => a['parent_id'] == activity['id']);
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Delete Activity?', style: AppTypography.h3),
        content: Text(
          hasSubActivities
              ? '"${activity['name']}" has sub-activities. Deleting it will permanently remove all of them.'
              : 'This will permanently delete "${activity['name']}".',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: kError, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final activityName = activity['name'] as String;
        await supabase.from('activities').delete().eq('parent_id', activity['id']);
        await supabase.from('activities').delete().eq('id', activity['id']);

        AppCache.instance.invalidateWhere((k) => k.startsWith('acts:'));
        AppCache.instance.invalidateWhere((k) => k.startsWith('subs:'));
        _fetchData();

        if (mounted) {
          await showDialog(
            context: context,
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
                    '"$activityName" has been permanently deleted.',
                    style: AppTypography.caption.copyWith(color: kForegroundMuted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  AppButton(
                    label: 'Done',
                    onTap: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
          );
        }
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  void _navigateToCreateActivity({String? parentId, String? parentName, String? inheritedRoleId}) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreateActivityPage(
          sessionId: widget.sessionId,
          parentId: parentId,
          parentName: parentName,
          inheritedRoleId: inheritedRoleId,
        ),
      ),
    );

    if (result == true) {
      _fetchData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentActivities = _activities.where((a) => a['parent_id'] == null).toList();

    return Scaffold(
      backgroundColor: Colors.transparent, // Inherit from SessionDetailsPage
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ACTIVITY MANAGER', style: AppTypography.overline.copyWith(color: kForegroundMuted)),
            Text(widget.sessionName.toUpperCase(), style: AppTypography.h3),
          ],
        ),
      ),
      body: Stack(
        children: [
          const TechnicalGridBackground(),
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: kAccent))
              : SafeArea(
                  child: ResponsiveContainer(
                    maxWidth: kMaxWidthContent,
                    child: Column(
                    children: [
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _fetchData,
                          color: kAccent,
                          backgroundColor: kSurfaceElevated,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(kPadding),
                            itemCount: parentActivities.length,
                            itemBuilder: (context, index) {
                              return _buildActivityNode(parentActivities[index]);
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(kPadding),
                        child: AppButton(
                          label: 'Add Activity',
                          icon: Icons.add_circle_outline,
                          onTap: () => _navigateToCreateActivity(),
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildActivityNode(Map<String, dynamic> activity) {
    final subActivities = _activities.where((a) => a['parent_id'] == activity['id']).toList();
    final subExpanded = _subExpandedIds.contains(activity['id']);
    final roleName = activity['display_role'] ?? activity['target_role'];
    final isAllPositions = activity['target_role_id'] == null;
    final hasSubActivities = subActivities.isNotEmpty;
    final isParent = activity['parent_id'] == null;

    return Column(
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          color: hasSubActivities ? kSurfaceElevated.withValues(alpha: 0.6) : kSurface,
          child: InkWell(
              onTap: () {
                final isSub = activity['parent_id'] != null;
                if (isSub) {
                  final parentId = activity['parent_id'] as String;
                  final parent = _activities.firstWhere((a) => a['id'] == parentId);
                  final parentRoleName = (parent['display_role'] ?? parent['target_role']) as String?;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ScoreTraineesPage(
                        sessionId: widget.sessionId,
                        activityId: parentId,
                        activityName: parent['name'].toString(),
                        sessionName: widget.sessionName,
                        roleId: parent['target_role_id'] as String?,
                        roleName: parentRoleName ?? 'All Positions',
                        highlightedSubId: activity['id'] as String,
                      ),
                    ),
                  ).then((_) => _fetchData());
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ScoreTraineesPage(
                        sessionId: widget.sessionId,
                        activityId: activity['id'],
                        activityName: activity['name'],
                        sessionName: widget.sessionName,
                        roleId: activity['target_role_id'],
                        roleName: roleName ?? 'All Positions',
                      ),
                    ),
                  ).then((_) => _fetchData());
                }
              },
              borderRadius: BorderRadius.circular(kRadius),
              splashColor: kAccent.withValues(alpha: 0.08),
              highlightColor: kAccent.withValues(alpha: 0.04),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isParent) ...[
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: kAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.folder_outlined, size: 13, color: kAccent),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            activity['name'].toString(),
                            style: AppTypography.body.copyWith(
                              fontWeight: hasSubActivities ? FontWeight.w700 : FontWeight.w600,
                              fontSize: 13,
                              color: kForeground,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          color: kSurfaceElevated,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSmall)),
                          onSelected: (value) {
                            if (value == 'edit') _editActivity(activity);
                            if (value == 'delete') _deleteActivity(activity);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'edit',
                              height: 40,
                              child: Row(children: [
                                const Icon(Icons.edit_outlined, size: 15, color: kForeground),
                                const SizedBox(width: 10),
                                Text('Edit', style: AppTypography.body.copyWith(fontSize: 13)),
                              ]),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              height: 40,
                              child: Row(children: [
                                const Icon(Icons.delete_outline_rounded, size: 15, color: kError),
                                const SizedBox(width: 10),
                                Text('Delete', style: AppTypography.body.copyWith(fontSize: 13, color: kError)),
                              ]),
                            ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.more_vert_rounded, size: 15, color: kForegroundDisabled),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          isAllPositions ? Icons.groups_rounded : Icons.psychology_outlined,
                          size: hasSubActivities ? 11 : 12,
                          color: kAccent,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            roleName ?? 'All Positions',
                            style: AppTypography.caption.copyWith(
                              fontSize: hasSubActivities ? 10 : 11,
                              color: kAccent,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text('See more', style: TextStyle(color: kAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 2),
                        const Icon(Icons.chevron_right_rounded, size: 14, color: kAccent),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ),
        if (isParent) ...[
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (subExpanded) {
                    _subExpandedIds.remove(activity['id']);
                  } else {
                    _subExpandedIds.add(activity['id']);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: kBorder.withValues(alpha: 0.3))),
                ),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: subExpanded ? 0.0 : -0.25,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.expand_more, size: 16, color: kForegroundMuted),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      subActivities.isEmpty
                          ? 'No sub-activities'
                          : '${subActivities.length} sub-activit${subActivities.length == 1 ? 'y' : 'ies'}',
                      style: AppTypography.caption.copyWith(fontSize: 11, color: kForegroundMuted),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _navigateToCreateActivity(
                        parentId: activity['id'],
                        parentName: activity['name'],
                        inheritedRoleId: activity['target_role_id'] as String?,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: kAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(kRadiusSmall),
                          border: Border.all(color: kAccent.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_rounded, size: 12, color: kAccent),
                            const SizedBox(width: 4),
                            Text('Add Sub-activity', style: TextStyle(color: kAccent, fontSize: 10, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (subExpanded && subActivities.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Column(
                children: subActivities.map((s) => _buildActivityNode(s)).toList(),
              ),
            ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

}


