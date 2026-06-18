import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:qcur_evaluation/Pages/Dashboard/create_activity_page.dart';
import 'package:qcur_evaluation/Pages/Dashboard/score_trainees_page.dart';

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
      // Fetch activities with role info
      final activitiesData = await supabase
          .from('activities')
          .select('*, roles(name)')
          .eq('session_id', widget.sessionId)
          .order('order_index');

      // Fetch ONLY trainees assigned to this session with their structured roles
      final sessionMembersData = await supabase
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

      final traineesList = sessionMembersData.map((m) => m['trainees'] as Map<String, dynamic>).toList();

      // Fetch manual activity assignments
      final assignmentsData = await supabase
          .from('activity_trainees')
          .select('activity_id, trainee_id');

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
            // Manual assignment
            activity['trainee_ids'] = assignmentsData
                .where((a) => a['activity_id'] == activity['id'])
                .map((a) => a['trainee_id'])
                .toList();
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

  void _navigateToCreateActivity({String? parentId, String? parentName}) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreateActivityPage(
          sessionId: widget.sessionId,
          parentId: parentId,
          parentName: parentName,
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
                          label: 'Add Root Activity',
                          icon: Icons.add_circle_outline,
                          onTap: () => _navigateToCreateActivity(),
                        ),
                      ),
                    ],
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

    return Column(
      children: [
        GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ScoreTraineesPage(
                  sessionId: widget.sessionId,
                  activityId: activity['id'],
                  activityName: activity['name'],
                  sessionName: widget.sessionName,
                  roleId: activity['target_role_id'],
                  roleName: roleName,
                ),
              ),
            ).then((_) => _fetchData());
          },
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        activity['name'].toString(),
                        style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (activity['is_graded'] == true)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: kAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('GRADED', style: TextStyle(color: kAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.psychology_outlined, size: 12, color: roleName != null ? kAccent : kForegroundDisabled),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        roleName ?? 'No role assigned',
                        style: AppTypography.caption.copyWith(fontSize: 11, color: roleName != null ? kAccent : kForegroundDisabled),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      'See more',
                      style: TextStyle(color: kAccent, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 14, color: kAccent),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (subActivities.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: GestureDetector(
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
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: kBorder.withValues(alpha: 0.3))),
                ),
                child: Row(
                  children: [
                    Icon(
                      subExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: kForegroundMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${subActivities.length} sub-activities',
                      style: AppTypography.caption.copyWith(fontSize: 11, color: kForegroundMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (subExpanded)
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


