import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  Map<String, List<Map<String, dynamic>>> _rankingsByRole = {};
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchRankings();
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
      _fetchRankings(); // Refresh data when coming back
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
          callback: (payload) {
            // Re-fetch everything to ensure accuracy across roles/averages
            _fetchRankings();
          },
        )
        .subscribe();
  }

  void _unsubscribeFromChanges() {
    if (_realtimeChannel != null) {
      supabase.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }

  Future<void> _fetchRankings() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch all graded activities for this session
      final activitiesData = await supabase
          .from('activities')
          .select('id, name, scoring_direction')
          .eq('session_id', widget.sessionId)
          .eq('is_graded', true);

      if (activitiesData.isEmpty) {
        setState(() {
          _rankingsByRole = {};
          _isLoading = false;
        });
        return;
      }

      final activityIds = activitiesData.map((a) => a['id']).toList();

      // 2. Fetch all results for these activities with trainee and role info
      // We need to join with trainee_roles and roles to get the role names
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

      // 3. Process and aggregate rankings
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

        // Normalize score: if lower is better, we invert it for ranking (simplified approach)
        // In a real system, you might want Z-scores or percentile rankings per activity
        final normalizedScore = scoringDirection == 'higher_is_better' ? score : -score;

        final rolesList = trainee['trainee_roles'] as List<dynamic>;
        for (var roleEntry in rolesList) {
          final roleName = roleEntry['roles']['name'] as String;
          
          roleTraineeScores.putIfAbsent(roleName, () => {});
          roleTraineeScores[roleName]!.putIfAbsent(traineeId, () => []);
          roleTraineeScores[roleName]![traineeId]!.add(normalizedScore);
        }
      }

      // 4. Calculate averages and sort
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

        // Sort by average score descending
        roleList.sort((a, b) => b['average_score'].compareTo(a['average_score']));
        finalRankings[roleName] = roleList;
      });

      setState(() {
        _rankingsByRole = finalRankings;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching rankings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading rankings: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kAccent));
    }

    if (_rankingsByRole.isEmpty) {
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
            onPressed: _fetchRankings,
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _rankingsByRole.length,
        itemBuilder: (context, index) {
          final roleName = _rankingsByRole.keys.elementAt(index);
          final trainees = _rankingsByRole[roleName]!;
          return _buildRoleSection(roleName, trainees);
        },
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
              Text(
                roleName,
                style: AppTypography.h3.copyWith(color: kAccent),
              ),
              const Spacer(),
              Text(
                '${trainees.length} members',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
        ...trainees.asMap().entries.map((entry) {
          final idx = entry.key;
          final trainee = entry.value;
          return _buildRankingCard(idx + 1, trainee);
        }),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildRankingCard(int rank, Map<String, dynamic> trainee) {
    Color rankColor;
    if (rank == 1) {
      rankColor = const Color(0xFFFFD700); // Gold
    } else if (rank == 2) {
      rankColor = const Color(0xFFC0C0C0); // Silver
    } else if (rank == 3) {
      rankColor = const Color(0xFFCD7F32); // Bronze
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
              child: Text(
                rank.toString(),
                style: AppTypography.h3.copyWith(color: rankColor, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trainee['name'], style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.bold)),
                Text(
                  '${trainee['activity_count']} activities',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                trainee['average_score'].toStringAsFixed(2),
                style: AppTypography.h2.copyWith(color: kAccent),
              ),
              Text(
                'Avg Score',
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
          Icon(Icons.emoji_events_rounded, size: 64, color: kForegroundDisabled),
          const SizedBox(height: 16),
          Text(
            'No rankings yet',
            style: AppTypography.h3.copyWith(color: kForegroundMuted),
          ),
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
            onTap: _fetchRankings,
          ),
        ],
      ),
    );
  }
}
