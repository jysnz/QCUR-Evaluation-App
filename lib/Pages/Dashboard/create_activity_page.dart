import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class CreateActivityPage extends StatefulWidget {
  final String sessionId;
  final String? parentId;
  final String? parentName;

  const CreateActivityPage({
    super.key,
    required this.sessionId,
    this.parentId,
    this.parentName,
  });

  @override
  State<CreateActivityPage> createState() => _CreateActivityPageState();
}

class _CreateActivityPageState extends State<CreateActivityPage> {
  final _nameController = TextEditingController();
  bool _isGraded = false;
  String _scoringDirection = 'higher_is_better';
  String? _targetRoleId;
  bool _isLoading = false;
  bool _isFetchingRoles = true;
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _roles = [];

  @override
  void initState() {
    super.initState();
    _fetchRoles();
  }

  Future<void> _fetchRoles() async {
    setState(() => _isFetchingRoles = true);
    try {
      final data = await supabase.from('roles').select().order('name');
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

    setState(() => _isLoading = true);
    try {
      // Get current max order_index for this level
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
        'is_graded': _isGraded,
        'scoring_direction': _isGraded ? _scoringDirection : null,
        'order_index': nextIndex,
      };

      if (_targetRoleId != null) {
        insertData['target_role_id'] = _targetRoleId;
        // Also keep target_role string for backward compatibility if needed, 
        // but finding the name from ID
        final role = _roles.firstWhere((r) => r['id'] == _targetRoleId);
        insertData['target_role'] = role['name'];
      }

      await supabase.from('activities').insert(insertData);

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
      appBar: AppBar(
        backgroundColor: kBackground,
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
                              SectionHeader(
                                title: 'Configuration',
                                subtitle: isSubActivity 
                                    ? 'Creating sub-activity for: ${widget.parentName}' 
                                    : 'Defining a primary assessment activity',
                              ),
                              const SizedBox(height: 32),
                              AppTextField(
                                label: 'Activity Name',
                                hint: 'e.g., Technical Assessment, Physical Training...',
                                controller: _nameController,
                              ),
                              const SizedBox(height: 24),
                              if (!isSubActivity) ...[
                                _buildRoleAssignmentDropdown(),
                                const SizedBox(height: 24),
                              ],
                              _buildGradedToggle(),
                              if (_isGraded) ...[
                                const SizedBox(height: 24),
                                _buildScoringDirectionDropdown(),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildProTip(),
                      ],
                    ),
                  ),
                ),
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
        Text('Assign to Position (Optional)', style: AppTypography.label),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: kSurfaceElevated,
            borderRadius: BorderRadius.circular(kRadiusSmall),
            border: Border.all(color: kBorder.withValues(alpha: 0.5)),
          ),
          child: DropdownButtonHideUnderline(
            child: _isFetchingRoles 
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent))),
                )
              : DropdownButton<String?>(
                  value: _targetRoleId,
                  isExpanded: true,
                  hint: const Text('Assign to all members', style: TextStyle(color: kForegroundDisabled, fontSize: 14)),
                  dropdownColor: kSurfaceElevated,
                  style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.bold),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kAccent),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Manual Assignment / All'),
                    ),
                    ..._roles.map((role) => DropdownMenuItem(
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

  Widget _buildGradedToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceElevated,
        borderRadius: BorderRadius.circular(kRadiusSmall),
        border: Border.all(color: kBorder.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Graded Evaluation', style: TextStyle(color: kForeground, fontWeight: FontWeight.bold, fontSize: 14)),
              SizedBox(height: 4),
              Text('Enable to assign scores and metrics', style: TextStyle(color: kForegroundMuted, fontSize: 12)),
            ],
          ),
          const Spacer(),
          Switch.adaptive(
            value: _isGraded,
            onChanged: (v) => setState(() => _isGraded = v),
            activeColor: kAccent,
            activeTrackColor: kAccent.withValues(alpha: 0.2),
          ),
        ],
      ),
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
            borderRadius: BorderRadius.circular(kRadiusSmall),
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

  Widget _buildProTip() {
    return AppCard(
      color: kInfo.withValues(alpha: 0.05),
      border: Border.all(color: kInfo.withValues(alpha: 0.2)),
      padding: const EdgeInsets.all(12),
      child: const Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: kInfo, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sub-activities inherit member assignments from their parent activity.',
              style: TextStyle(color: kForegroundMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
