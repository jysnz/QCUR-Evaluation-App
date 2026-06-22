import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class TraineeScoresPage extends StatefulWidget {
  final String traineeId;
  final String traineeName;

  const TraineeScoresPage({
    super.key,
    required this.traineeId,
    required this.traineeName,
  });

  @override
  State<TraineeScoresPage> createState() => _TraineeScoresPageState();
}

class _TraineeScoresPageState extends State<TraineeScoresPage> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;

  // Grouped: sessionId → { session, activities: [ { activity, subActivityName?, score } ] }
  List<_SessionScoreGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    _fetchScores();
  }

  Future<void> _refreshScores() async {
    AppCache.instance.invalidate('trainee_results:${widget.traineeId}');
    await _fetchScores();
  }

  Future<void> _fetchScores() async {
    setState(() => _isLoading = true);
    try {
      // Fetch all results for this trainee
      final resultsKey = 'trainee_results:${widget.traineeId}';
      final cachedResults = AppCache.instance.get<List<dynamic>>(resultsKey);
      final resultsData = cachedResults ??
          await supabase
              .from('activity_results')
              .select('score, feedback, activity_id')
              .eq('trainee_id', widget.traineeId);
      if (cachedResults == null) {
        AppCache.instance.set(resultsKey, resultsData, ttl: const Duration(minutes: 3));
      }

      if (resultsData.isEmpty) {
        setState(() {
          _groups = [];
          _isLoading = false;
        });
        return;
      }

      final activityIds = resultsData.map((r) => r['activity_id']).toList();

      // Fetch activities (including parent_id, session_id, name, scoring_direction)
      final activitiesData = await supabase
          .from('activities')
          .select('id, name, parent_id, session_id, target_role_id, scoring_direction, roles(name)')
          .inFilter('id', activityIds);

      // Collect parent_ids that aren't already in results
      final parentIds = activitiesData
          .where((a) => a['parent_id'] != null)
          .map((a) => a['parent_id'] as String)
          .toSet()
          .difference(activityIds.map((id) => id as String).toSet());

      Map<String, Map<String, dynamic>> parentActivitiesMap = {};
      if (parentIds.isNotEmpty) {
        final parentsData = await supabase
            .from('activities')
            .select('id, name')
            .inFilter('id', parentIds.toList());
        for (var p in parentsData) {
          parentActivitiesMap[p['id'] as String] = p;
        }
      }

      // Collect session IDs
      final sessionIds = activitiesData.map((a) => a['session_id']).toSet().toList();

      final sessionsData = await supabase
          .from('training_sessions')
          .select('id, name, date')
          .inFilter('id', sessionIds);

      final Map<String, Map<String, dynamic>> sessionsMap = {
        for (var s in sessionsData) s['id'] as String: s,
      };
      final Map<String, Map<String, dynamic>> activitiesMap = {
        for (var a in activitiesData) a['id'] as String: a,
      };
      // Fetch all results for the same activities to compute rank
      final allResultsData = await supabase
          .from('activity_results')
          .select('activity_id, score, trainee_id')
          .inFilter('activity_id', activityIds);

      // Build sessionId → activityId → [{trainee_id, score}] for unique ranking
      final Map<String, Map<String, List<Map<String, dynamic>>>> sessionActivityEntries = {};
      for (var r in allResultsData) {
        final actId = r['activity_id'] as String;
        final activity = activitiesMap[actId];
        if (activity == null) continue;
        final sessionId = activity['session_id'] as String;
        sessionActivityEntries.putIfAbsent(sessionId, () => {});
        sessionActivityEntries[sessionId]!.putIfAbsent(actId, () => []);
        sessionActivityEntries[sessionId]![actId]!.add({
          'trainee_id': r['trainee_id'] as String,
          'score': (r['score'] as num).toDouble(),
        });
      }

      // Group results by session
      final Map<String, List<_ScoreEntry>> sessionEntries = {};
      for (var result in resultsData) {
        final actId = result['activity_id'] as String;
        final activity = activitiesMap[actId];
        if (activity == null) continue;

        final sessionId = activity['session_id'] as String;
        final parentId = activity['parent_id'] as String?;
        final parentActivity = parentId != null ? parentActivitiesMap[parentId] : null;

        final score = (result['score'] as num).toDouble();

        // Compute unique rank: sort by scoring_direction, find this trainee's position
        final direction = activity['scoring_direction'] as String? ?? 'higher_is_better';
        final higherBetter = direction == 'higher_is_better';
        final allEntries = List<Map<String, dynamic>>.from(
          sessionActivityEntries[sessionId]?[actId] ??
              [{'trainee_id': widget.traineeId, 'score': score}],
        );
        allEntries.sort((a, b) => higherBetter
            ? (b['score'] as double).compareTo(a['score'] as double)
            : (a['score'] as double).compareTo(b['score'] as double));
        final rankIndex = allEntries.indexWhere((e) => e['trainee_id'] == widget.traineeId);
        final rank = rankIndex < 0 ? 1 : rankIndex + 1;

        final roleName = activity['roles'] != null ? activity['roles']['name'] as String? : null;

        sessionEntries.putIfAbsent(sessionId, () => []).add(_ScoreEntry(
          activityId: actId,
          activityName: parentActivity != null ? parentActivity['name'] as String : activity['name'] as String,
          subActivityName: parentActivity != null ? activity['name'] as String : null,
          score: score,
          feedback: result['feedback'] as String?,
          rank: rank,
          totalParticipants: allEntries.length,
          roleName: roleName,
          sessionId: sessionId,
          sessionName: sessionsMap[sessionId]?['name'] as String? ?? 'Unknown Session',
        ));
      }

      final groups = <_SessionScoreGroup>[];
      for (var sessionId in sessionIds) {
        final session = sessionsMap[sessionId];
        final entries = sessionEntries[sessionId];
        if (session == null || entries == null || entries.isEmpty) continue;
        groups.add(_SessionScoreGroup(
          sessionId: sessionId,
          sessionName: session['name'] as String,
          date: session['date'] as String,
          entries: entries,
        ));
      }

      // Sort sessions by date descending
      groups.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _groups = groups;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching scores: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  void _showScoreDetail(BuildContext context, _ScoreEntry entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadius)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(kPadding, 20, kPadding, kPaddingLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: kForegroundDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Score Detail', style: AppTypography.h3),
            const SizedBox(height: 20),
            _detailRow(Icons.folder_outlined, 'Activity', entry.activityName),
            if (entry.subActivityName != null) ...[
              const SizedBox(height: 12),
              _detailRow(Icons.subdirectory_arrow_right_rounded, 'Sub-activity', entry.subActivityName!),
            ],
            if (entry.roleName != null) ...[
              const SizedBox(height: 12),
              _detailRow(Icons.psychology_outlined, 'Role', entry.roleName!),
            ],
            const SizedBox(height: 12),
            _detailRow(Icons.layers_outlined, 'Session', entry.sessionName),
            const Divider(height: 32, color: kBorder),
            Row(
              children: [
                Expanded(
                  child: _scoreChip(
                    label: 'Score',
                    value: entry.score.toStringAsFixed(entry.score == entry.score.roundToDouble() ? 0 : 2),
                    color: kAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _scoreChip(
                    label: 'Rank',
                    value: '#${entry.rank} / ${entry.totalParticipants}',
                    color: entry.rank == 1
                        ? const Color(0xFFFFD700)
                        : entry.rank == 2
                            ? const Color(0xFFC0C0C0)
                            : entry.rank == 3
                                ? const Color(0xFFCD7F32)
                                : kInfo,
                  ),
                ),
              ],
            ),
            if (entry.feedback != null && entry.feedback!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Feedback', style: AppTypography.label),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kSurfaceElevated,
                  borderRadius: BorderRadius.circular(kRadiusSmall),
                ),
                child: Text(entry.feedback!, style: AppTypography.body.copyWith(fontSize: 13)),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: kForegroundMuted),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.label.copyWith(fontSize: 10)),
            const SizedBox(height: 2),
            Text(value, style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _scoreChip({required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(kRadiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(value, style: AppTypography.h2.copyWith(color: color, fontSize: 20)),
          const SizedBox(height: 4),
          Text(label, style: AppTypography.label.copyWith(fontSize: 10)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Score History', style: AppTypography.overline.copyWith(color: kForegroundMuted)),
            Text(widget.traineeName, style: AppTypography.h3),
          ],
        ),
      ),
      body: Stack(
        children: [
          const AppBackground(child: SizedBox.expand()),
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: kAccent))
              : _groups.isEmpty
                  ? _buildEmptyState()
                  : SafeArea(
                      child: ResponsiveContainer(
                        maxWidth: kMaxWidthContent,
                        child: RefreshIndicator(
                        onRefresh: _refreshScores,
                        color: kAccent,
                        backgroundColor: kSurfaceElevated,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(kPadding),
                          itemCount: _groups.length,
                          itemBuilder: (context, i) => _buildSessionGroup(_groups[i]),
                        ),
                      ),
                      ),
                    ),
        ],
      ),
    );
  }

  Widget _buildSessionGroup(_SessionScoreGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(kRadiusSmall),
                ),
                child: const Icon(Icons.layers_rounded, size: 14, color: kAccent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  group.sessionName.toUpperCase(),
                  style: AppTypography.label.copyWith(color: kAccent, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        ...group.entries.map((entry) => _buildScoreCard(entry)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildScoreCard(_ScoreEntry entry) {
    Color rankColor = kForegroundMuted;
    if (entry.rank == 1) {
      rankColor = const Color(0xFFFFD700);
    } else if (entry.rank == 2) {
      rankColor = const Color(0xFFC0C0C0);
    } else if (entry.rank == 3) {
      rankColor = const Color(0xFFCD7F32);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () => _showScoreDetail(context, entry),
          borderRadius: BorderRadius.circular(kRadius),
          splashColor: kAccent.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: kAccent.withValues(alpha: 0.1),
                  child: Text(
                    _getInitials(widget.traineeName),
                    style: TextStyle(color: kAccent, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.activityName,
                        style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (entry.subActivityName != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.subdirectory_arrow_right_rounded, size: 12, color: kForegroundDisabled),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                entry.subActivityName!,
                                style: AppTypography.caption.copyWith(fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (entry.roleName != null) ...[
                        const SizedBox(height: 2),
                        Text(entry.roleName!, style: AppTypography.caption.copyWith(color: kAccent, fontSize: 10)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      entry.score.toStringAsFixed(entry.score == entry.score.roundToDouble() ? 0 : 2),
                      style: AppTypography.h3.copyWith(color: kAccent, fontSize: 18),
                    ),
                    Row(
                      children: [
                        Icon(Icons.emoji_events_rounded, size: 11, color: rankColor),
                        const SizedBox(width: 3),
                        Text(
                          '#${entry.rank}',
                          style: AppTypography.label.copyWith(color: rankColor, fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 16, color: kForegroundDisabled),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart_rounded, size: 64, color: kForegroundDisabled.withValues(alpha: 0.2)),
          const SizedBox(height: 20),
          Text('No scores yet', style: AppTypography.h3.copyWith(color: kForegroundMuted)),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'This member has not been scored in any activity yet.',
              textAlign: TextAlign.center,
              style: AppTypography.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionScoreGroup {
  final String sessionId;
  final String sessionName;
  final String date;
  final List<_ScoreEntry> entries;

  _SessionScoreGroup({
    required this.sessionId,
    required this.sessionName,
    required this.date,
    required this.entries,
  });
}

class _ScoreEntry {
  final String activityId;
  final String activityName;
  final String? subActivityName;
  final double score;
  final String? feedback;
  final int rank;
  final int totalParticipants;
  final String? roleName;
  final String sessionId;
  final String sessionName;

  _ScoreEntry({
    required this.activityId,
    required this.activityName,
    this.subActivityName,
    required this.score,
    this.feedback,
    required this.rank,
    required this.totalParticipants,
    this.roleName,
    required this.sessionId,
    required this.sessionName,
  });
}
