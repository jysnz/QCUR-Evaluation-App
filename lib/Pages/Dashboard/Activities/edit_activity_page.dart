import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

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
  List<Map<String, dynamic>> _roles = [];
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
    _scoringDirection = widget.currentScoringDirection;
    _targetRoleId = widget.currentRoleId;
    if (widget.canChangeRole) _fetchRoles();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _fetchRoles() async {
    setState(() => _isFetchingRoles = true);
    try {
      final cached = AppCache.instance.get<List<dynamic>>('roles');
      final data = cached ?? await supabase.from('roles').select().order('name');
      if (cached == null) {
        AppCache.instance.set('roles', data, ttl: const Duration(minutes: 30));
      }
      setState(() {
        _roles = List<Map<String, dynamic>>.from(data);
        _isFetchingRoles = false;
      });
    } catch (e) {
      setState(() => _isFetchingRoles = false);
    }
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
      final updateData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'scoring_direction': _scoringDirection,
      };

      if (widget.canChangeRole && _targetRoleId != null) {
        updateData['target_role_id'] = _targetRoleId;
        final role = _roles.cast<Map<String, dynamic>?>().firstWhere(
          (r) => r?['id'].toString() == _targetRoleId,
          orElse: () => null,
        );
        if (role != null) updateData['target_role'] = role['name'];
      }

      await supabase.from('activities').update(updateData).eq('id', widget.activityId);

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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Edit Activity', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
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
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              _field(
                                icon: Icons.edit_rounded,
                                hint: 'Activity name...',
                                controller: _nameController,
                              ),
                              const Divider(height: 1, color: kBorder, indent: 44),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                child: Row(
                                  children: [
                                    const Icon(Icons.trending_up_rounded, size: 17, color: kAccent),
                                    const SizedBox(width: 12),
                                    Text('Scoring', style: AppTypography.caption.copyWith(color: kForegroundMuted, fontSize: 12)),
                                    const Spacer(),
                                    _scoringChip(label: 'Higher ▲', value: 'higher_is_better'),
                                    const SizedBox(width: 6),
                                    _scoringChip(label: 'Lower ▼', value: 'lower_is_better'),
                                  ],
                                ),
                              ),
                              if (widget.canChangeRole) ...[
                                const Divider(height: 1, color: kBorder, indent: 44),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.psychology_outlined, size: 17, color: kAccent),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: DropdownButtonHideUnderline(
                                          child: _isFetchingRoles
                                              ? const Padding(
                                                  padding: EdgeInsets.symmetric(vertical: 10),
                                                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)),
                                                )
                                              : DropdownButton<String>(
                                                  value: _targetRoleId,
                                                  isExpanded: true,
                                                  hint: Text('Select a position', style: AppTypography.label.copyWith(color: kForegroundDisabled, fontSize: 13)),
                                                  dropdownColor: kSurfaceElevated,
                                                  style: AppTypography.body.copyWith(fontSize: 13, color: kForeground),
                                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kAccent, size: 16),
                                                  isDense: true,
                                                  items: _roles.map((role) => DropdownMenuItem(
                                                    value: role['id'].toString(),
                                                    child: Text(role['name'].toString()),
                                                  )).toList(),
                                                  onChanged: (v) => setState(() => _targetRoleId = v),
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
                        const SizedBox(height: 16),
                        AppCard(
                          color: kInfo.withValues(alpha: 0.05),
                          border: Border.all(color: kInfo.withValues(alpha: 0.2)),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.lightbulb_outline_rounded, color: kInfo, size: 18),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Changing the scoring type will affect how existing scores are ranked.',
                                  style: TextStyle(color: kForegroundMuted, fontSize: 12),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({required IconData icon, required String hint, required TextEditingController controller}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: kAccent),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              style: AppTypography.body.copyWith(fontSize: 13),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppTypography.label.copyWith(color: kForegroundDisabled, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
