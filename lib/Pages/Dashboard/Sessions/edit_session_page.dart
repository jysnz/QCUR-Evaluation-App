import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  static const _statuses = ['planned', 'active', 'completed'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.session['name']?.toString() ?? '');
    _selectedDate = DateTime.parse(widget.session['date'] as String);
    _status = widget.session['status']?.toString() ?? 'planned';
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
        setState(() => _isSaving = false);
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active': return kAccent;
      case 'completed': return kSuccess;
      case 'planned': return kInfo;
      default: return kForegroundMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Edit Session', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: kForegroundMuted),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(kPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppCard(
                        padding: const EdgeInsets.all(kPaddingLarge),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: kAccent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(kRadiusSmall),
                                  ),
                                  child: const Icon(Icons.layers_rounded, size: 16, color: kAccent),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: SectionHeader(
                                    title: 'Details',
                                    subtitle: 'Update session information',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            AppTextField(
                              label: 'Session Name',
                              hint: 'e.g., Monthly Training...',
                              controller: _nameController,
                              icon: Icons.title_rounded,
                            ),
                            const SizedBox(height: 20),
                            Text('Date', style: AppTypography.label),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _selectDate,
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
                      const SizedBox(height: 16),
                      AppCard(
                        padding: const EdgeInsets.all(kPaddingLarge),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: kInfo.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(kRadiusSmall),
                                  ),
                                  child: const Icon(Icons.flag_outlined, size: 16, color: kInfo),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: SectionHeader(
                                    title: 'Status',
                                    subtitle: 'Current session state',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 8,
                              runSpacing: 10,
                              children: _statuses.map((s) {
                                final isSelected = _status == s;
                                final color = _statusColor(s);
                                return GestureDetector(
                                  onTap: () => setState(() => _status = s),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
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
                                          isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                                          size: 15,
                                          color: isSelected ? color : kForegroundDisabled,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          s[0].toUpperCase() + s.substring(1),
                                          style: AppTypography.body.copyWith(
                                            color: isSelected ? kForeground : kForegroundMuted,
                                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                            fontSize: 13,
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
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(kPadding, 0, kPadding, kPadding),
                child: AppButton(
                  label: 'Save Changes',
                  onTap: _isSaving ? null : _save,
                  isLoading: _isSaving,
                  icon: Icons.check_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
