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
        'status': 'active',
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
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(kPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _field(
                        icon: Icons.title_rounded,
                        hint: 'Session name...',
                        controller: _nameController,
                      ),
                      const Divider(height: 1, color: kBorder, indent: 44),
                      InkWell(
                        onTap: () => _selectDate(context),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(kRadius)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded, size: 17, color: kAccent),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  DateFormat('MMMM dd, yyyy').format(_selectedDate),
                                  style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, size: 16, color: kForegroundDisabled),
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
      ),
    );
  }

  Widget _field({required IconData icon, required String hint, required TextEditingController controller}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

