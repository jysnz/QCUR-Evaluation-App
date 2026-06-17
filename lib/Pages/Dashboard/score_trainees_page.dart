import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class ScoreTraineesPage extends StatefulWidget {
  final String sessionId;
  final String activityId;
  final String activityName;
  final String? roleId;
  final String? roleName;

  const ScoreTraineesPage({
    super.key,
    required this.sessionId,
    required this.activityId,
    required this.activityName,
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
  Map<String, TextEditingController> _scoreControllers = {};
  Map<String, TextEditingController> _feedbackControllers = {};

  @override
  void initState() {
    super.initState();
    _fetchTraineesAndResults();
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

  Future<void> _fetchTraineesAndResults() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch trainees in this session
      var query = supabase
          .from('session_trainees')
          .select('trainees!inner(*)')
          .eq('session_id', widget.sessionId);
      
      // If a specific role is required, filter by it using the join table
      if (widget.roleId != null) {
        query = supabase
            .from('session_trainees')
            .select('trainees!inner(*, trainee_roles!inner(role_id))')
            .eq('session_id', widget.sessionId)
            .eq('trainees.trainee_roles.role_id', widget.roleId as Object);
      }

      final traineesData = await query;
      final traineesList = traineesData.map((m) => m['trainees'] as Map<String, dynamic>).toList();

      // 2. Fetch existing results for this activity
      final resultsData = await supabase
          .from('activity_results')
          .select()
          .eq('activity_id', widget.activityId);

      final Map<String, Map<String, dynamic>> resultsMap = {
        for (var r in resultsData) r['trainee_id']: r
      };

      setState(() {
        _trainees = traineesList;
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
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching scoring data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveScores() async {
    setState(() => _isLoading = true);
    try {
      final List<Map<String, dynamic>> upsertData = [];

      for (var trainee in _trainees) {
        final id = trainee['id'] as String;
        final scoreText = _scoreControllers[id]!.text.trim();
        final feedbackText = _feedbackControllers[id]!.text.trim();

        if (scoreText.isNotEmpty) {
          final score = double.tryParse(scoreText);
          if (score != null) {
            upsertData.add({
              'activity_id': widget.activityId,
              'trainee_id': id,
              'score': score,
              'feedback': feedbackText.isEmpty ? null : feedbackText,
            });
          }
        }
      }

      if (upsertData.isNotEmpty) {
        await supabase.from('activity_results').upsert(
          upsertData,
          onConflict: 'activity_id, trainee_id',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Evaluation results synchronized.')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving scores: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
            Text('Assess Members', style: AppTypography.label),
            Text(widget.activityName, style: AppTypography.h3),
          ],
        ),
      ),
      body: AppBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: kAccent))
            : _trainees.isEmpty
                ? _buildEmptyState()
                : Column(
                    children: [
                      _buildHeader(),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(kPadding),
                          itemCount: _trainees.length,
                          itemBuilder: (context, index) {
                            return _buildTraineeScoringCard(_trainees[index]);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(kPaddingLarge),
                        child: AppButton(
                          label: 'Sync Results',
                          icon: Icons.sync_rounded,
                          onTap: _saveScores,
                          isLoading: _isLoading,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: kSurfaceElevated.withValues(alpha: 0.5),
        border: const Border(bottom: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          const Icon(Icons.psychology_rounded, size: 16, color: kAccent),
          const SizedBox(width: 8),
          Text(
            'Position: ${widget.roleName ?? "Manual selection"}',
            style: AppTypography.label.copyWith(color: kAccent),
          ),
          const Spacer(),
          Text(
            '${_trainees.length} members found',
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }

  Widget _buildTraineeScoringCard(Map<String, dynamic> trainee) {
    final id = trainee['id'] as String;

    return AppCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_outline_rounded, color: kAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trainee['full_name'].toString(), style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.bold)),
                    if (trainee['email'] != null)
                      Text(trainee['email'], style: AppTypography.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: AppTextField(
                  label: 'Score',
                  hint: '0.00',
                  controller: _scoreControllers[id]!,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                flex: 3,
                child: SizedBox(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Feedback',
            hint: 'Notes on performance or behavior...',
            controller: _feedbackControllers[id]!,
            maxLines: 2,
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
          Icon(Icons.person_off_rounded, size: 64, color: kForegroundDisabled),
          const SizedBox(height: 16),
          Text(
            'No members matched',
            style: AppTypography.h3.copyWith(color: kForegroundMuted),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'No trainees with the ${widget.roleName ?? "selected"} role are assigned to this session.',
              textAlign: TextAlign.center,
              style: AppTypography.caption,
            ),
          ),
          const SizedBox(height: 24),
          AppButton(
            label: 'Go Back',
            isFullWidth: false,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
