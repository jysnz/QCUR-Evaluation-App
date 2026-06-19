import 'package:flutter/material.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Sessions/session_details_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:intl/intl.dart';

class CreateSessionPage extends StatefulWidget {
  const CreateSessionPage({super.key});

  @override
  State<CreateSessionPage> createState() => _CreateSessionPageState();
}

class _CreateSessionPageState extends State<CreateSessionPage> {
  final _nameController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  final supabase = Supabase.instance.client;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: kAccent,
              onPrimary: Colors.black,
              surface: kSurface,
              onSurface: kForeground,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _createSession() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a session name')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw 'User not authenticated';

      final data = await supabase.from('training_sessions').insert({
        'name': _nameController.text.trim(),
        'date': _selectedDate.toIso8601String(),
        'creator_id': user.id,
        'status': 'planned',
      }).select().single();
      AppCache.instance.invalidate('sessions');

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => SessionDetailsPage(
              sessionId: data['id'],
              sessionName: data['name'],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating session: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBackground,
        title: const Text('New Session', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: kForegroundMuted),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: AppBackground(
        child: Padding(
          padding: const EdgeInsets.all(kPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                padding: const EdgeInsets.all(kPaddingLarge),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Details',
                      subtitle: 'Plan a new training session',
                    ),
                    const SizedBox(height: 32),
                    AppTextField(
                      label: 'Session Name',
                      hint: 'e.g., Monthly Training...',
                      controller: _nameController,
                    ),
                    const SizedBox(height: 24),
                    Text('Date', style: AppTypography.label),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _selectDate(context),
                      borderRadius: BorderRadius.circular(kRadiusSmall),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: kSurfaceElevated,
                          borderRadius: BorderRadius.circular(kRadiusSmall),
                          border: Border.all(color: kBorder.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('MMMM dd, yyyy').format(_selectedDate),
                              style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const Icon(Icons.calendar_today_rounded, color: kAccent, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              AppButton(
                label: 'Create Session',
                onTap: _createSession,
                isLoading: _isLoading,
                icon: Icons.rocket_launch_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

