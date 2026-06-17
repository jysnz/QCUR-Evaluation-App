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
  List<Map<String, dynamic>> _roles = [];
  bool _isLoading = true;

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

      // Fetch ALL roles for assignment
      final rolesData = await supabase.from('roles').select().order('name');

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
        _roles = List<Map<String, dynamic>>.from(rolesData);
        
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

  Future<void> _showRoleAssignmentDialog(Map<String, dynamic> activity) async {
    String? currentRoleId = activity['target_role_id'];

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kSurface,
          surfaceTintColor: Colors.transparent,
          title: Text('ASSIGN TO ROLE', style: AppTypography.h3.copyWith(color: kAccent)),
          content: SizedBox(
            width: double.maxFinite,
            child: _roles.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.psychology_outlined, color: kForegroundDisabled, size: 40),
                        SizedBox(height: 16),
                        Text('NO ROLES DEFINED', style: AppTypography.caption),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Select a role to automatically assign all relevant personnel in this session.',
                        style: TextStyle(color: kForegroundMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _roles.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return RadioListTile<String?>(
                                title: const Text('MANUAL / ALL', style: AppTypography.body),
                                value: null,
                                groupValue: currentRoleId,
                                activeColor: kAccent,
                                onChanged: (v) => setDialogState(() => currentRoleId = v),
                              );
                            }
                            final role = _roles[index - 1];
                            return RadioListTile<String?>(
                              title: Text(role['name'].toString().toUpperCase(), style: AppTypography.body),
                              value: role['id'],
                              groupValue: currentRoleId,
                              activeColor: kAccent,
                              onChanged: (v) => setDialogState(() => currentRoleId = v),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null), // Close without changes
              child: const Text('CANCEL', style: TextStyle(color: kForegroundMuted)),
            ),
            AppButton(
              label: 'APPLY',
              onTap: () => Navigator.of(context).pop(currentRoleId ?? 'manual_cleared'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        final String? newRoleId = result == 'manual_cleared' ? null : result;
        
        // Update the activity record
        final Map<String, dynamic> updateData = {
          'target_role_id': newRoleId,
        };

        if (newRoleId != null) {
          final role = _roles.firstWhere((r) => r['id'] == newRoleId);
          updateData['target_role'] = role['name'];
        } else {
          updateData['target_role'] = null;
        }

        await supabase.from('activities').update(updateData).eq('id', activity['id']);
        
        // If switching to a role, we might want to clear manual assignments?
        // User said " सिंपली, assign that activity to a role itself"
        if (newRoleId != null) {
           await supabase.from('activity_trainees').delete().eq('activity_id', activity['id']);
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
    final isParent = activity['parent_id'] == null;

    return Column(
      children: [
        AppCard(
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
                          isParent ? 'Parent Activity' : 'Sub-activity',
                          style: AppTypography.label.copyWith(
                            color: isParent ? kAccent : kInfo,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          activity['name'].toString(),
                          style: AppTypography.h3,
                        ),
                      ],
                    ),
                  ),
                  if (activity['is_graded'] == true)
                    const AppStatusBadge(label: 'Graded', color: kAccent),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (isParent) ...[
                    _buildActionButton(
                      icon: (activity['display_role'] != null || activity['target_role'] != null) ? Icons.psychology_rounded : Icons.group_add_rounded,
                      label: (activity['display_role'] != null || activity['target_role'] != null)
                        ? (activity['display_role'] ?? activity['target_role']).toString()
                        : '${(activity['trainee_ids'] as List).length} assigned',
                      onTap: () => _showRoleAssignmentDialog(activity),
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.add_circle_outline_rounded,
                      label: 'Sub',
                      onTap: () => _navigateToCreateActivity(
                        parentId: activity['id'],
                        parentName: activity['name'],
                      ),
                    ),
                  ] else ...[
                     const Text('Inherits members from parent', style: TextStyle(color: kForegroundMuted, fontSize: 11, fontStyle: FontStyle.italic)),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: kError, size: 20),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: kSurface,
                          title: const Text('Delete activity?', style: AppTypography.h3),
                          content: const Text('This will remove the activity and all its sub-activities.', style: AppTypography.body),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: kError))),
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
              if (activity['is_graded'] == true) ...[
                const SizedBox(height: 12),
                _buildActionButton(
                  icon: Icons.assignment_turned_in_rounded,
                  label: 'Assess Members',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ScoreTraineesPage(
                        sessionId: widget.sessionId,
                        activityId: activity['id'],
                        activityName: activity['name'],
                        roleId: activity['target_role_id'],
                        roleName: activity['display_role'] ?? activity['target_role'],
                      ),
                    ),
                  ),
                ),
              ],
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
      borderRadius: BorderRadius.circular(kRadiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: kSurfaceElevated.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(kRadiusSmall),
          border: Border.all(color: kBorder.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: kAccent),
            const SizedBox(width: 6),
            Text(label, style: AppTypography.label.copyWith(color: kForeground, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}


