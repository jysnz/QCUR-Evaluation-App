import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:intl/intl.dart';

class EditSessionPage extends StatefulWidget {
  final Map<String, dynamic> session;

  const EditSessionPage({super.key, required this.session});

  @override
  State<EditSessionPage> createState() => _EditSessionPageState();
}

class _EditSessionPageState extends State<EditSessionPage> {
  late final TextEditingController _nameController;
  late DateTime _selectedDate;
  late String _status;
  bool _isSaving = false;
  final supabase = Supabase.instance.client;

  static const _statuses = ['active', 'completed'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.session['name']?.toString() ?? '');
    _selectedDate = DateTime.parse(widget.session['date'] as String);
    _status = widget.session['status']?.toString() ?? 'active';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: kAccent,
            onPrimary: Colors.black,
            surface: kSurface,
            onSurface: kForeground,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a session name')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await supabase.from('training_sessions').update({
        'name': _nameController.text.trim(),
        'date': _selectedDate.toIso8601String(),
        'status': _status,
      }).eq('id', widget.session['id'] as String);

      AppCache.instance.invalidate('sessions');

      if (mounted) Navigator.of(context).pop(true);
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
        setState(() => _isSaving = false);
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active': return kSuccess;
      case 'completed': return kInfo;
      default: return kForegroundMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 44,
        title: const Text('Edit Session', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: kForegroundMuted, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: ResponsiveContainer(
            maxWidth: kMaxWidthForm,
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
                        onTap: _selectDate,
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
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.all(kPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.flag_outlined, size: 13, color: kInfo),
                          const SizedBox(width: 6),
                          Text(
                            'STATUS',
                            style: AppTypography.overline.copyWith(color: kInfo, fontSize: 10, letterSpacing: 1.1),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 8,
                        children: _statuses.map((s) {
                          final isSelected = _status == s;
                          final color = _statusColor(s);
                          return GestureDetector(
                            onTap: () => setState(() => _status = s),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSelected ? color.withValues(alpha: 0.12) : kSurfaceElevated,
                                borderRadius: BorderRadius.circular(kRadiusSmall),
                                border: Border.all(
                                  color: isSelected ? color : kBorder,
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                                    size: 13,
                                    color: isSelected ? color : kForegroundDisabled,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    s[0].toUpperCase() + s.substring(1),
                                    style: AppTypography.body.copyWith(
                                      color: isSelected ? kForeground : kForegroundMuted,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                AppButton(
                  label: 'Save Changes',
                  onTap: _isSaving ? null : _save,
                  isLoading: _isSaving,
                  icon: Icons.check_rounded,
                ),
              ],
            ),
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
