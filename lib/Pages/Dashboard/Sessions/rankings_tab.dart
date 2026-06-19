import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class RankingsTab extends StatefulWidget {
  final String sessionId;

  const RankingsTab({super.key, required this.sessionId});

  @override
  State<RankingsTab> createState() => _RankingsTabState();
}

class _RankingsTabState extends State<RankingsTab> with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _showByActivity = false;

  // Overall view: role → ranked trainees
  Map<String, List<Map<String, dynamic>>> _rankingsByRole = {};

  // By-Activity view: activity entry list
  List<_ActivityRanking> _activityRankings = [];

  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchAll();
    _subscribeToChanges();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unsubscribeFromChanges();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _unsubscribeFromChanges();
    } else if (state == AppLifecycleState.resumed) {
      _fetchAll();
      _subscribeToChanges();
    }
  }

  void _subscribeToChanges() {
    if (_realtimeChannel != null) return;
    _realtimeChannel = supabase
        .channel('public:activity_results:session:${widget.sessionId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'activity_results',
          callback: (_) => _fetchAll(),
        )
        .subscribe();
  }

  void _unsubscribeFromChanges() {
    if (_realtimeChannel != null) {
      supabase.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }

  Future<void> _fetchAll() async {
    setState(() => _isLoading = true);
    await Future.wait([_fetchOverallRankings(), _fetchActivityRankings()]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchOverallRankings() async {
    try {
      final actsKey = 'acts_score:${widget.sessionId}';
      final cachedActs = AppCache.instance.get<List<dynamic>>(actsKey);
      final activitiesData = cachedActs ??
          await supabase
              .from('activities')
              .select('id, name, scoring_direction')
              .eq('session_id', widget.sessionId)
              .eq('is_graded', true);
      if (cachedActs == null) AppCache.instance.set(actsKey, activitiesData);

      if (activitiesData.isEmpty) {
        _rankingsByRole = {};
        return;
      }

      final activityIds = activitiesData.map((a) => a['id']).toList();

      final resultsData = await supabase
          .from('activity_results')
          .select('''
            score,
            activity_id,
            trainees!inner (
              id,
              full_name,
              trainee_roles!inner (
                roles!inner (
                  id,
                  name
                )
              )
            )
          ''')
          .inFilter('activity_id', activityIds);

      final Map<String, Map<String, List<double>>> roleTraineeScores = {};
      final Map<String, String> traineeNames = {};

      for (var result in resultsData) {
        final score = (result['score'] as num).toDouble();
        final activityId = result['activity_id'];
        final trainee = result['trainees'] as Map<String, dynamic>;
        final traineeId = trainee['id'] as String;
        traineeNames[traineeId] = trainee['full_name'];

        final activity = activitiesData.firstWhere((a) => a['id'] == activityId);
        final scoringDirection = activity['scoring_direction'] ?? 'higher_is_better';
        final normalizedScore = scoringDirection == 'higher_is_better' ? score : -score;

        final rolesList = trainee['trainee_roles'] as List<dynamic>;
        for (var roleEntry in rolesList) {
          final roleName = roleEntry['roles']['name'] as String;
          roleTraineeScores.putIfAbsent(roleName, () => {});
          roleTraineeScores[roleName]!.putIfAbsent(traineeId, () => []);
          roleTraineeScores[roleName]![traineeId]!.add(normalizedScore);
        }
      }

      final Map<String, List<Map<String, dynamic>>> finalRankings = {};
      roleTraineeScores.forEach((roleName, traineeScores) {
        final List<Map<String, dynamic>> roleList = [];
        traineeScores.forEach((traineeId, scores) {
          final avgScore = scores.reduce((a, b) => a + b) / scores.length;
          roleList.add({
            'trainee_id': traineeId,
            'name': traineeNames[traineeId],
            'average_score': avgScore,
            'activity_count': scores.length,
          });
        });
        roleList.sort((a, b) => b['average_score'].compareTo(a['average_score']));
        finalRankings[roleName] = roleList;
      });

      _rankingsByRole = finalRankings;
    } catch (e) {
      debugPrint('Error fetching overall rankings: $e');
    }
  }

  Future<void> _fetchActivityRankings() async {
    try {
      // Fetch all graded activities with optional role
      final actsKey = 'acts_disp:${widget.sessionId}';
      final cachedActs = AppCache.instance.get<List<dynamic>>(actsKey);
      final activitiesData = cachedActs ??
          await supabase
              .from('activities')
              .select('id, name, target_role_id, roles(name)')
              .eq('session_id', widget.sessionId)
              .eq('is_graded', true)
              .order('order_index');
      if (cachedActs == null) AppCache.instance.set(actsKey, activitiesData);

      if (activitiesData.isEmpty) {
        _activityRankings = [];
        return;
      }

      final activityIds = activitiesData.map((a) => a['id']).toList();

      // Fetch scores with trainee info and role info
      final resultsData = await supabase
          .from('activity_results')
          .select('''
            score,
            activity_id,
            trainees!inner (
              id,
              full_name,
              trainee_roles (
                roles (
                  id,
                  name
                )
              )
            )
          ''')
          .inFilter('activity_id', activityIds);

      // Group by activity
      final Map<String, List<Map<String, dynamic>>> activityResults = {};
      for (var result in resultsData) {
        final actId = result['activity_id'] as String;
        activityResults.putIfAbsent(actId, () => []).add(result);
      }

      final List<_ActivityRanking> rankings = [];

      for (var activity in activitiesData) {
        final actId = activity['id'] as String;
        final targetRoleId = activity['target_role_id'] as String?;
        final roleName = activity['roles'] != null ? activity['roles']['name'] as String? : null;
        final results = activityResults[actId] ?? [];

        if (results.isEmpty) continue;

        // Filter by role if applicable
        final filteredResults = targetRoleId == null
            ? results
            : results.where((r) {
                final trainee = r['trainees'] as Map<String, dynamic>;
                final rolesList = trainee['trainee_roles'] as List<dynamic>;
                return rolesList.any((re) => re['roles'] != null && re['roles']['id'].toString() == targetRoleId);
              }).toList();

        if (filteredResults.isEmpty) continue;

        // Build ranked list
        final List<Map<String, dynamic>> ranked = filteredResults.map((r) {
          final trainee = r['trainees'] as Map<String, dynamic>;
          return {
            'trainee_id': trainee['id'],
            'name': trainee['full_name'],
            'average_score': (r['score'] as num).toDouble(),
            'activity_count': 1,
          };
        }).toList();

        ranked.sort((a, b) => b['average_score'].compareTo(a['average_score']));

        rankings.add(_ActivityRanking(
          activityId: actId,
          activityName: activity['name'] as String,
          roleName: roleName,
          ranked: ranked,
        ));
      }

      _activityRankings = rankings;
    } catch (e) {
      debugPrint('Error fetching activity rankings: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kAccent));
    }

    final isEmpty = _showByActivity ? _activityRankings.isEmpty : _rankingsByRole.isEmpty;

    if (isEmpty) {
      return _buildEmptyState();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Leaderboard', style: AppTypography.h3),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: kAccent),
            onPressed: _fetchAll,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _buildViewToggle(),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _showByActivity ? _activityRankings.length : _rankingsByRole.length,
              itemBuilder: (context, index) {
                if (_showByActivity) {
                  return _buildActivitySection(_activityRankings[index]);
                }
                final roleName = _rankingsByRole.keys.elementAt(index);
                return _buildRoleSection(roleName, _rankingsByRole[roleName]!);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: kSurfaceElevated,
        borderRadius: BorderRadius.circular(kRadiusSmall),
      ),
      child: Row(
        children: [
          Expanded(child: _toggleOption('Overall', !_showByActivity, () => setState(() => _showByActivity = false))),
          Expanded(child: _toggleOption('By Activity', _showByActivity, () => setState(() => _showByActivity = true))),
        ],
      ),
    );
  }

  Widget _toggleOption(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? kAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(kRadiusSmall - 2),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTypography.label.copyWith(
              color: isSelected ? Colors.white : kForegroundMuted,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleSection(String roleName, List<Map<String, dynamic>> trainees) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: kAccent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(roleName, style: AppTypography.h3.copyWith(color: kAccent)),
              const Spacer(),
              Text('${trainees.length} members', style: AppTypography.caption),
            ],
          ),
        ),
        ...trainees.asMap().entries.map((entry) => _buildRankingCard(entry.key + 1, entry.value)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildActivitySection(_ActivityRanking activity) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: kInfo,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(activity.activityName, style: AppTypography.h3.copyWith(fontSize: 15)),
                    if (activity.roleName != null)
                      Row(
                        children: [
                          const Icon(Icons.psychology_outlined, size: 11, color: kAccent),
                          const SizedBox(width: 4),
                          Text(activity.roleName!, style: AppTypography.caption.copyWith(color: kAccent, fontSize: 10)),
                        ],
                      )
                    else
                      Text('All roles', style: AppTypography.caption.copyWith(fontSize: 10)),
                  ],
                ),
              ),
              Text('${activity.ranked.length} ranked', style: AppTypography.caption),
            ],
          ),
        ),
        ...activity.ranked.asMap().entries.map((entry) => _buildRankingCard(entry.key + 1, entry.value)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildRankingCard(int rank, Map<String, dynamic> trainee) {
    Color rankColor;
    if (rank == 1) {
      rankColor = const Color(0xFFFFD700);
    } else if (rank == 2) {
      rankColor = const Color(0xFFC0C0C0);
    } else if (rank == 3) {
      rankColor = const Color(0xFFCD7F32);
    } else {
      rankColor = kForegroundMuted;
    }

    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      border: rank <= 3 ? Border.all(color: rankColor.withValues(alpha: 0.3)) : null,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: rank <= 3 ? rankColor.withValues(alpha: 0.1) : kSurfaceElevated,
              shape: BoxShape.circle,
              border: Border.all(color: rankColor.withValues(alpha: 0.5)),
            ),
            child: Center(
              child: Text(rank.toString(), style: AppTypography.h3.copyWith(color: rankColor, fontSize: 14)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trainee['name'], style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.bold)),
                Text(
                  _showByActivity ? 'Score' : '${trainee['activity_count']} activit${trainee['activity_count'] == 1 ? 'y' : 'ies'}',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                trainee['average_score'].abs().toStringAsFixed(2),
                style: AppTypography.h2.copyWith(color: kAccent),
              ),
              Text(
                _showByActivity ? 'Score' : 'Avg Score',
                style: AppTypography.label.copyWith(fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.emoji_events_rounded, size: 64, color: kForegroundDisabled),
          const SizedBox(height: 16),
          Text('No rankings yet', style: AppTypography.h3.copyWith(color: kForegroundMuted)),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Complete graded activities to generate rankings.',
              textAlign: TextAlign.center,
              style: AppTypography.caption,
            ),
          ),
          const SizedBox(height: 24),
          AppButton(
            label: 'Refresh',
            isFullWidth: false,
            onTap: _fetchAll,
          ),
        ],
      ),
    );
  }
}

class _ActivityRanking {
  final String activityId;
  final String activityName;
  final String? roleName;
  final List<Map<String, dynamic>> ranked;

  _ActivityRanking({
    required this.activityId,
    required this.activityName,
    this.roleName,
    required this.ranked,
  });
}
