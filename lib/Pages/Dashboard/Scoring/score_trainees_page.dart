import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Activities/create_activity_page.dart';

class ScoreTraineesPage extends StatefulWidget {
  final String sessionId;
  final String activityId;
  final String activityName;
  final String? sessionName;
  final String? roleId;
  final String? roleName;
  final String? highlightedSubId;

  const ScoreTraineesPage({
    super.key,
    required this.sessionId,
    required this.activityId,
    required this.activityName,
    this.sessionName,
    this.roleId,
    this.roleName,
    this.highlightedSubId,
  });

  @override
  State<ScoreTraineesPage> createState() => _ScoreTraineesPageState();
}

class _ScoreTraineesPageState extends State<ScoreTraineesPage> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _trainees = [];

  // Single-score activities (no sub-activities)
  Map<String, Map<String, dynamic>> _resultsMap = {};
  final Map<String, TextEditingController> _scoreControllers = {};

  // Sub-activity activities: "${subId}:${traineeId}" → result
  Map<String, Map<String, dynamic>> _subResultsMap = {};
  // traineeId → subId → controller
  final Map<String, Map<String, TextEditingController>> _subScoreControllers = {};

  List<Map<String, dynamic>> _subActivities = [];
  bool _subExpanded = true;
  String _searchQuery = '';
  String? _currentUserName;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _fetchData();
  }

  Future<void> _loadCurrentUser() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final cacheKey = 'user:${user.id}';
    final cached = AppCache.instance.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) {
      if (mounted) setState(() => _currentUserName = cached['full_name']?.toString() ?? user.email ?? 'Another user');
      return;
    }
    try {
      final data = await supabase.from('user_accounts').select('full_name').eq('id', user.id).single();
      AppCache.instance.set(cacheKey, data);
      if (mounted) setState(() => _currentUserName = data['full_name']?.toString() ?? user.email ?? 'Another user');
    } catch (_) {
      if (mounted) setState(() => _currentUserName = user.email ?? 'Another user');
    }
  }

  @override
  void dispose() {
    for (final c in _scoreControllers.values) { c.dispose(); }
    for (final sub in _subScoreControllers.values) {
      for (final c in sub.values) { c.dispose(); }
    }
    super.dispose();
  }

  Future<void> _refreshData() async {
    final cache = AppCache.instance;
    cache.invalidate('subs:${widget.activityId}');
    cache.invalidate('results:${widget.activityId}');
    final stKey = widget.roleId != null
        ? 'st:${widget.sessionId}:${widget.roleId}'
        : 'st:${widget.sessionId}';
    cache.invalidate(stKey);
    await _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // Sequential: subs must be known before trainees+results are initialised.
      await _fetchSubActivities();
      await _fetchTraineesAndResults();
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error fetching data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchSubActivities() async {
    final subsKey = 'subs:${widget.activityId}';
    final cached = AppCache.instance.get<List<dynamic>>(subsKey);
    final data = cached ??
        await supabase
            .from('activities')
            .select('*')
            .eq('parent_id', widget.activityId)
            .order('order_index');
    if (cached == null) AppCache.instance.set(subsKey, data);
    setState(() => _subActivities = List<Map<String, dynamic>>.from(data));
  }

  Future<void> _fetchTraineesAndResults() async {
    final cache = AppCache.instance;
    final stKey = widget.roleId != null
        ? 'st:${widget.sessionId}:${widget.roleId}'
        : 'st:${widget.sessionId}';

    final cachedSt = cache.get<List<dynamic>>(stKey);
    List<dynamic> traineesData;
    if (cachedSt != null) {
      traineesData = cachedSt;
    } else {
      if (widget.roleId != null) {
        final roleRows = await supabase
            .from('trainee_roles')
            .select('trainee_id')
            .eq('role_id', widget.roleId!);

        final idsWithRole = (roleRows as List)
            .map((r) => r['trainee_id'] as String)
            .toList();

        if (idsWithRole.isEmpty) {
          traineesData = [];
        } else {
          traineesData = await supabase
              .from('session_trainees')
              .select('trainees!inner(*)')
              .eq('session_id', widget.sessionId)
              .inFilter('trainee_id', idsWithRole);
        }
      } else {
        traineesData = await supabase
            .from('session_trainees')
            .select('trainees!inner(*)')
            .eq('session_id', widget.sessionId);
      }
      cache.set(stKey, traineesData, ttl: const Duration(minutes: 3));
    }

    final traineesList = traineesData
        .map((m) => m['trainees'] as Map<String, dynamic>)
        .toList();

    // --- Single-score results (used when no sub-activities) ---
    final resultsKey = 'results:${widget.activityId}';
    final cachedResults = cache.get<List<dynamic>>(resultsKey);
    final resultsData = cachedResults ??
        await supabase
            .from('activity_results')
            .select()
            .eq('activity_id', widget.activityId);
    if (cachedResults == null) {
      cache.set(resultsKey, resultsData, ttl: const Duration(minutes: 2));
    }
    final resultsMap = <String, Map<String, dynamic>>{
      for (final r in resultsData) r['trainee_id']: r,
    };

    // --- Sub-activity results (used when sub-activities exist) ---
    final newSubResultsMap = <String, Map<String, dynamic>>{};
    if (_subActivities.isNotEmpty) {
      final subIds = _subActivities.map((s) => s['id'] as String).toList();
      final subResultsData = await supabase
          .from('activity_results')
          .select()
          .inFilter('activity_id', subIds);
      for (final r in subResultsData as List) {
        newSubResultsMap['${r['activity_id']}:${r['trainee_id']}'] = r;
      }
    }

    setState(() {
      _trainees = traineesList;
      _resultsMap = resultsMap;
      _subResultsMap = newSubResultsMap;

      for (final trainee in _trainees) {
        final id = trainee['id'] as String;

        // Single-score controllers
        final existing = resultsMap[id];
        _scoreControllers[id] ??= TextEditingController();
        _scoreControllers[id]!.text =
            (existing != null && existing['score'] != null) ? existing['score'].toString() : '';

        // Sub-score controllers
        if (_subActivities.isNotEmpty) {
          _subScoreControllers[id] ??= {};
          for (final sub in _subActivities) {
            final subId = sub['id'] as String;
            final subResult = newSubResultsMap['$subId:$id'];
            _subScoreControllers[id]![subId] ??= TextEditingController();
            _subScoreControllers[id]![subId]!.text =
                (subResult != null && subResult['score'] != null) ? subResult['score'].toString() : '';
          }
        }
      }
    });
  }

  // ---------- Scoring state helpers ----------

  bool _isTraineeScored(String traineeId) {
    if (_subActivities.isEmpty) {
      final r = _resultsMap[traineeId];
      return r != null && r['score'] != null;
    }
    return _subActivities.every((sub) {
      final r = _subResultsMap['${sub['id']}:$traineeId'];
      return r != null && r['score'] != null;
    });
  }

  int _scoredSubCount(String traineeId) => _subActivities.where((sub) {
        final r = _subResultsMap['${sub['id']}:$traineeId'];
        return r != null && r['score'] != null;
      }).length;

  // ---------- Save ----------

  Future<void> _saveSingleScore(String traineeId) async {
    try {
      final scoreText = _scoreControllers[traineeId]!.text.trim();
      if (scoreText.isEmpty) return;
      final score = double.tryParse(scoreText);
      if (score == null) return;

      await supabase.from('activity_results').upsert(
        {
          'activity_id': widget.activityId,
          'trainee_id': traineeId,
          'score': score,
        },
        onConflict: 'activity_id, trainee_id',
      );

      AppCache.instance.invalidate('results:${widget.activityId}');

      if (mounted) {
        setState(() {
          _resultsMap[traineeId] = {
            'activity_id': widget.activityId,
            'trainee_id': traineeId,
            'score': score,
            'updated_at': DateTime.now().toIso8601String(),
          };
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _saveAllSubScores(String traineeId) async {
    try {
      final upserts = <Map<String, dynamic>>[];
      for (final sub in _subActivities) {
        final subId = sub['id'] as String;
        final scoreText = _subScoreControllers[traineeId]?[subId]?.text.trim() ?? '';
        if (scoreText.isNotEmpty) {
          final score = double.tryParse(scoreText);
          if (score != null) {
            upserts.add({
              'activity_id': subId,
              'trainee_id': traineeId,
              'score': score,
            });
          }
        }
      }

      if (upserts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter at least one score to save')),
          );
        }
        return;
      }

      await supabase.from('activity_results').upsert(
        upserts,
        onConflict: 'activity_id, trainee_id',
      );

      for (final sub in _subActivities) {
        AppCache.instance.invalidate('results:${sub['id']}');
      }

      if (mounted) {
        setState(() {
          for (final u in upserts) {
            _subResultsMap['${u['activity_id']}:$traineeId'] = {
              ...u,
              'updated_at': DateTime.now().toIso8601String(),
            };
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ---------- Bottom sheets ----------

  Future<void> _openTraineeScoringSheet(Map<String, dynamic> trainee) async {
    final traineeId = trainee['id'] as String;
    final currentUserId = supabase.auth.currentUser?.id ?? '';
    final currentUserName = _currentUserName ?? 'Another user';

    try {
      // Check if another user already has this trainee locked for scoring.
      final existing = await supabase
          .from('scoring_locks')
          .select()
          .eq('activity_id', widget.activityId)
          .eq('trainee_id', traineeId)
          .maybeSingle();

      final bool lockedByOther = existing != null &&
          existing['user_id'] != currentUserId &&
          DateTime.now().toUtc().difference(
                DateTime.parse(existing['locked_at'] as String).toUtc(),
              ).inMinutes <
              10;

      if (lockedByOther) {
        // Active lock held by someone else — show blocking dialog.
        final otherName = existing['user_name'] as String? ?? 'Another user';
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: kSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: kWarning, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('Currently being scored', style: AppTypography.h3)),
              ],
            ),
            content: Text(
              '${trainee['full_name']} is currently being scored by $otherName. Please wait until they\'re done.',
              style: AppTypography.body,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('OK', style: TextStyle(color: kAccent, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
        return;
      }

      // Acquire (or refresh own stale) lock via upsert.
      await supabase.from('scoring_locks').upsert(
        {
          'activity_id': widget.activityId,
          'trainee_id': traineeId,
          'user_id': currentUserId,
          'user_name': currentUserName,
          'locked_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'activity_id, trainee_id',
      );

      if (_subActivities.isNotEmpty) {
        await _openSubScoringSheet(trainee);
      } else {
        await _openSingleScoringSheet(trainee);
      }
    } finally {
      // Always release the lock when the sheet closes or on any error.
      try {
        await supabase
            .from('scoring_locks')
            .delete()
            .eq('activity_id', widget.activityId)
            .eq('trainee_id', traineeId)
            .eq('user_id', currentUserId);
      } catch (_) {}
    }
  }

  Future<void> _openSingleScoringSheet(Map<String, dynamic> trainee) async {
    final id = trainee['id'] as String;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadius)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSheetHandle(),
              _buildSheetHeader(trainee),
              const SizedBox(height: 16),
              const Divider(height: 1, color: kBorder),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SCORE', style: AppTypography.label),
                    const SizedBox(height: 8),
                    _buildScoreField(_scoreControllers[id]!),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Divider(height: 1, color: kBorder),
              _buildSheetActions(
                sheetCtx: sheetCtx,
                onSave: () {
                  _saveSingleScore(id);
                  Navigator.of(sheetCtx).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSubScoringSheet(Map<String, dynamic> trainee) async {
    final id = trainee['id'] as String;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadius)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSheetHandle(),
              _buildSheetHeader(trainee),
              const SizedBox(height: 16),
              const Divider(height: 1, color: kBorder),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < _subActivities.length; i++) ...[
                      if (i > 0) ...[
                        const SizedBox(height: 4),
                        const Divider(height: 1, color: kBorder),
                        const SizedBox(height: 12),
                      ],
                      _buildSubScoreRow(
                        index: i,
                        sub: _subActivities[i],
                        traineeId: id,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Divider(height: 1, color: kBorder),
              _buildSheetActions(
                sheetCtx: sheetCtx,
                saveLabel: 'Save All',
                onSave: () {
                  _saveAllSubScores(id);
                  Navigator.of(sheetCtx).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Shared sheet widgets ----------

  Widget _buildSheetHandle() => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: kForegroundDisabled,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _buildSheetHeader(Map<String, dynamic> trainee) => Padding(
        padding: const EdgeInsets.fromLTRB(kPadding, 20, kPadding, 0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: kAccent.withValues(alpha: 0.15),
              child: Text(
                _getInitials(trainee['full_name'].toString()),
                style: const TextStyle(color: kAccent, fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trainee['full_name'].toString(), style: AppTypography.h3.copyWith(fontSize: 18)),
                  const SizedBox(height: 2),
                  Text(
                    widget.activityName,
                    style: AppTypography.caption.copyWith(fontSize: 11, color: kForegroundMuted),
                  ),
                  if (widget.roleName != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: kAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.roleName!,
                        style: const TextStyle(color: kAccent, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildSubScoreRow({
    required int index,
    required Map<String, dynamic> sub,
    required String traineeId,
  }) {
    final subId = sub['id'] as String;
    final result = _subResultsMap['$subId:$traineeId'];
    final isScored = result != null && result['score'] != null;
    final isHighlighted = subId == widget.highlightedSubId;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isHighlighted
                    ? kAccent.withValues(alpha: 0.2)
                    : isScored
                        ? kAccent.withValues(alpha: 0.12)
                        : kSurfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isHighlighted
                      ? kAccent.withValues(alpha: 0.7)
                      : isScored
                          ? kAccent.withValues(alpha: 0.4)
                          : kBorder.withValues(alpha: 0.5),
                ),
              ),
              child: Center(
                child: isScored
                    ? const Icon(Icons.check_rounded, size: 12, color: kAccent)
                    : Text(
                        '${index + 1}',
                        style: AppTypography.caption.copyWith(
                          color: isHighlighted ? kAccent : kForegroundMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                sub['name'].toString(),
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: isHighlighted ? kAccent : kForeground,
                ),
              ),
            ),
            if (isHighlighted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Selected',
                  style: TextStyle(color: kAccent, fontSize: 9, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _buildScoreField(_subScoreControllers[traineeId]![subId]!),
      ],
    );

    if (!isHighlighted) return content;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(kRadiusSmall),
        border: Border.all(color: kAccent.withValues(alpha: 0.3)),
      ),
      child: content,
    );
  }

  Widget _buildScoreField(TextEditingController controller) => SizedBox(
        height: 48,
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTypography.h2.copyWith(fontSize: 22, color: kForeground),
          textAlign: TextAlign.start,
          decoration: InputDecoration(
            hintText: '0',
            hintStyle: TextStyle(color: kForegroundDisabled.withValues(alpha: 0.5)),
            filled: true,
            fillColor: kSurfaceElevated.withValues(alpha: 0.5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadiusSmall),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadiusSmall),
              borderSide: BorderSide(color: kBorder.withValues(alpha: 0.3), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadiusSmall),
              borderSide: const BorderSide(color: kAccent, width: 1.5),
            ),
          ),
        ),
      );

  Widget _buildSheetActions({
    required BuildContext sheetCtx,
    required VoidCallback onSave,
    String saveLabel = 'Save Score',
  }) =>
      Padding(
        padding: const EdgeInsets.all(kPadding),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(sheetCtx).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kForegroundMuted,
                    side: BorderSide(color: kBorder.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusLarge)),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(saveLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusLarge)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  // ---------- Sub-activity navigation ----------

  void _navigateToCreateSubActivity() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateActivityPage(
          sessionId: widget.sessionId,
          parentId: widget.activityId,
          parentName: widget.activityName,
          inheritedRoleId: widget.roleId,
        ),
      ),
    );
    if (result == true) _fetchData();
  }

  // ---------- Build ----------

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
            Text(widget.sessionName?.toUpperCase() ?? '', style: AppTypography.overline.copyWith(color: kForegroundMuted)),
            Text(widget.activityName, style: AppTypography.h3),
          ],
        ),
      ),
      body: Stack(
        children: [
          const TechnicalGridBackground(),
          _isLoading
              ? const AppLoader()
              : SafeArea(
                  child: RefreshIndicator(
                    onRefresh: _refreshData,
                    color: kAccent,
                    backgroundColor: kSurfaceElevated,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(kPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_subActivities.isNotEmpty) ...[
                            _buildSubActivitiesSection(),
                            const SizedBox(height: 16),
                          ],
                          _buildScoringSection(),
                        ],
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildSubActivitiesSection() {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _subExpanded = !_subExpanded),
            borderRadius: BorderRadius.circular(kRadius),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _subExpanded ? 0.0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more, size: 18, color: kAccent),
                ),
                const SizedBox(width: 8),
                Text('Sub-questions', style: AppTypography.h3.copyWith(fontSize: 15)),
                const Spacer(),
                Text('${_subActivities.length}', style: AppTypography.caption),
              ],
            ),
          ),
          if (_subExpanded) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: kBorder),
            const SizedBox(height: 8),
            ..._subActivities.asMap().entries.map((e) {
              final i = e.key;
              final sub = e.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(
                    color: kSurfaceElevated.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(kRadiusSmall),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: kAccent.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(color: kAccent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          sub['name'].toString(),
                          style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _navigateToCreateSubActivity,
                icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                label: const Text('Add Sub-question'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kAccent,
                  side: BorderSide(color: kAccent.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSmall)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScoringSection() {
    if (_trainees.isEmpty) return _buildEmptyState();

    final filtered = _searchQuery.isEmpty
        ? _trainees
        : _trainees
            .where((t) => t['full_name']
                .toString()
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()))
            .toList();

    final scoredCount = _trainees.where((t) => _isTraineeScored(t['id'] as String)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Members', style: AppTypography.h3.copyWith(fontSize: 15)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: kAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$scoredCount / ${_trainees.length} scored',
                style: const TextStyle(color: kAccent, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        if (widget.roleName != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: kSurfaceElevated.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(kRadiusSmall),
              border: Border.all(color: kBorder.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.psychology_rounded, size: 13, color: kAccent),
                const SizedBox(width: 6),
                Text(widget.roleName!, style: AppTypography.label.copyWith(color: kAccent, fontSize: 11)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            style: AppTypography.body.copyWith(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search trainees...',
              hintStyle: AppTypography.label.copyWith(color: kForegroundDisabled),
              icon: const Icon(Icons.search_rounded, color: kAccent, size: 18),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No trainees match "$_searchQuery"',
                style: AppTypography.caption.copyWith(color: kForegroundDisabled),
              ),
            ),
          )
        else
          ...filtered.map(_buildTraineeScoringCard),
      ],
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Widget _buildTraineeScoringCard(Map<String, dynamic> trainee) {
    final id = trainee['id'] as String;
    final hasSubs = _subActivities.isNotEmpty;
    final isScored = _isTraineeScored(id);

    // --- Trailing widget ---
    Widget trailing;
    if (hasSubs) {
      if (isScored) {
        trailing = _scoreBadge('Scored', kAccent);
      } else {
        final count = _scoredSubCount(id);
        trailing = count > 0
            ? _scoreBadge('$count / ${_subActivities.length}', kWarning)
            : const Icon(Icons.chevron_right_rounded, size: 18, color: kForegroundDisabled);
      }
    } else {
      final result = _resultsMap[id];
      final singleScored = result != null && result['score'] != null;
      if (singleScored) {
        trailing = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              result['score'].toString(),
              style: AppTypography.statValue.copyWith(fontSize: 22, color: kAccent),
            ),
            Text('pts', style: AppTypography.caption.copyWith(fontSize: 10, color: kAccent.withValues(alpha: 0.6))),
          ],
        );
      } else {
        trailing = const Icon(Icons.chevron_right_rounded, size: 18, color: kForegroundDisabled);
      }
    }

    // --- Subtitle ---
    Widget? subtitle;
    if (hasSubs) {
      if (isScored) {
        subtitle = _inlineBadge('Scored', kAccent);
      } else {
        final count = _scoredSubCount(id);
        if (count > 0) {
          subtitle = Text(
            '$count of ${_subActivities.length} sub-activities scored',
            style: AppTypography.caption.copyWith(fontSize: 10, color: kWarning),
          );
        } else if (trainee['email'] != null) {
          subtitle = Text(trainee['email'], style: AppTypography.caption.copyWith(fontSize: 10));
        }
      }
    } else {
      final result = _resultsMap[id];
      final singleScored = result != null && result['score'] != null;
      if (singleScored) {
        subtitle = _inlineBadge('Graded', kAccent);
      } else if (trainee['email'] != null) {
        subtitle = Text(trainee['email'], style: AppTypography.caption.copyWith(fontSize: 10));
      }
    }

    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.zero,
      color: isScored ? kAccent.withValues(alpha: 0.05) : kSurface,
      border: Border.all(
        color: isScored ? kAccent.withValues(alpha: 0.25) : kBorder.withValues(alpha: 0.5),
      ),
      child: InkWell(
        onTap: () => _openTraineeScoringSheet(trainee),
        borderRadius: BorderRadius.circular(kRadius),
        splashColor: kAccent.withValues(alpha: 0.08),
        highlightColor: kAccent.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isScored ? kAccent.withValues(alpha: 0.12) : kSurfaceElevated,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isScored ? kAccent.withValues(alpha: 0.35) : kBorder.withValues(alpha: 0.5),
                  ),
                ),
                child: Center(
                  child: isScored
                      ? const Icon(Icons.check_rounded, color: kAccent, size: 18)
                      : Text(
                          _getInitials(trainee['full_name'].toString()),
                          style: const TextStyle(color: kForegroundMuted, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trainee['full_name'].toString(),
                      style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      subtitle,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _scoreBadge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(kRadiusSmall),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      );

  Widget _inlineBadge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
      );

  Widget _buildEmptyState() => AppEmptyState(
        icon: Icons.person_off_rounded,
        title: 'No members matched',
        message: 'No trainees with the ${widget.roleName ?? "selected"} role are assigned to this session.',
      );
}
