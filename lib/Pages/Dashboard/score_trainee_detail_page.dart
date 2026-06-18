import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class ScoreTraineeDetailPage extends StatefulWidget {
  final String sessionId;
  final String activityId;
  final String activityName;
  final String? sessionName;
  final String? roleName;
  final Map<String, dynamic> trainee;
  final List<Map<String, dynamic>> subActivities;

  const ScoreTraineeDetailPage({
    super.key,
    required this.sessionId,
    required this.activityId,
    required this.activityName,
    this.sessionName,
    this.roleName,
    required this.trainee,
    required this.subActivities,
  });

  @override
  State<ScoreTraineeDetailPage> createState() => _ScoreTraineeDetailPageState();
}

class _ScoreTraineeDetailPageState extends State<ScoreTraineeDetailPage> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isSaving = false;

  TextEditingController? _scoreController;
  TextEditingController? _feedbackController;
  final Map<String, TextEditingController> _subScoreControllers = {};
  final Map<String, TextEditingController> _subFeedbackControllers = {};

  @override
  void initState() {
    super.initState();
    _fetchResults();
  }

  @override
  void dispose() {
    _scoreController?.dispose();
    _feedbackController?.dispose();
    for (var c in _subScoreControllers.values) {
      c.dispose();
    }
    for (var c in _subFeedbackControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchResults() async {
    try {
      final traineeId = widget.trainee['id'] as String;

      final mainResult = await supabase
          .from('activity_results')
          .select()
          .eq('activity_id', widget.activityId)
          .eq('trainee_id', traineeId)
          .maybeSingle();

      final subIds = widget.subActivities.map((a) => a['id'] as String).toList();
      List<Map<String, dynamic>> subResults = [];
      if (subIds.isNotEmpty) {
        final data = await supabase
            .from('activity_results')
            .select()
            .inFilter('activity_id', subIds)
            .eq('trainee_id', traineeId);
        subResults = List<Map<String, dynamic>>.from(data);
      }

      final Map<String, Map<String, dynamic>> subResultsMap = {
        for (var r in subResults) r['activity_id'].toString(): r,
      };

      setState(() {
        _scoreController = TextEditingController(
          text: mainResult != null && mainResult['score'] != null ? mainResult['score'].toString() : '',
        );
        _feedbackController = TextEditingController(
          text: mainResult != null ? mainResult['feedback'] ?? '' : '',
        );

        for (var sub in widget.subActivities) {
          final sid = sub['id'] as String;
          final existing = subResultsMap[sid];
          _subScoreControllers[sid] = TextEditingController(
            text: existing != null && existing['score'] != null ? existing['score'].toString() : '',
          );
          _subFeedbackControllers[sid] = TextEditingController(
            text: existing != null ? existing['feedback'] ?? '' : '',
          );
        }

        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching results: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final traineeId = widget.trainee['id'] as String;

      final scoreText = _scoreController!.text.trim();
      final feedbackText = _feedbackController!.text.trim();
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
        }
      }

      for (var sub in widget.subActivities) {
        final sid = sub['id'] as String;
        final subScoreText = _subScoreControllers[sid]!.text.trim();
        final subFeedbackText = _subFeedbackControllers[sid]!.text.trim();

        if (subScoreText.isNotEmpty) {
          final score = double.tryParse(subScoreText);
          if (score != null) {
            await supabase.from('activity_results').upsert(
              {
                'activity_id': sid,
                'trainee_id': traineeId,
                'score': score,
                'feedback': subFeedbackText.isEmpty ? null : subFeedbackText,
              },
              onConflict: 'activity_id, trainee_id',
            );
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.sessionName != null)
              Text(widget.sessionName!.toUpperCase(), style: AppTypography.overline.copyWith(color: kForegroundMuted)),
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
                        _buildHeader(),
                        const SizedBox(height: 20),
                        _buildMainScoring(),
                        if (widget.subActivities.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _buildSubScoring(),
                        ],
                        const SizedBox(height: 32),
                        _buildSaveButton(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: kAccent.withValues(alpha: 0.15),
            child: Text(
              _getInitials(widget.trainee['full_name'].toString()),
              style: TextStyle(color: kAccent, fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.trainee['full_name'].toString(), style: AppTypography.h3.copyWith(fontSize: 18)),
                const SizedBox(height: 2),
                Text(widget.activityName, style: AppTypography.caption.copyWith(fontSize: 11, color: kForegroundMuted)),
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
    );
  }

  Widget _buildMainScoring() {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('OVERALL SCORE', style: AppTypography.label),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SizedBox(
              height: 56,
              child: TextField(
                controller: _scoreController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: AppTypography.h2.copyWith(fontSize: 28, color: kForeground),
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
          const SizedBox(height: 20),
          Text('FEEDBACK', style: AppTypography.label),
          const SizedBox(height: 8),
          TextField(
            controller: _feedbackController,
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
    );
  }

  Widget _buildSubScoring() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SUB-QUESTIONS', style: AppTypography.label),
        const SizedBox(height: 8),
        ...widget.subActivities.map((sub) {
          final sid = sub['id'] as String;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: kAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          sub['name'].toString(),
                          style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: TextField(
                            controller: _subScoreControllers[sid],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: AppTypography.h2.copyWith(fontSize: 18),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              hintText: '0',
                              hintStyle: TextStyle(color: kForegroundDisabled.withValues(alpha: 0.5)),
                              filled: true,
                              fillColor: kSurfaceElevated.withValues(alpha: 0.5),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(kRadiusSmall),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(kRadiusSmall),
                                borderSide: BorderSide(color: kBorder.withValues(alpha: 0.3)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(kRadiusSmall),
                                borderSide: const BorderSide(color: kAccent),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 44,
                          child: TextField(
                            controller: _subFeedbackControllers[sid],
                            maxLines: 2,
                            style: AppTypography.body.copyWith(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'Feedback...',
                              hintStyle: TextStyle(color: kForegroundDisabled.withValues(alpha: 0.5), fontSize: 12),
                              filled: true,
                              fillColor: kSurfaceElevated.withValues(alpha: 0.5),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(kRadiusSmall),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(kRadiusSmall),
                                borderSide: BorderSide(color: kBorder.withValues(alpha: 0.3)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(kRadiusSmall),
                                borderSide: const BorderSide(color: kAccent),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _save,
        icon: _isSaving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.check_rounded, size: 18),
        label: Text(_isSaving ? 'Saving...' : 'Save Score', style: const TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: kAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusLarge)),
          elevation: 0,
        ),
      ),
    );
  }
}
