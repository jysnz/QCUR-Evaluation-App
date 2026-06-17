import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class SessionMembersTab extends StatefulWidget {
  final String sessionId;

  const SessionMembersTab({
    super.key,
    required this.sessionId,
  });

  @override
  State<SessionMembersTab> createState() => _SessionMembersTabState();
}

class _SessionMembersTabState extends State<SessionMembersTab> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _allTrainees = [];
  List<String> _selectedTraineeIds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // Fetch all trainees
      final allTraineesData = await supabase
          .from('trainees')
          .select()
          .order('full_name');

      // Fetch session members
      final sessionMembersData = await supabase
          .from('session_trainees')
          .select('trainee_id')
          .eq('session_id', widget.sessionId);

      setState(() {
        _allTrainees = List<Map<String, dynamic>>.from(allTraineesData);
        _selectedTraineeIds = sessionMembersData
            .map((m) => m['trainee_id'].toString())
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleMember(String traineeId, bool isSelected) async {
    try {
      if (isSelected) {
        await supabase.from('session_trainees').insert({
          'session_id': widget.sessionId,
          'trainee_id': traineeId,
        });
        setState(() => _selectedTraineeIds.add(traineeId));
      } else {
        await supabase.from('session_trainees')
            .delete()
            .eq('session_id', widget.sessionId)
            .eq('trainee_id', traineeId);
        setState(() => _selectedTraineeIds.remove(traineeId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('SESSION MEMBERS', style: AppTypography.h3.copyWith(letterSpacing: 2)),
        actions: [
          IconButton(
            onPressed: _addTrainee,
            icon: const Icon(Icons.person_add_alt_1, color: kAccent),
            tooltip: 'Add New Personnel',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          const TechnicalGridBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(kPadding),
              child: Column(
                children: [
                  const SectionHeader(
                    title: 'Personnel Assignment',
                    subtitle: 'Assign trainees participating in this session',
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: TechnicalCard(
                      padding: EdgeInsets.zero,
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator(color: kAccent))
                          : _allTrainees.isEmpty
                              ? _buildEmptyState()
                              : _buildTraineesList(),
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

  Future<void> _addTrainee() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    List<String> selectedRoles = [];
    final List<String> roles = [
      'Programmer',
      'Builder',
      'Designer',
      'Notebook Manager',
      'Driver',
      'Coach Driver'
    ];

    bool shouldAddAnother = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kSurface,
          surfaceTintColor: Colors.transparent,
          title: Text('NEW PERSONNEL', style: AppTypography.h3.copyWith(color: kAccent)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'FULL NAME',
                  controller: nameController,
                  hint: 'Enter trainee name',
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'EMAIL ADDRESS',
                  controller: emailController,
                  hint: 'Optional contact info',
                ),
                const SizedBox(height: 16),
                Text('ASSIGNED ROLES', style: AppTypography.overline),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kSurfaceElevated,
                    borderRadius: BorderRadius.circular(kRadiusSmall),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: roles.map((role) {
                      final isChecked = selectedRoles.contains(role);
                      return CheckboxListTile(
                        title: Text(role.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        value: isChecked,
                        dense: true,
                        activeColor: kAccent,
                        checkColor: Colors.black,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) {
                          setDialogState(() {
                            if (v == true) {
                              selectedRoles.add(role);
                            } else {
                              selectedRoles.remove(role);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('CANCEL', style: AppTypography.caption.copyWith(color: kForegroundMuted)),
            ),
            TextButton(
              onPressed: () {
                shouldAddAnother = true;
                Navigator.of(context).pop(true);
              },
              child: Text('ADD ANOTHER', style: AppTypography.caption.copyWith(color: kAccent)),
            ),
            TechnicalButton(
              label: 'ADD',
              onTap: () {
                shouldAddAnother = false;
                Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      try {
        final traineeData = await supabase.from('trainees').insert({
          'full_name': nameController.text.trim(),
          'email': emailController.text.trim().isEmpty ? null : emailController.text.trim(),
          'role': selectedRoles,
          'creator_id': supabase.auth.currentUser!.id,
        }).select().single();

        // Automatically assign to session
        await supabase.from('session_trainees').insert({
          'session_id': widget.sessionId,
          'trainee_id': traineeData['id'],
        });

        _fetchData();

        if (shouldAddAnother) {
          if (mounted) _addTrainee();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Widget _buildTraineesList() {
    return ListView.separated(
      itemCount: _allTrainees.length,
      separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.white10),
      itemBuilder: (context, index) {
        final trainee = _allTrainees[index];
        final isSelected = _selectedTraineeIds.contains(trainee['id']);
        final List<dynamic> traineeRoles = trainee['role'] ?? [];
        
        return CheckboxListTile(
          value: isSelected,
          onChanged: (v) => _toggleMember(trainee['id'], v ?? false),
          activeColor: kAccent,
          checkColor: Colors.black,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  trainee['full_name'].toString().toUpperCase(),
                  style: AppTypography.bodyLg.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isSelected ? kForeground : kForegroundMuted,
                  ),
                ),
              ),
              if (traineeRoles.isNotEmpty)
                Wrap(
                  spacing: 4,
                  children: traineeRoles.map((r) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      r.toString().toUpperCase(),
                      style: AppTypography.overline.copyWith(color: kAccent, fontSize: 7),
                    ),
                  )).toList(),
                ),
            ],
          ),
          subtitle: trainee['email'] != null 
              ? Text(trainee['email'], style: AppTypography.caption) 
              : null,
          secondary: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? kAccent.withValues(alpha: 0.1) : kSurfaceElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isSelected ? Icons.person : Icons.person_outline,
              color: isSelected ? kAccent : kForegroundDisabled,
              size: 20,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_off_outlined, size: 48, color: kForegroundMuted.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            'NO PERSONNEL IN DATABASE',
            style: AppTypography.overline.copyWith(color: kForegroundMuted),
          ),
          const SizedBox(height: 8),
          Text(
            'Add trainees directly to this session.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 24),
          TechnicalButton(
            label: 'ADD FIRST TRAINEE',
            onTap: _addTrainee,
            icon: Icons.person_add_alt_1,
          ),
        ],
      ),
    );
  }
}
