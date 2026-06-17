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
  String? _targetRole;
  bool _isLoading = false;
  final supabase = Supabase.instance.client;

  final List<String> _roles = [
    'Programmer',
    'Builder',
    'Designer',
    'Notebook Manager',
    'Driver',
    'Coach Driver'
  ];

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

      await supabase.from('activities').insert({
        'session_id': widget.sessionId,
        'parent_id': widget.parentId,
        'name': _nameController.text.trim(),
        'is_graded': _isGraded,
        'scoring_direction': _isGraded ? _scoringDirection : null,
        'target_role': _targetRole,
        'order_index': nextIndex,
      });

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
          isSubActivity ? 'ADD SUB-ACTIVITY' : 'NEW ACTIVITY',
          style: AppTypography.h3.copyWith(letterSpacing: 2),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: kForegroundMuted),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          const TechnicalGridBackground(),
          SafeArea(
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
                          TechnicalCard(
                            padding: const EdgeInsets.all(kPaddingLarge),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SectionHeader(
                                  title: 'Activity Configuration',
                                  subtitle: isSubActivity 
                                      ? 'Creating sub-activity for: ${widget.parentName}' 
                                      : 'Defining a primary evaluation activity',
                                ),
                                const SizedBox(height: 32),
                                AppTextField(
                                  label: 'Activity Name',
                                  hint: 'e.g., Tactical Maneuvers, Physical Fitness...',
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
                  TechnicalButton(
                    label: isSubActivity ? 'Create Sub-Activity' : 'Create Activity',
                    onTap: _saveActivity,
                    isLoading: _isLoading,
                    icon: Icons.add_task,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleAssignmentDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ASSIGN TO ROLE (OPTIONAL)', style: AppTypography.overline),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: kSurfaceElevated,
            borderRadius: BorderRadius.circular(kRadiusSmall),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _targetRole,
              isExpanded: true,
              hint: const Text('ASSIGN TO ALL PERSONNEL', style: TextStyle(color: kForegroundDisabled, fontSize: 14)),
              dropdownColor: kSurfaceElevated,
              style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.bold),
              icon: const Icon(Icons.keyboard_arrow_down, color: kAccent),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('MANUAL ASSIGNMENT / ALL'),
                ),
                ..._roles.map((role) => DropdownMenuItem(
                  value: role,
                  child: Text(role.toUpperCase()),
                )),
              ],
              onChanged: (v) => setState(() => _targetRole = v),
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
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('GRADED EVALUATION', style: TextStyle(color: kForeground, fontWeight: FontWeight.bold, fontSize: 14)),
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
        const Text('SCORING DIRECTION', style: AppTypography.overline),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: kSurfaceElevated,
            borderRadius: BorderRadius.circular(kRadiusSmall),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _scoringDirection,
              isExpanded: true,
              dropdownColor: kSurfaceElevated,
              style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.bold),
              icon: const Icon(Icons.keyboard_arrow_down, color: kAccent),
              items: const [
                DropdownMenuItem(
                  value: 'higher_is_better',
                  child: Text('HIGHER IS BETTER (%)'),
                ),
                DropdownMenuItem(
                  value: 'lower_is_better',
                  child: Text('LOWER IS BETTER (TIME/ERRORS)'),
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
    return TechnicalCard(
      color: kInfo.withValues(alpha: 0.05),
      border: Border.all(color: kInfo.withValues(alpha: 0.2)),
      padding: const EdgeInsets.all(12),
      child: const Row(
        children: [
          Icon(Icons.lightbulb_outline, color: kInfo, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sub-activities inherit the trainee assignments from their parent activity.',
              style: TextStyle(color: kForegroundMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
