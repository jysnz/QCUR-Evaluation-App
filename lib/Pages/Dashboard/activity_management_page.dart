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
            TechnicalButton(
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
                      icon: (activity['display_role'] != null || activity['target_role'] != null) ? Icons.psychology : Icons.group_add_outlined,
                      label: (activity['display_role'] != null || activity['target_role'] != null)
                        ? (activity['display_role'] ?? activity['target_role']).toString().toUpperCase()
                        : '${(activity['trainee_ids'] as List).length} ASSIGNED',
                      onTap: () => _showRoleAssignmentDialog(activity),
                    ),
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


