import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Activities/create_activity_page.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Scoring/score_trainee_detail_page.dart';

class ScoreTraineesPage extends StatefulWidget {
  final String sessionId;
  final String activityId;
  final String activityName;
  final String? sessionName;
  final String? roleId;
  final String? roleName;

  const ScoreTraineesPage({
    super.key,
    required this.sessionId,
    required this.activityId,
    required this.activityName,
    this.sessionName,
    this.roleId,
    this.roleName,
  });

  @override
  State<ScoreTraineesPage> createState() => _ScoreTraineesPageState();
}

class _ScoreTraineesPageState extends State<ScoreTraineesPage> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _trainees = [];
  Map<String, Map<String, dynamic>> _resultsMap = {};
  final Map<String, TextEditingController> _scoreControllers = {};
  final Map<String, TextEditingController> _feedbackControllers = {};
  List<Map<String, dynamic>> _subActivities = [];
  bool _subExpanded = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    for (var controller in _scoreControllers.values) {
      controller.dispose();
    }
    for (var controller in _feedbackControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([_fetchTraineesAndResults(), _fetchSubActivities()]);
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error fetching data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      if (mounted) setState(() => _isLoading = false);
    }
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
      var query = supabase
          .from('session_trainees')
          .select('trainees!inner(*)')
          .eq('session_id', widget.sessionId);

      if (widget.roleId != null) {
        query = supabase
            .from('session_trainees')
            .select('trainees!inner(*, trainee_roles!inner(role_id))')
            .eq('session_id', widget.sessionId)
            .eq('trainees.trainee_roles.role_id', widget.roleId as Object);
      }

      traineesData = await query;
      cache.set(stKey, traineesData, ttl: const Duration(minutes: 3));
    }

    final traineesList = traineesData.map((m) => m['trainees'] as Map<String, dynamic>).toList();

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

    final Map<String, Map<String, dynamic>> resultsMap = {
      for (var r in resultsData) r['trainee_id']: r
    };

    setState(() {
      _trainees = traineesList;
      _resultsMap = resultsMap;
      for (var trainee in _trainees) {
        final id = trainee['id'] as String;
        final existing = resultsMap[id];

        _scoreControllers[id] = TextEditingController(
          text: (existing != null && existing['score'] != null) ? existing['score'].toString() : '',
        );
        _feedbackControllers[id] = TextEditingController(
          text: existing != null ? existing['feedback'] ?? '' : '',
        );
      }
    });
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

    setState(() {
      _subActivities = List<Map<String, dynamic>>.from(data);
    });
  }

  void _navigateToCreateSubActivity() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreateActivityPage(
          sessionId: widget.sessionId,
          parentId: widget.activityId,
          parentName: widget.activityName,
          inheritedRoleId: widget.roleId,
        ),
      ),
    );
    if (result == true) {
      _fetchData();
    }
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
            Text(widget.sessionName?.toUpperCase() ?? '', style: AppTypography.overline.copyWith(color: kForegroundMuted)),
            Text(widget.activityName, style: AppTypography.h3),
          ],
        ),
      ),
      body: Stack(
        children: [
          const TechnicalGridBackground(),
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: kAccent))
              : SafeArea(
                  child: SingleChildScrollView(
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
            if (_subActivities.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text('No sub-questions yet', style: AppTypography.caption),
                ),
              )
            else
              ..._subActivities.map((sub) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: kForegroundMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        sub['name'].toString(),
                        style: AppTypography.body.copyWith(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )),
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

    final gradedCount = _trainees.where((t) {
      final r = _resultsMap[t['id'] as String];
      return r != null && r['score'] != null;
    }).length;

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
                '$gradedCount / ${_trainees.length} graded',
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
        const SizedBox(height: 8),
        ..._trainees.map((t) => _buildTraineeScoringCard(t)),
      ],
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  void _openTraineeScoringSheet(Map<String, dynamic> trainee) {
    final id = trainee['id'] as String;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadius)),
      ),
      builder: (sheetContext) {
        return SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: kForegroundDisabled,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(kPadding, 20, kPadding, 0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: kAccent.withValues(alpha: 0.15),
                            child: Text(
                              _getInitials(trainee['full_name'].toString()),
                              style: TextStyle(color: kAccent, fontWeight: FontWeight.w700, fontSize: 18),
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
                                      style: TextStyle(color: kAccent, fontSize: 10, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: TextField(
                                    controller: _scoreControllers[id]!,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: AppTypography.h2.copyWith(fontSize: 22, color: kForeground),
                                    textAlign: TextAlign.center,
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
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text('FEEDBACK', style: AppTypography.label),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _feedbackControllers[id]!,
                            maxLines: 3,
                            style: AppTypography.body.copyWith(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Notes on performance or behavior...',
                              hintStyle: TextStyle(color: kForegroundDisabled.withValues(alpha: 0.5)),
                              filled: true,
                              fillColor: kSurfaceElevated.withValues(alpha: 0.5),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(height: 1, color: kBorder),
                    Padding(
                      padding: const EdgeInsets.all(kPadding),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(sheetContext).pop(),
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
                                onPressed: () {
                                  _saveSingleScore(id);
                                  Navigator.of(sheetContext).pop();
                                },
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: const Text('Save Score', style: TextStyle(fontWeight: FontWeight.w600)),
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
                    ),
                  ],
                ),
              );
    },
    );
  }

  Future<void> _saveSingleScore(String traineeId) async {
    try {
      final scoreText = _scoreControllers[traineeId]!.text.trim();
      final feedbackText = _feedbackControllers[traineeId]!.text.trim();

      if (scoreText.isNotEmpty) {
        final score = double.tryParse(scoreText);
        if (score != null) {
          await supabase.from('activity_results').upsert(
            {
              'activity_id': widget.activityId,
              'trainee_id': traineeId,
              'score': score,
              'feedback': feedbackText.isEmpty ? null : feedbackText,
            },
            onConflict: 'activity_id, trainee_id',
          );

          AppCache.instance.invalidate('results:${widget.activityId}');
          AppCache.instance.invalidate('result:${widget.activityId}:$traineeId');

          if (mounted) {
            setState(() {
              _resultsMap[traineeId] = {
                'activity_id': widget.activityId,
                'trainee_id': traineeId,
                'score': score,
                'feedback': feedbackText.isEmpty ? null : feedbackText,
                'updated_at': DateTime.now().toIso8601String(),
              };
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _openTraineeScoringFlow(Map<String, dynamic> trainee) {
    if (_subActivities.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ScoreTraineeDetailPage(
            sessionId: widget.sessionId,
            activityId: widget.activityId,
            activityName: widget.activityName,
            sessionName: widget.sessionName,
            roleName: widget.roleName,
            trainee: trainee,
            subActivities: _subActivities,
          ),
        ),
      );
    } else {
      _openTraineeScoringSheet(trainee);
    }
  }

  Widget _buildTraineeScoringCard(Map<String, dynamic> trainee) {
    final id = trainee['id'] as String;
    final result = _resultsMap[id];
    final isGraded = result != null && result['score'] != null;
    final score = isGraded ? result['score'] : null;

    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.zero,
      color: isGraded ? kAccent.withValues(alpha: 0.05) : kSurface,
      border: Border.all(
        color: isGraded ? kAccent.withValues(alpha: 0.25) : kBorder.withValues(alpha: 0.5),
      ),
      child: InkWell(
        onTap: () => _openTraineeScoringFlow(trainee),
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
                  color: isGraded ? kAccent.withValues(alpha: 0.12) : kSurfaceElevated,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isGraded ? kAccent.withValues(alpha: 0.35) : kBorder.withValues(alpha: 0.5),
                  ),
                ),
                child: Center(
                  child: isGraded
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
                    const SizedBox(height: 3),
                    if (isGraded)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: kAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Graded',
                          style: TextStyle(color: kAccent, fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      )
                    else if (trainee['email'] != null)
                      Text(
                        trainee['email'],
                        style: AppTypography.caption.copyWith(fontSize: 10),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (isGraded)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      score.toString(),
                      style: AppTypography.h2.copyWith(fontSize: 22, color: kAccent),
                    ),
                    Text(
                      'pts',
                      style: AppTypography.caption.copyWith(fontSize: 10, color: kAccent.withValues(alpha: 0.6)),
                    ),
                  ],
                )
              else
                const Icon(Icons.chevron_right_rounded, size: 18, color: kForegroundDisabled),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          Icon(Icons.person_off_rounded, size: 48, color: kForegroundDisabled),
          const SizedBox(height: 12),
          Text(
            'No members matched',
            style: AppTypography.h3.copyWith(color: kForegroundMuted, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'No trainees with the ${widget.roleName ?? "selected"} role are assigned to this session.',
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(fontSize: 11),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
