import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Sessions/edit_session_page.dart';

class SessionSettingsTab extends StatefulWidget {
  final String sessionId;
  final String sessionName;

  const SessionSettingsTab({
    super.key,
    required this.sessionId,
    required this.sessionName,
  });

  @override
  State<SessionSettingsTab> createState() => _SessionSettingsTabState();
}

class _SessionSettingsTabState extends State<SessionSettingsTab> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? _session;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSession();
  }

  Future<void> _fetchSession() async {
    setState(() => _isLoading = true);
    try {
      // Try cache first
      final cached = AppCache.instance.get<List<dynamic>>('sessions');
      if (cached != null) {
        final found = cached.cast<Map<String, dynamic>>().where((s) => s['id'] == widget.sessionId).firstOrNull;
        if (found != null) {
          setState(() { _session = found; _isLoading = false; });
          return;
        }
      }
      final data = await supabase.from('training_sessions').select().eq('id', widget.sessionId).single();
      setState(() { _session = data; _isLoading = false; });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  // ---------- Actions ----------

  Future<void> _toggleDone(bool markDone) async {
    final newStatus = markDone ? 'completed' : 'active';
    try {
      await supabase
          .from('training_sessions')
          .update({'status': newStatus})
          .eq('id', widget.sessionId);
      AppCache.instance.invalidate('sessions');
      setState(() => _session = {...?_session, 'status': newStatus});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _editSession() async {
    if (_session == null) return;
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditSessionPage(session: _session!)),
    );
    if (result == true && mounted) {
      AppCache.instance.invalidate('sessions');
      await _fetchSession();
    }
  }

  Future<void> _deleteSession() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
        title: const Text('Delete session?', style: AppTypography.h3),
        content: Text(
          'This will permanently delete "${widget.sessionName}" and all its activities, scores, and members. This cannot be undone.',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: kError, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await supabase.from('training_sessions').delete().eq('id', widget.sessionId);
      AppCache.instance.invalidate('sessions');
      AppCache.instance.invalidateWhere(
          (k) => k.contains(widget.sessionId) || k.startsWith('st:'));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  void _showFormulaDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: kAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(kRadiusSmall),
              ),
              child: const Icon(Icons.functions_rounded, color: kAccent, size: 16),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('Ranking Formula', style: AppTypography.h3)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rankings are computed differently depending on whether an activity has sub-questions.',
                style: AppTypography.body.copyWith(color: kForegroundMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),

              // Direct scoring
              _formulaSection(
                color: kInfo,
                icon: Icons.straighten_rounded,
                title: 'Direct Score',
                subtitle: 'Activities without sub-questions',
                body: 'Trainees are ranked by their raw score.\n\n'
                    '• Higher is Better → highest score = Rank 1\n'
                    '• Lower is Better → lowest score = Rank 1',
              ),
              const SizedBox(height: 16),

              // Aggregate scoring
              _formulaSection(
                color: kAccent,
                icon: Icons.calculate_rounded,
                title: 'Aggregate Score',
                subtitle: 'Activities with sub-questions',
                body: 'Each sub-question is first normalized to a 0–100 scale across all trainees, then averaged.',
              ),
              const SizedBox(height: 12),

              // Normalization formula box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kSurfaceElevated,
                  borderRadius: BorderRadius.circular(kRadiusSmall),
                  border: Border.all(color: kAccent.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Normalization', style: AppTypography.label.copyWith(color: kAccent, fontSize: 10)),
                    const SizedBox(height: 8),
                    _formulaLine('Higher is better:', '(score − min) ÷ (max − min) × 100'),
                    const SizedBox(height: 6),
                    _formulaLine('Lower is better:', '(max − score) ÷ (max − min) × 100'),
                    const SizedBox(height: 6),
                    _formulaLine('All scores equal:', '100 for everyone (full tie)'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kSurfaceElevated,
                  borderRadius: BorderRadius.circular(kRadiusSmall),
                  border: Border.all(color: kAccent.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Final Score', style: AppTypography.label.copyWith(color: kAccent, fontSize: 10)),
                    const SizedBox(height: 8),
                    _formulaLine('Score', 'Average of all normalized sub-scores'),
                    const SizedBox(height: 6),
                    _formulaLine('Rank 1', 'Highest average normalized score'),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Got it', style: TextStyle(color: kAccent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _formulaSection({
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required String body,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(kRadiusSmall),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, fontSize: 13)),
              Text(subtitle, style: AppTypography.caption.copyWith(fontSize: 10, color: color)),
              const SizedBox(height: 4),
              Text(body, style: AppTypography.body.copyWith(fontSize: 12, color: kForegroundMuted, height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _formulaLine(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: AppTypography.caption.copyWith(fontSize: 11, color: kForegroundMuted)),
        ),
        Expanded(
          child: Text(value, style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: kForeground)),
        ),
      ],
    );
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final isDone = _session?['status'] == 'completed';

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: kPadding,
        title: const Text('Settings', style: AppTypography.h3),
      ),
      body: Stack(
        children: [
          const TechnicalGridBackground(),
          if (_isLoading)
            const AppLoader()
          else
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(kPadding),
                children: [
                  // Session section
                  _sectionLabel('Session', Icons.layers_rounded),
                  const SizedBox(height: 8),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _toggleTile(
                          icon: isDone
                              ? Icons.check_circle_rounded
                              : Icons.check_circle_outline_rounded,
                          iconColor: kSuccess,
                          title: 'Mark as Done',
                          subtitle: isDone ? 'Session is completed' : 'Set this session as completed',
                          value: isDone,
                          onChanged: _toggleDone,
                        ),
                        const Divider(height: 1, indent: 56, color: kBorder),
                        _tile(
                          icon: Icons.edit_outlined,
                          iconColor: kInfo,
                          title: 'Edit Session',
                          subtitle: 'Change name, date or status',
                          onTap: _editSession,
                        ),
                        const Divider(height: 1, indent: 56, color: kBorder),
                        _tile(
                          icon: Icons.delete_outline_rounded,
                          iconColor: kError,
                          title: 'Delete Session',
                          subtitle: 'Permanently remove this session',
                          titleColor: kError,
                          onTap: _deleteSession,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Rankings section
                  _sectionLabel('Rankings', Icons.emoji_events_outlined),
                  const SizedBox(height: 8),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: _tile(
                      icon: Icons.functions_rounded,
                      iconColor: kAccent,
                      title: 'Ranking Formula',
                      subtitle: 'How scores are calculated and ranked',
                      onTap: _showFormulaDialog,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 13, color: kForegroundDisabled),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: AppTypography.overline.copyWith(color: kForegroundDisabled, fontSize: 10, letterSpacing: 1.2),
        ),
      ],
    );
  }

  Widget _toggleTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (value ? iconColor : kForegroundDisabled).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(kRadiusSmall),
            ),
            child: Icon(icon, size: 17, color: value ? iconColor : kForegroundDisabled),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: value ? iconColor : kForeground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTypography.caption.copyWith(fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: iconColor,
            activeTrackColor: iconColor.withValues(alpha: 0.25),
            inactiveThumbColor: kForegroundDisabled,
            inactiveTrackColor: kSurfaceElevated,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? titleColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(kRadiusSmall),
              ),
              child: Icon(icon, size: 17, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: titleColor ?? kForeground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTypography.caption.copyWith(fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, size: 18, color: kForegroundDisabled),
          ],
        ),
      ),
    );
  }
}
