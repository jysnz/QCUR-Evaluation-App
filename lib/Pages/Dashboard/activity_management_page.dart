import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:qcur_evaluation/Pages/Dashboard/create_activity_page.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // Fetch activities
      final activitiesData = await supabase
          .from('activities')
          .select()
          .eq('session_id', widget.sessionId)
          .order('order_index');

      // Fetch ONLY trainees assigned to this session
      final sessionMembersData = await supabase
          .from('session_trainees')
          .select('trainee_id, trainees!inner(*)')
          .eq('session_id', widget.sessionId);

      final traineesList = sessionMembersData.map((m) => m['trainees'] as Map<String, dynamic>).toList();

      // Fetch activity assignments
      final assignmentsData = await supabase
          .from('activity_trainees')
          .select('activity_id, trainee_id');

      setState(() {
        _activities = List<Map<String, dynamic>>.from(activitiesData);
        _sessionTrainees = traineesList;
        
        // Map assignments to activities
        for (var activity in _activities) {
          if (activity['target_role'] != null) {
            // Role-based assignment: find trainees in this session with the matching role
            activity['trainee_ids'] = _sessionTrainees
                .where((t) {
                  final List<dynamic> traineeRoles = t['role'] ?? [];
                  return traineeRoles.contains(activity['target_role']);
                })
                .map((t) => t['id'])
                .toList();
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

  Future<void> _manageTrainees(Map<String, dynamic> activity) async {
    final selectedIds = List<String>.from(activity['trainee_ids'] ?? []);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kSurface,
          surfaceTintColor: Colors.transparent,
          title: Text('ASSIGN PERSONNEL', style: AppTypography.h3.copyWith(color: kAccent)),
          content: SizedBox(
            width: double.maxFinite,
            child: _sessionTrainees.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline, color: kForegroundDisabled, size: 40),
                        SizedBox(height: 16),
                        Text('NO SESSION MEMBERS', style: AppTypography.caption),
                        Text('Add members in the Members tab first.', 
                          style: TextStyle(color: kForegroundDisabled, fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _sessionTrainees.length,
                    itemBuilder: (context, index) {
                      final trainee = _sessionTrainees[index];
                      final isSelected = selectedIds.contains(trainee['id']);
                      return CheckboxListTile(
                        title: Text(trainee['full_name'].toString().toUpperCase(), style: AppTypography.body),
                        subtitle: trainee['email'] != null ? Text(trainee['email'], style: AppTypography.caption) : null,
                        value: isSelected,
                        activeColor: kAccent,
                        checkColor: Colors.black,
                        onChanged: (v) {
                          setDialogState(() {
                            if (v == true) {
                              selectedIds.add(trainee['id']);
                            } else {
                              selectedIds.remove(trainee['id']);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('CANCEL', style: TextStyle(color: kForegroundMuted)),
            ),
            TechnicalButton(
              label: 'SAVE',
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      try {
        // Delete existing assignments for this activity
        await supabase.from('activity_trainees').delete().eq('activity_id', activity['id']);
        
        // Insert new ones
        if (selectedIds.isNotEmpty) {
          await supabase.from('activity_trainees').insert(
            selectedIds.map((tid) => {'activity_id': activity['id'], 'trainee_id': tid}).toList(),
          );
        }
        _fetchData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
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
                        child: ListView.builder(
                          padding: const EdgeInsets.all(kPadding),
                          itemCount: parentActivities.length,
                          itemBuilder: (context, index) {
                            return _buildActivityNode(parentActivities[index]);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(kPadding),
                        child: TechnicalButton(
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
    final isParent = activity['parent_id'] == null;

    return Column(
      children: [
        TechnicalCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isParent ? 'PARENT ACTIVITY' : 'SUB-ACTIVITY',
                          style: AppTypography.overline.copyWith(
                            color: isParent ? kAccent : kInfo,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          activity['name'].toString().toUpperCase(),
                          style: AppTypography.h3,
                        ),
                      ],
                    ),
                  ),
                  if (activity['is_graded'] == true)
                    const AppStatusBadge(label: 'GRADED', color: kAccent),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (isParent) ...[
                    _buildActionButton(
                      icon: activity['target_role'] != null ? Icons.psychology : Icons.group_add_outlined,
                      label: activity['target_role'] != null 
                        ? '${activity['target_role'].toString().toUpperCase()}'
                        : '${(activity['trainee_ids'] as List).length} ASSIGNED',
                      onTap: activity['target_role'] != null 
                        ? () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Auto-assigned to all ${activity['target_role']}s')),
                            );
                          }
                        : () => _manageTrainees(activity),
                    ),
                    if (activity['target_role'] != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: kAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: kAccent.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          '${(activity['trainee_ids'] as List).length} ACTIVE',
                          style: AppTypography.overline.copyWith(color: kAccent, fontSize: 8),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.add_circle_outline,
                      label: 'SUB',
                      onTap: () => _navigateToCreateActivity(
                        parentId: activity['id'],
                        parentName: activity['name'],
                      ),
                    ),
                  ] else ...[
                     const Text('GETS TRAINEES FROM PARENT', style: TextStyle(color: kForegroundMuted, fontSize: 10, fontStyle: FontStyle.italic)),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: kError, size: 20),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: kSurface,
                          title: const Text('DELETE ACTIVITY?', style: AppTypography.h3),
                          content: const Text('This will remove the activity and all its sub-activities.', style: AppTypography.body),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('DELETE', style: TextStyle(color: kError))),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await supabase.from('activities').delete().eq('id', activity['id']);
                        _fetchData();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        if (subActivities.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 24.0, top: 12, bottom: 4),
            child: Column(
              children: subActivities.map((s) => _buildActivityNode(s)).toList(),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: kSurfaceElevated,
          borderRadius: BorderRadius.circular(kRadiusSmall),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: kAccent),
            const SizedBox(width: 6),
            Text(label, style: AppTypography.overline.copyWith(color: kForeground)),
          ],
        ),
      ),
    );
  }
}


