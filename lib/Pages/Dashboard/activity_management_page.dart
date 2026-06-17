import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class ActivityManagementPage extends StatefulWidget {
  final String sessionId;
  final String sessionName;

  const ActivityManagementPage({
    super.key,
    required this.sessionId,
    required this.sessionName,
  });

  @override
  State<ActivityManagementPage> createState() => _ActivityManagementPageState();
}

class _ActivityManagementPageState extends State<ActivityManagementPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _activities = [];
  List<Map<String, dynamic>> _trainees = [];
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

      // Fetch trainees (available to assign)
      final traineesData = await supabase
          .from('trainees')
          .select()
          .order('full_name');

      // Fetch assignments
      final assignmentsData = await supabase
          .from('activity_trainees')
          .select('activity_id, trainee_id');

      setState(() {
        _activities = List<Map<String, dynamic>>.from(activitiesData);
        _trainees = List<Map<String, dynamic>>.from(traineesData);
        
        // Map assignments to activities
        for (var activity in _activities) {
          activity['trainee_ids'] = assignmentsData
              .where((a) => a['activity_id'] == activity['id'])
              .map((a) => a['trainee_id'])
              .toList();
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

  Future<void> _addActivity({String? parentId}) async {
    final nameController = TextEditingController();
    bool isGraded = false;
    String scoringDirection = 'higher_is_better';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kSurface,
          title: Text(parentId == null ? 'ADD ACTIVITY' : 'ADD SUB-ACTIVITY', 
              style: const TextStyle(color: kAccent, fontWeight: FontWeight.w900, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDialogLabel('NAME'),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: kForeground),
                  decoration: _dialogInputDecoration('Activity name...'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('GRADED', style: TextStyle(color: kForegroundMuted, fontWeight: FontWeight.bold, fontSize: 12)),
                    const Spacer(),
                    Switch(
                      value: isGraded,
                      onChanged: (v) => setDialogState(() => isGraded = v),
                      activeThumbColor: kAccent,
                    ),
                  ],
                ),
                if (isGraded) ...[
                  const SizedBox(height: 16),
                  _buildDialogLabel('SCORING DIRECTION'),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<String>(
                      value: scoringDirection,
                      isExpanded: true,
                      underline: const SizedBox(),
                      dropdownColor: kSurface,
                      items: const [
                        DropdownMenuItem(value: 'higher_is_better', child: Text('HIGHER IS BETTER (%)')),
                        DropdownMenuItem(value: 'lower_is_better', child: Text('LOWER IS BETTER (TIME/ERRORS)')),
                      ],
                      onChanged: (v) => setDialogState(() => scoringDirection = v!),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('CANCEL', style: TextStyle(color: kForegroundMuted)),
            ),
            TechnicalButton(
              label: 'ADD',
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      try {
        await supabase.from('activities').insert({
          'session_id': widget.sessionId,
          'parent_id': parentId,
          'name': nameController.text.trim(),
          'is_graded': isGraded,
          'scoring_direction': isGraded ? scoringDirection : null,
          'order_index': _activities.where((a) => a['parent_id'] == parentId).length,
        });
        _fetchData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _manageTrainees(Map<String, dynamic> activity) async {
    final selectedIds = List<String>.from(activity['trainee_ids'] ?? []);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kSurface,
          title: const Text('ASSIGN TRAINEES', 
              style: TextStyle(color: kAccent, fontWeight: FontWeight.w900, fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: _trainees.isEmpty
                ? const Center(child: Text('No trainees available. Add them in settings.', style: TextStyle(color: kForegroundMuted)))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _trainees.length,
                    itemBuilder: (context, index) {
                      final trainee = _trainees[index];
                      final isSelected = selectedIds.contains(trainee['id']);
                      return CheckboxListTile(
                        title: Text(trainee['full_name'], style: const TextStyle(color: kForeground)),
                        subtitle: trainee['email'] != null ? Text(trainee['email'], style: const TextStyle(color: kForegroundMuted, fontSize: 12)) : null,
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
      appBar: AppBar(
        backgroundColor: kBackground,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MANAGE SESSION', style: TextStyle(color: kAccent.withValues(alpha: 0.7), fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900)),
            Text(widget.sessionName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
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
                          icon: Icons.add_task,
                          onTap: () => _addActivity(),
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
                          style: TextStyle(
                            color: isParent ? kAccent : Colors.blue,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          activity['name'].toString().toUpperCase(),
                          style: const TextStyle(color: kForeground, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  if (activity['is_graded'] == true)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: kAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: kAccent.withValues(alpha: 0.3)),
                      ),
                      child: const Text('GRADED', style: TextStyle(color: kAccent, fontSize: 8, fontWeight: FontWeight.w900)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (isParent) ...[
                    _buildActionButton(
                      icon: Icons.group_add_outlined,
                      label: '${(activity['trainee_ids'] as List).length} TRAINEES',
                      onTap: () => _manageTrainees(activity),
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.add_circle_outline,
                      label: 'SUB',
                      onTap: () => _addActivity(parentId: activity['id']),
                    ),
                  ] else ...[
                     const Text('INHERITS TRAINEES FROM PARENT', style: TextStyle(color: kForegroundMuted, fontSize: 10, fontStyle: FontStyle.italic)),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                    onPressed: () async {
                      await supabase.from('activities').delete().eq('id', activity['id']);
                      _fetchData();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        if (subActivities.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 24.0, top: 8, bottom: 8),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: kAccent),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: kForeground, fontSize: 10, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, left: 2),
      child: Text(
        label,
        style: const TextStyle(color: kForegroundMuted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
      ),
    );
  }

  InputDecoration _dialogInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kAccent, width: 1)),
    );
  }
}
