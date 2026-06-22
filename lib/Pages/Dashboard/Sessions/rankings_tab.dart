import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class RankingsTab extends StatefulWidget {
  final String sessionId;
  final ValueNotifier<int> visibilityTrigger;

  const RankingsTab({
    super.key,
    required this.sessionId,
    required this.visibilityTrigger,
  });

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
  // parentId → selected sub-activity ID; null = All sub-activities
  Map<String, String?> _selectedSubIds = {};

  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.visibilityTrigger.addListener(_onTabVisible);
    _fetchAll();
    _subscribeToChanges();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.visibilityTrigger.removeListener(_onTabVisible);
    _unsubscribeFromChanges();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _unsubscribeFromChanges();
    } else if (state == AppLifecycleState.resumed) {
      _checkAndFetchIfStale();
      _subscribeToChanges();
    }
  }

  void _onTabVisible() => _checkAndFetchIfStale();

  void _checkAndFetchIfStale() {
    final cached = AppCache.instance.get<Map<String, dynamic>>('rankings:${widget.sessionId}');
    if (cached == null) _fetchAll();
  }

  void _subscribeToChanges() {
    if (_realtimeChannel != null) return;
    _realtimeChannel = supabase
        .channel('public:activity_results:session:${widget.sessionId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'activity_results',
          callback: (_) {
            AppCache.instance.invalidate('rankings:${widget.sessionId}');
            _fetchAll(forceRefresh: true);
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

  // ---------- Data ----------

  Future<void> _fetchAll({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([_fetchRoles(), _fetchActivitiesAndResults(forceRefresh: forceRefresh)]);
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

  Future<void> _fetchActivitiesAndResults({bool forceRefresh = false}) async {
    final cacheKey = 'rankings:${widget.sessionId}';

    if (!forceRefresh) {
      final cached = AppCache.instance.get<Map<String, dynamic>>(cacheKey);
      if (cached != null) {
        _buildFromCached(cached);
        return;
      }
    }

    // 1. Parent activities
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
      AppCache.instance.set(cacheKey, {'parents': List.from(parentsData), 'subs': [], 'results': []});
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
    final allSubIds = (subsData as List).map((s) => s['id'] as String).toList();
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

    AppCache.instance.set(cacheKey, {
      'parents': List.from(parentsData),
      'subs': List.from(subsData),
      'results': List.from(resultsData),
    });
  }

  void _buildFromCached(Map<String, dynamic> cached) {
    final parentsData = cached['parents'] as List;
    final subsData = cached['subs'] as List;
    final resultsData = cached['results'] as List;

    _parentActivities = List<Map<String, dynamic>>.from(parentsData);

    final Map<String, List<Map<String, dynamic>>> subMap = {};
    for (final sub in subsData) {
      final pid = sub['parent_id'] as String;
      subMap.putIfAbsent(pid, () => []).add(Map<String, dynamic>.from(sub));
    }
    _subActivitiesMap = subMap;

    final Map<String, List<Map<String, dynamic>>> map = {};
    for (final r in resultsData) {
      final actId = r['activity_id'] as String;
      map.putIfAbsent(actId, () => []).add(Map<String, dynamic>.from(r));
    }
    _activityResultsMap = map;
  }

  // ---------- Computed ----------

  // Parent activities visible for the selected role
  List<Map<String, dynamic>> get _activitiesForRole {
    if (_selectedRoleId == null) return [];
    // "All Roles" → only activities explicitly assigned to all roles (no specific role)
    if (_selectedRoleId == '__all__') {
      return _parentActivities
          .where((a) => a['target_role_id'] == null)
          .toList();
    }
    return _parentActivities.where((a) {
      final rid = a['target_role_id'];
      return rid == null || rid.toString() == _selectedRoleId;
    }).toList();
  }

  // Filter results by selected role
  List<Map<String, dynamic>> _filterByRole(List<Map<String, dynamic>> results) {
    if (_selectedRoleId == null || _selectedRoleId == '__all__') return results;
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
        toolbarHeight: 44,
        title: const Text('Leaderboard', style: AppTypography.h3),
      ),
      body: ResponsiveContainer(
        maxWidth: kMaxWidthContent,
        child: RefreshIndicator(
        onRefresh: () async {
          AppCache.instance.invalidate('rankings:${widget.sessionId}');
          await _fetchAll(forceRefresh: true);
        },
        color: kAccent,
        backgroundColor: kSurfaceElevated,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
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
      ),
      ),
    );
  }

  Widget _buildRoleDropdown() {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedRoleId,
          isExpanded: true,
          dropdownColor: kSurfaceElevated,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kAccent, size: 16),
          hint: Row(
            children: [
              const Icon(Icons.psychology_outlined, size: 14, color: kForegroundDisabled),
              const SizedBox(width: 6),
              Text('Select a role',
                  style: AppTypography.body.copyWith(color: kForegroundDisabled, fontSize: 13)),
            ],
          ),
          selectedItemBuilder: (_) => [
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const Icon(Icons.groups_rounded, size: 14, color: kAccent),
                  const SizedBox(width: 6),
                  Text('All Roles',
                      style: AppTypography.body
                          .copyWith(color: kAccent, fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            ),
            ..._roles.map((role) => Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const Icon(Icons.psychology_outlined, size: 14, color: kAccent),
                  const SizedBox(width: 6),
                  Text(
                    role['name'].toString(),
                    style: AppTypography.body
                        .copyWith(color: kAccent, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            )),
          ],
          items: [
            DropdownMenuItem<String>(
              value: '__all__',
              child: Row(
                children: [
                  const Icon(Icons.groups_rounded, size: 14, color: kAccent),
                  const SizedBox(width: 6),
                  Text('All Roles',
                      style: AppTypography.body
                          .copyWith(color: kAccent, fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            ),
            ..._roles.map((role) => DropdownMenuItem<String>(
                  value: role['id'].toString(),
                  child: Text(role['name'].toString(),
                      style: AppTypography.body.copyWith(fontSize: 13)),
                )),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedRoleId = value;
              _selectedRoleName = value == '__all__'
                  ? 'All Roles'
                  : _roles
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
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 13, color: kForegroundDisabled),
            const SizedBox(width: 8),
            Text('No activities found for this role',
                style: AppTypography.caption.copyWith(color: kForegroundMuted, fontSize: 12)),
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
                      if (hasSubs) _selectedSubIds[actId] = null;
                    }
                  })
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 5),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isChecked ? kAccent : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isChecked ? kAccent : kBorder,
                      width: 1.5,
                    ),
                  ),
                  child: isChecked
                      ? const Icon(Icons.check_rounded, size: 10, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.folder_outlined, size: 11, color: kForegroundMuted),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          act['name'].toString(),
                          style: AppTypography.body.copyWith(
                            fontSize: 12,
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
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
      padding: const EdgeInsets.only(left: 24, bottom: 4),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        color: kSurfaceElevated.withValues(alpha: 0.5),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: selectedSubId,
            isExpanded: true,
            isDense: true,
            dropdownColor: kSurfaceElevated,
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                size: 13, color: kForegroundMuted),
            style: AppTypography.body.copyWith(fontSize: 11, color: kForeground),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text('All sub-activities',
                    style: AppTypography.body
                        .copyWith(fontSize: 11, color: kForegroundMuted)),
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
                            fontSize: 11,
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
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(icon, size: 40, color: kForegroundDisabled.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(title, style: AppTypography.h3.copyWith(color: kForegroundMuted)),
          const SizedBox(height: 6),
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                    color: kAccent, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(activity.activityName,
                        style: AppTypography.h3.copyWith(fontSize: 13)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.psychology_outlined,
                            size: 10, color: kAccent),
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
                  style: AppTypography.caption.copyWith(fontSize: 11)),
            ],
          ),
        ),
        ...activity.ranked.asMap().entries.map(
              (e) => _buildRankingCard(
                  e.key + 1, e.value, activity.isAggregate),
            ),
        const SizedBox(height: 10),
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
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      border:
          rank <= 3 ? Border.all(color: rankColor.withValues(alpha: 0.3)) : null,
      child: InkWell(
        onTap: () => _openTraineeDetail(
          traineeId: trainee['trainee_id'] as String,
          traineeName: trainee['name'] as String,
        ),
        borderRadius: BorderRadius.circular(kRadius),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
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
                        color: rankColor, fontSize: 11)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                trainee['name'].toString(),
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: kForegroundMuted, size: 16),
          ],
        ),
      ),
    );
  }

  void _openTraineeDetail({
    required String traineeId,
    required String traineeName,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TraineeScoreSheet(
        traineeId: traineeId,
        traineeName: traineeName,
        selectedRoleId: _selectedRoleId!,
        parentActivities: _activitiesForRole,
        subActivitiesMap: _subActivitiesMap,
        activityResultsMap: _activityResultsMap,
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

// ---------- Trainee score detail bottom sheet ----------

class _TraineeScoreSheet extends StatefulWidget {
  final String traineeId;
  final String traineeName;
  final String selectedRoleId;
  final List<Map<String, dynamic>> parentActivities;
  final Map<String, List<Map<String, dynamic>>> subActivitiesMap;
  final Map<String, List<Map<String, dynamic>>> activityResultsMap;

  const _TraineeScoreSheet({
    required this.traineeId,
    required this.traineeName,
    required this.selectedRoleId,
    required this.parentActivities,
    required this.subActivitiesMap,
    required this.activityResultsMap,
  });

  @override
  State<_TraineeScoreSheet> createState() => _TraineeScoreSheetState();
}

class _TraineeScoreSheetState extends State<_TraineeScoreSheet> {
  // parentId → selected sub-activity ID; null = All sub-activities
  final Map<String, String?> _selectedSubIds = {};

  List<Map<String, dynamic>> _filterByRole(
      List<Map<String, dynamic>> results) {
    if (widget.selectedRoleId == '__all__') return results;
    return results.where((r) {
      final trainee = r['trainees'] as Map<String, dynamic>;
      final rolesList = trainee['trainee_roles'] as List<dynamic>;
      return rolesList.any((re) =>
          re['roles'] != null &&
          re['roles']['id'].toString() == widget.selectedRoleId);
    }).toList();
  }

  // {score, rank, total, isAggregate} for a directly scored activity
  Map<String, dynamic>? _directInfo(String actId, String scoringDirection) {
    final filtered =
        _filterByRole(widget.activityResultsMap[actId] ?? []);
    if (filtered.isEmpty) return null;

    final sorted = filtered
        .map((r) {
          final t = r['trainees'] as Map<String, dynamic>;
          return {
            'trainee_id': t['id'] as String,
            'score': (r['score'] as num).toDouble(),
          };
        })
        .toList()
      ..sort((a, b) => scoringDirection == 'higher_is_better'
          ? (b['score'] as double).compareTo(a['score'] as double)
          : (a['score'] as double).compareTo(b['score'] as double));

    final idx =
        sorted.indexWhere((e) => e['trainee_id'] == widget.traineeId);
    if (idx == -1) return null;

    return {
      'score': sorted[idx]['score'] as double,
      'rank': idx + 1,
      'total': sorted.length,
      'isAggregate': false,
    };
  }

  // {score, rank, total, isAggregate:true}
  // Rank is computed via normalization; score is the trainee's raw average.
  Map<String, dynamic>? _aggregateInfo(
      String parentId, List<Map<String, dynamic>> subs) {
    final Map<String, List<double>> traineeNorm = {};
    final List<double> thisTraineeRaw = [];

    for (final sub in subs) {
      final subId = sub['id'] as String;
      final direction =
          (sub['scoring_direction'] ?? 'higher_is_better') as String;
      final filtered =
          _filterByRole(widget.activityResultsMap[subId] ?? []);
      if (filtered.isEmpty) continue;

      final scores =
          filtered.map((r) => (r['score'] as num).toDouble()).toList();
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
        traineeNorm.putIfAbsent(tid, () => []).add(norm);
        if (tid == widget.traineeId) thisTraineeRaw.add(raw);
      }
    }

    if (traineeNorm.isEmpty) return null;

    final ranked = traineeNorm.entries
        .map((e) {
          final avg = e.value.reduce((a, b) => a + b) / e.value.length;
          return {'trainee_id': e.key, 'score': avg};
        })
        .toList()
      ..sort((a, b) =>
          (b['score'] as double).compareTo(a['score'] as double));

    final idx =
        ranked.indexWhere((e) => e['trainee_id'] == widget.traineeId);
    if (idx == -1) return null;

    final rawAvg = thisTraineeRaw.isEmpty
        ? 0.0
        : thisTraineeRaw.reduce((a, b) => a + b) / thisTraineeRaw.length;

    return {
      'score': rawAvg,
      'rank': idx + 1,
      'total': ranked.length,
      'isAggregate': true,
    };
  }

  Color _rankColor(int? rank) {
    if (rank == 1) return const Color(0xFFFFD700);
    if (rank == 2) return const Color(0xFFC0C0C0);
    if (rank == 3) return const Color(0xFFCD7F32);
    return kForegroundMuted;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: kSurface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(kRadius)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(kPadding, 4, kPadding, 8),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: kAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          widget.traineeName[0].toUpperCase(),
                          style: AppTypography.body.copyWith(color: kAccent, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.traineeName,
                              style: AppTypography.body.copyWith(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(
                            'Scores & rankings per activity',
                            style: AppTypography.caption
                                .copyWith(color: kForegroundMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: kForegroundMuted, size: 18),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Activity list
              Expanded(
                child: widget.parentActivities.isEmpty
                    ? Center(
                        child: Text(
                          'No activities for this role',
                          style: AppTypography.caption
                              .copyWith(color: kForegroundDisabled),
                        ),
                      )
                    : ListView(
                        controller: controller,
                        padding: const EdgeInsets.all(kPadding),
                        children: widget.parentActivities
                            .map(_buildActivityCard)
                            .toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> act) {
    final parentId = act['id'] as String;
    final subs = widget.subActivitiesMap[parentId] ?? [];
    final hasSubs = subs.isNotEmpty;

    Map<String, dynamic>? info;

    if (!hasSubs) {
      info = _directInfo(
        parentId,
        (act['scoring_direction'] ?? 'higher_is_better') as String,
      );
    } else {
      final selectedSubId = _selectedSubIds[parentId];
      if (selectedSubId == null) {
        info = _aggregateInfo(parentId, subs);
      } else {
        final sub = subs.firstWhere(
          (s) => s['id'] == selectedSubId,
          orElse: () => {},
        );
        if (sub.isNotEmpty) {
          info = _directInfo(
            selectedSubId,
            (sub['scoring_direction'] ?? 'higher_is_better') as String,
          );
        }
      }
    }

    final rank = info?['rank'] as int?;
    final score = info?['score'] as double?;
    final total = info?['total'] as int?;
    final isAggregate = (info?['isAggregate'] as bool?) ?? false;
    final rc = _rankColor(rank);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: rank != null && rank <= 3
          ? Border.all(color: rc.withValues(alpha: 0.35))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Activity name + rank badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.folder_outlined, size: 13, color: kForegroundMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  act['name'].toString(),
                  style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              if (rank != null)
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: rc.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: rc.withValues(alpha: 0.5)),
                  ),
                  child: Center(
                    child: Text(
                      '#$rank',
                      style: AppTypography.caption.copyWith(color: rc, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                )
              else
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: kSurfaceElevated,
                    shape: BoxShape.circle,
                    border: Border.all(color: kBorder.withValues(alpha: 0.4)),
                  ),
                  child: Center(
                    child: Text(
                      '–',
                      style: AppTypography.caption.copyWith(color: kForegroundDisabled, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),

          // Sub-activity dropdown
          if (hasSubs) ...[
            const SizedBox(height: 8),
            _buildSubDropdown(parentId, subs),
          ],

          const SizedBox(height: 8),

          // Score + rank pill
          if (score != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      score.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kAccent),
                    ),
                    Text(
                      isAggregate ? 'Avg score' : 'Score',
                      style: AppTypography.caption.copyWith(
                          color: kForegroundMuted, fontSize: 10),
                    ),
                  ],
                ),
                const Spacer(),
                if (rank != null && total != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: rc.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(kRadiusSmall),
                      border: Border.all(color: rc.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      'Rank #$rank of $total',
                      style: AppTypography.caption.copyWith(color: rc, fontSize: 11),
                    ),
                  ),
              ],
            )
          else
            Text(
              'No score recorded',
              style: AppTypography.caption.copyWith(color: kForegroundDisabled),
            ),
        ],
      ),
    );
  }

  Widget _buildSubDropdown(
      String parentId, List<Map<String, dynamic>> subs) {
    final selectedSubId = _selectedSubIds[parentId];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: kSurfaceElevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(kRadiusSmall),
        border: Border.all(color: kBorder.withValues(alpha: 0.5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selectedSubId,
          isExpanded: true,
          isDense: true,
          dropdownColor: kSurfaceElevated,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 13, color: kForegroundMuted),
          style: AppTypography.body.copyWith(fontSize: 11, color: kForeground),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'All sub-activities',
                style: AppTypography.body.copyWith(
                    fontSize: 11, color: kForegroundMuted),
              ),
            ),
            ...subs.map((sub) {
              final subId = sub['id'] as String;
              final hasScore =
                  widget.activityResultsMap.containsKey(subId);
              return DropdownMenuItem<String?>(
                value: subId,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        sub['name'].toString(),
                        style: AppTypography.body.copyWith(
                          fontSize: 11,
                          color: hasScore
                              ? kForeground
                              : kForegroundDisabled,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!hasScore) ...[
                      const SizedBox(width: 6),
                      Text(
                        'No scores',
                        style: AppTypography.caption.copyWith(
                            fontSize: 9, color: kForegroundDisabled),
                      ),
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
    );
  }
}
