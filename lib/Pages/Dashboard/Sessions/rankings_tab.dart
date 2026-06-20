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

  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _parentActivities = [];
  // parentId → sub-activities list
  Map<String, List<Map<String, dynamic>>> _subActivitiesMap = {};
  // activityId (parent or sub) → result rows with trainee data
  Map<String, List<Map<String, dynamic>>> _activityResultsMap = {};

  String? _selectedRoleId;
  String? _selectedRoleName;
  // Which parent activities are checked
  Set<String> _selectedParentIds = {};
  // parentId → selected sub-activity ID; null = All sub-questions
  Map<String, String?> _selectedSubIds = {};

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

  // ---------- Data ----------

  Future<void> _fetchAll() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([_fetchRoles(), _fetchActivitiesAndResults()]);
    } catch (e) {
      debugPrint('Rankings fetch error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchRoles() async {
    final cached = AppCache.instance.get<List<dynamic>>('roles');
    final data = cached ?? await supabase.from('roles').select().order('name');
    if (cached == null) {
      AppCache.instance.set('roles', data, ttl: const Duration(minutes: 30));
    }
    _roles = List<Map<String, dynamic>>.from(data);
  }

  Future<void> _fetchActivitiesAndResults() async {
    // 1. Parent activities (no is_graded filter — parents with subs have is_graded=false)
    final parentsData = await supabase
        .from('activities')
        .select('id, name, scoring_direction, target_role_id, roles(name)')
        .eq('session_id', widget.sessionId)
        .isFilter('parent_id', null)
        .order('order_index');

    _parentActivities = List<Map<String, dynamic>>.from(parentsData);

    if (_parentActivities.isEmpty) {
      _subActivitiesMap = {};
      _activityResultsMap = {};
      return;
    }

    final parentIds = _parentActivities.map((a) => a['id'] as String).toList();

    // 2. Sub-activities for all parents
    final subsData = await supabase
        .from('activities')
        .select('id, name, scoring_direction, parent_id, target_role_id')
        .inFilter('parent_id', parentIds)
        .order('order_index');

    final Map<String, List<Map<String, dynamic>>> subMap = {};
    for (final sub in subsData as List) {
      final pid = sub['parent_id'] as String;
      subMap.putIfAbsent(pid, () => []).add(Map<String, dynamic>.from(sub));
    }
    _subActivitiesMap = subMap;

    // 3. Fetch results for parents AND all sub-activities
    final allSubIds = (subsData).map((s) => s['id'] as String).toList();
    final allIds = [...parentIds, ...allSubIds];

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
        .inFilter('activity_id', allIds);

    final Map<String, List<Map<String, dynamic>>> map = {};
    for (final r in resultsData as List) {
      final actId = r['activity_id'] as String;
      map.putIfAbsent(actId, () => []).add(Map<String, dynamic>.from(r));
    }
    _activityResultsMap = map;
  }

  // ---------- Computed ----------

  // Parent activities visible for the selected role
  List<Map<String, dynamic>> get _activitiesForRole {
    if (_selectedRoleId == null) return [];
    return _parentActivities.where((a) {
      final rid = a['target_role_id'];
      return rid == null || rid.toString() == _selectedRoleId;
    }).toList();
  }

  // Filter results by selected role
  List<Map<String, dynamic>> _filterByRole(List<Map<String, dynamic>> results) {
    if (_selectedRoleId == null) return results;
    return results.where((r) {
      final trainee = r['trainees'] as Map<String, dynamic>;
      final rolesList = trainee['trainee_roles'] as List<dynamic>;
      return rolesList.any((re) =>
          re['roles'] != null &&
          re['roles']['id'].toString() == _selectedRoleId);
    }).toList();
  }

  // Single-activity direct ranking (no aggregation)
  _ActivityRanking? _directRanking({
    required String actId,
    required String activityName,
    required String scoringDirection,
  }) {
    final filtered = _filterByRole(_activityResultsMap[actId] ?? []);
    if (filtered.isEmpty) return null;

    final ranked = filtered.map((r) {
      final t = r['trainees'] as Map<String, dynamic>;
      return <String, dynamic>{
        'trainee_id': t['id'],
        'name': t['full_name'],
        'score': (r['score'] as num).toDouble(),
      };
    }).toList()
      ..sort((a, b) => scoringDirection == 'higher_is_better'
          ? (b['score'] as double).compareTo(a['score'] as double)
          : (a['score'] as double).compareTo(b['score'] as double));

    return _ActivityRanking(
      activityId: actId,
      activityName: activityName,
      scoringDirection: scoringDirection,
      ranked: ranked,
      isAggregate: false,
    );
  }

  // Aggregate sub-activity scores: normalize each sub to 0–100 then average
  _ActivityRanking? _aggregateRanking(Map<String, dynamic> parent) {
    final parentId = parent['id'] as String;
    final subs = _subActivitiesMap[parentId] ?? [];
    if (subs.isEmpty) return null;

    final Map<String, Map<String, dynamic>> traineeInfo = {};
    final Map<String, List<double>> traineeNorm = {};

    for (final sub in subs) {
      final subId = sub['id'] as String;
      final direction = (sub['scoring_direction'] ?? 'higher_is_better') as String;
      final filtered = _filterByRole(_activityResultsMap[subId] ?? []);
      if (filtered.isEmpty) continue;

      final scores = filtered.map((r) => (r['score'] as num).toDouble()).toList();
      final minS = scores.reduce((a, b) => a < b ? a : b);
      final maxS = scores.reduce((a, b) => a > b ? a : b);

      for (final r in filtered) {
        final t = r['trainees'] as Map<String, dynamic>;
        final tid = t['id'] as String;
        final raw = (r['score'] as num).toDouble();

        final double norm;
        if (maxS == minS) {
          norm = 100.0;
        } else if (direction == 'higher_is_better') {
          norm = (raw - minS) / (maxS - minS) * 100;
        } else {
          norm = (maxS - raw) / (maxS - minS) * 100;
        }

        traineeInfo[tid] = {'trainee_id': tid, 'name': t['full_name']};
        traineeNorm.putIfAbsent(tid, () => []).add(norm);
      }
    }

    if (traineeInfo.isEmpty) return null;

    final ranked = traineeInfo.values.map((t) {
      final tid = t['trainee_id'] as String;
      final scores = traineeNorm[tid]!;
      final avg = scores.reduce((a, b) => a + b) / scores.length;
      return <String, dynamic>{...t, 'score': avg};
    }).toList()
      ..sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    return _ActivityRanking(
      activityId: parentId,
      activityName: parent['name'] as String,
      scoringDirection: 'higher_is_better',
      ranked: ranked,
      isAggregate: true,
    );
  }

  List<_ActivityRanking> get _computedRankings {
    if (_selectedParentIds.isEmpty || _selectedRoleId == null) return [];
    final List<_ActivityRanking> result = [];

    for (final act in _parentActivities) {
      final parentId = act['id'] as String;
      if (!_selectedParentIds.contains(parentId)) continue;

      final subs = _subActivitiesMap[parentId] ?? [];

      if (subs.isEmpty) {
        // Directly scored parent
        final r = _directRanking(
          actId: parentId,
          activityName: act['name'] as String,
          scoringDirection: (act['scoring_direction'] ?? 'higher_is_better') as String,
        );
        if (r != null) result.add(r);
      } else {
        final selectedSubId = _selectedSubIds[parentId]; // null = All

        if (selectedSubId == null) {
          // Aggregate across all sub-activities
          final r = _aggregateRanking(act);
          if (r != null) result.add(r);
        } else {
          // Specific sub-activity
          final sub = subs.firstWhere(
            (s) => s['id'] == selectedSubId,
            orElse: () => {},
          );
          if (sub.isNotEmpty) {
            final r = _directRanking(
              actId: selectedSubId,
              activityName: '${act['name']} · ${sub['name']}',
              scoringDirection:
                  (sub['scoring_direction'] ?? 'higher_is_better') as String,
            );
            if (r != null) result.add(r);
          }
        }
      }
    }
    return result;
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kAccent));
    }

    final rankings = _computedRankings;

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
      body: ListView(
        padding: const EdgeInsets.only(bottom: kPadding),
        children: [
          // Role dropdown
          Padding(
            padding: const EdgeInsets.fromLTRB(kPadding, 4, kPadding, 8),
            child: _buildRoleDropdown(),
          ),

          // Activity filter
          if (_selectedRoleId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(kPadding, 0, kPadding, 8),
              child: _buildActivityFilter(),
            ),

          // Content
          if (_selectedRoleId == null)
            _centerHint(
              icon: Icons.group_outlined,
              title: 'Select a role',
              subtitle: 'Choose a role to see available activities.',
            )
          else if (_selectedParentIds.isEmpty)
            _centerHint(
              icon: Icons.checklist_rounded,
              title: 'Select activities',
              subtitle:
                  'Check one or more activities above to view rankings.',
            )
          else if (rankings.isEmpty)
            _centerHint(
              icon: Icons.emoji_events_rounded,
              title: 'No scores yet',
              subtitle:
                  'No trainees with this role have been scored for the selected activities.',
            )
          else
            ...rankings.map(
              (r) => Padding(
                padding: const EdgeInsets.fromLTRB(kPadding, 0, kPadding, 0),
                child: _buildActivitySection(r),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRoleDropdown() {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedRoleId,
          isExpanded: true,
          dropdownColor: kSurfaceElevated,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kAccent),
          hint: Row(
            children: [
              const Icon(Icons.psychology_outlined, size: 16, color: kForegroundDisabled),
              const SizedBox(width: 8),
              Text('Select a role',
                  style: AppTypography.body.copyWith(color: kForegroundDisabled)),
            ],
          ),
          selectedItemBuilder: (_) => _roles.map((role) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const Icon(Icons.psychology_outlined, size: 16, color: kAccent),
                  const SizedBox(width: 8),
                  Text(
                    role['name'].toString(),
                    style: AppTypography.body
                        .copyWith(color: kAccent, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }).toList(),
          items: _roles
              .map((role) => DropdownMenuItem<String>(
                    value: role['id'].toString(),
                    child: Text(role['name'].toString(), style: AppTypography.body),
                  ))
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedRoleId = value;
              _selectedRoleName = _roles
                  .firstWhere((r) => r['id'].toString() == value)['name']
                  .toString();
              _selectedParentIds = {};
              _selectedSubIds = {};
            });
          },
        ),
      ),
    );
  }

  Widget _buildActivityFilter() {
    final activities = _activitiesForRole;
    if (activities.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 14, color: kForegroundDisabled),
            const SizedBox(width: 8),
            Text('No activities found for this role',
                style: AppTypography.caption.copyWith(color: kForegroundMuted)),
          ],
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rounded, size: 14, color: kAccent),
              const SizedBox(width: 6),
              Text('Activities', style: AppTypography.label.copyWith(color: kAccent)),
              const Spacer(),
              if (_selectedParentIds.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() {
                    _selectedParentIds = {};
                    _selectedSubIds = {};
                  }),
                  child: Text('Clear',
                      style: AppTypography.caption
                          .copyWith(color: kForegroundMuted, fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...activities.map(_buildActivityRow),
        ],
      ),
    );
  }

  Widget _buildActivityRow(Map<String, dynamic> act) {
    final actId = act['id'] as String;
    final isChecked = _selectedParentIds.contains(actId);
    final subs = _subActivitiesMap[actId] ?? [];
    final hasSubs = subs.isNotEmpty;

    // For activities with no subs: check if there are direct results
    // For activities with subs: check if any sub has results
    final hasResults = hasSubs
        ? subs.any((s) => _activityResultsMap.containsKey(s['id']))
        : _activityResultsMap.containsKey(actId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Checkbox row
        GestureDetector(
          onTap: hasResults
              ? () => setState(() {
                    if (isChecked) {
                      _selectedParentIds.remove(actId);
                      _selectedSubIds.remove(actId);
                    } else {
                      _selectedParentIds.add(actId);
                      // Default: all sub-questions
                      if (hasSubs) _selectedSubIds[actId] = null;
                    }
                  })
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: isChecked
                  ? kAccent.withValues(alpha: 0.1)
                  : kSurfaceElevated.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(kRadiusSmall),
              border: Border.all(
                color: isChecked
                    ? kAccent.withValues(alpha: 0.4)
                    : kBorder.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                // Checkbox indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: isChecked ? kAccent : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isChecked ? kAccent : kBorder,
                      width: 1.5,
                    ),
                  ),
                  child: isChecked
                      ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 10),
                // Activity name
                Expanded(
                  child: Row(
                    children: [
                      if (hasSubs) ...[
                        const Icon(Icons.folder_outlined, size: 12, color: kForegroundMuted),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          act['name'].toString(),
                          style: AppTypography.body.copyWith(
                            fontSize: 13,
                            color: !hasResults
                                ? kForegroundDisabled
                                : isChecked
                                    ? kForeground
                                    : kForegroundMuted,
                            fontWeight:
                                isChecked ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!hasResults)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kSurfaceElevated,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('No scores',
                        style: AppTypography.caption
                            .copyWith(fontSize: 9, color: kForegroundDisabled)),
                  ),
              ],
            ),
          ),
        ),

        // Sub-activity dropdown (appears when parent is checked and has subs)
        if (isChecked && hasSubs) _buildSubDropdown(actId, subs),
      ],
    );
  }

  Widget _buildSubDropdown(String parentId, List<Map<String, dynamic>> subs) {
    final selectedSubId = _selectedSubIds[parentId];

    return Padding(
      padding: const EdgeInsets.only(left: 28, bottom: 6),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        color: kSurfaceElevated.withValues(alpha: 0.5),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: selectedSubId,
            isExpanded: true,
            dropdownColor: kSurfaceElevated,
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                size: 16, color: kForegroundMuted),
            style: AppTypography.body.copyWith(fontSize: 12, color: kForeground),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text('All sub-questions',
                    style: AppTypography.body
                        .copyWith(fontSize: 12, color: kForegroundMuted)),
              ),
              ...subs.map((sub) {
                final subId = sub['id'] as String;
                final hasScores = _activityResultsMap.containsKey(subId);
                return DropdownMenuItem<String?>(
                  value: subId,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          sub['name'].toString(),
                          style: AppTypography.body.copyWith(
                            fontSize: 12,
                            color: hasScores ? kForeground : kForegroundDisabled,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!hasScores) ...[
                        const SizedBox(width: 6),
                        Text('No scores',
                            style: AppTypography.caption
                                .copyWith(fontSize: 9, color: kForegroundDisabled)),
                      ],
                    ],
                  ),
                );
              }),
            ],
            onChanged: (value) =>
                setState(() => _selectedSubIds[parentId] = value),
          ),
        ),
      ),
    );
  }

  Widget _centerHint({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(icon, size: 48, color: kForegroundDisabled.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(title, style: AppTypography.h3.copyWith(color: kForegroundMuted)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              subtitle,
              style: AppTypography.caption.copyWith(color: kForegroundDisabled),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
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
                    color: kAccent, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(activity.activityName,
                        style: AppTypography.h3.copyWith(fontSize: 15)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.psychology_outlined,
                            size: 11, color: kAccent),
                        const SizedBox(width: 4),
                        Text(_selectedRoleName ?? '',
                            style: AppTypography.caption
                                .copyWith(color: kAccent, fontSize: 10)),
                        if (activity.isAggregate) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: kInfo.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text('Normalized avg',
                                style: AppTypography.caption.copyWith(
                                    fontSize: 9, color: kInfo)),
                          ),
                        ] else ...[
                          const SizedBox(width: 8),
                          Icon(
                            activity.scoringDirection == 'higher_is_better'
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 10,
                            color: kForegroundDisabled,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            activity.scoringDirection == 'higher_is_better'
                                ? 'Higher is better'
                                : 'Lower is better',
                            style: AppTypography.caption.copyWith(
                                fontSize: 10, color: kForegroundDisabled),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Text('${activity.ranked.length} ranked',
                  style: AppTypography.caption),
            ],
          ),
        ),
        ...activity.ranked.asMap().entries.map(
              (e) => _buildRankingCard(
                  e.key + 1, e.value, activity.isAggregate),
            ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildRankingCard(
      int rank, Map<String, dynamic> trainee, bool isAggregate) {
    final Color rankColor;
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
      border:
          rank <= 3 ? Border.all(color: rankColor.withValues(alpha: 0.3)) : null,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: rank <= 3
                  ? rankColor.withValues(alpha: 0.1)
                  : kSurfaceElevated,
              shape: BoxShape.circle,
              border: Border.all(color: rankColor.withValues(alpha: 0.5)),
            ),
            child: Center(
              child: Text(rank.toString(),
                  style: AppTypography.h3.copyWith(
                      color: rankColor, fontSize: 14)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              trainee['name'].toString(),
              style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                (trainee['score'] as double).toStringAsFixed(2),
                style: AppTypography.h2.copyWith(color: kAccent),
              ),
              Text(
                isAggregate ? 'Avg Score' : 'Score',
                style: AppTypography.label.copyWith(fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityRanking {
  final String activityId;
  final String activityName;
  final String scoringDirection;
  final List<Map<String, dynamic>> ranked;
  final bool isAggregate;

  _ActivityRanking({
    required this.activityId,
    required this.activityName,
    required this.scoringDirection,
    required this.ranked,
    required this.isAggregate,
  });
}
