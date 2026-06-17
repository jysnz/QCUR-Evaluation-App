import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class TraineesPage extends StatefulWidget {
  const TraineesPage({super.key});

  @override
  State<TraineesPage> createState() => _TraineesPageState();
}

class _TraineesPageState extends State<TraineesPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _trainees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTrainees();
  }

  Future<void> _fetchTrainees() async {
    setState(() => _isLoading = true);
    try {
      final data = await supabase
          .from('trainees')
          .select()
          .order('full_name');
      setState(() {
        _trainees = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() => _isLoading = false);
    }
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

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kSurface,
          surfaceTintColor: Colors.transparent,
          title: Text('REGISTER TRAINEE', style: AppTypography.h3.copyWith(color: kAccent, letterSpacing: 1)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Full Name',
                  hint: 'e.g. John Doe',
                  controller: nameController,
                ),
                const SizedBox(height: 20),
                AppTextField(
                  label: 'Email (Optional)',
                  hint: 'e.g. john@example.com',
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 24),
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
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('CANCEL', style: AppTypography.caption.copyWith(color: kForegroundMuted)),
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
        await supabase.from('trainees').insert({
          'full_name': nameController.text.trim(),
          'email': emailController.text.trim().isEmpty ? null : emailController.text.trim(),
          'role': selectedRoles,
          'creator_id': supabase.auth.currentUser!.id,
        });
        _fetchTrainees();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('TRAINEE DATABASE', style: AppTypography.h3.copyWith(letterSpacing: 2)),
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
                    title: 'Active Personnel',
                    subtitle: 'Manage and track trainee profiles',
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: TechnicalCard(
                      padding: EdgeInsets.zero,
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator(color: kAccent))
                          : _trainees.isEmpty
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

  Widget _buildTraineesList() {
    return ListView.separated(
      itemCount: _trainees.length,
      separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.white10),
      itemBuilder: (context, index) {
        final trainee = _trainees[index];
        final List<dynamic> traineeRoles = trainee['role'] ?? [];

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.person_outline, color: kAccent, size: 20),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  trainee['full_name'].toString().toUpperCase(),
                  style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.w800),
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
                      style: AppTypography.overline.copyWith(color: kAccent, fontSize: 8),
                    ),
                  )).toList(),
                ),
            ],
          ),
          subtitle: trainee['email'] != null 
              ? Text(trainee['email'], style: AppTypography.caption) 
              : null,
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: kError, size: 20),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: kSurface,
                  title: const Text('DELETE TRAINEE?', style: AppTypography.h3),
                  content: Text('Are you sure you want to remove ${trainee['full_name']}?', style: AppTypography.body),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('DELETE', style: TextStyle(color: kError))),
                  ],
                ),
              );
              if (confirm == true) {
                await supabase.from('trainees').delete().eq('id', trainee['id']);
                _fetchTrainees();
              }
            },
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
          Icon(Icons.person_off_outlined, size: 48, color: kForegroundMuted.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          Text(
            'DATABASE EMPTY',
            style: AppTypography.overline.copyWith(color: kForegroundMuted),
          ),
        ],
      ),
    );
  }
}

