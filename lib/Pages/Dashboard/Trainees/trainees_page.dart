import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class TraineesPage extends StatefulWidget {
  const TraineesPage({super.key});

  @override
  State<TraineesPage> createState() => _TraineesPageState();
}

class _TraineesPageState extends State<TraineesPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _trainees = [];
  List<Map<String, dynamic>> _sessions = [];
  Map<String, List<Map<String, dynamic>>> _sessionTraineeMap = {};
  bool _isLoading = true;
  String _searchQuery = '';
  String? _roleFilter;
  List<Map<String, dynamic>> _availableRoles = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
    _fetchRoles();
  }

  Future<void> _fetchRoles() async {
    try {
      final data = await supabase.from('roles').select().order('name');
      setState(() {
        _availableRoles = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      debugPrint('Error fetching roles: $e');
    }
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([_fetchTrainees(), _fetchSessions()]);
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchTrainees() async {
    final data = await supabase
        .from('trainees')
        .select()
        .order('full_name');
    _trainees = List<Map<String, dynamic>>.from(data);
  }

  Future<void> _fetchSessions() async {
    final sessionsData = await supabase
        .from('training_sessions')
        .select()
        .order('date', ascending: false);

    final assignmentsData = await supabase
        .from('session_trainees')
        .select();

    _sessions = List<Map<String, dynamic>>.from(sessionsData);

    final Map<String, List<Map<String, dynamic>>> map = {};
    final assignedIds = <String>{};

    for (var assignment in assignmentsData) {
      final sessionId = assignment['session_id'] as String;
      final traineeId = assignment['trainee_id'] as String;
      assignedIds.add(traineeId);

      final trainee = _trainees.cast<Map<String, dynamic>?>().firstWhere(
        (t) => t?['id'] == traineeId,
        orElse: () => null,
      );
      if (trainee != null) {
        map.putIfAbsent(sessionId, () => []).add(trainee);
      }
    }

    final unassigned = _trainees.where((t) => !assignedIds.contains(t['id'])).toList();
    if (unassigned.isNotEmpty) {
      map['unassigned'] = unassigned;
    }

    _sessionTraineeMap = map;
  }

  List<Map<String, dynamic>> _getSessionListItems() {
    final items = <Map<String, dynamic>>[];

    for (var session in _sessions) {
      final sid = session['id'] as String;
      final trainees = _sessionTraineeMap[sid];
      if (trainees == null || trainees.isEmpty) continue;

      final filtered = trainees.where((t) {
        final matchesSearch = t['full_name']
            .toString()
            .toLowerCase()
            .contains(_searchQuery.toLowerCase());
        if (_roleFilter == null) return matchesSearch;
        final List<dynamic> traineeRoles = t['role'] ?? [];
        return matchesSearch && traineeRoles.contains(_roleFilter);
      }).toList();

      if (filtered.isEmpty) continue;

      items.add({'type': 'header', 'name': session['name'] ?? 'Session', 'id': sid});
      for (var t in filtered) {
        items.add({'type': 'trainee', 'data': t});
      }
    }

    final unassigned = _sessionTraineeMap['unassigned'];
    if (unassigned != null && unassigned.isNotEmpty) {
      final filtered = unassigned.where((t) {
        final matchesSearch = t['full_name']
            .toString()
            .toLowerCase()
            .contains(_searchQuery.toLowerCase());
        if (_roleFilter == null) return matchesSearch;
        final List<dynamic> traineeRoles = t['role'] ?? [];
        return matchesSearch && traineeRoles.contains(_roleFilter);
      }).toList();

      if (filtered.isNotEmpty) {
        items.add({'type': 'header', 'name': 'Unassigned', 'id': null});
        for (var t in filtered) {
          items.add({'type': 'trainee', 'data': t});
        }
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Members', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(kPadding),
            child: Column(
              children: [
                const SectionHeader(
                  title: 'Directory',
                  subtitle: 'List of all registered members',
                ),
                const SizedBox(height: 24),
                _buildSearchAndFilters(),
                const SizedBox(height: 16),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: kAccent))
                      : RefreshIndicator(
                          onRefresh: _fetchData,
                          color: kAccent,
                          backgroundColor: kSurfaceElevated,
                          child: _trainees.isEmpty
                              ? _buildEmptyState()
                              : _buildTraineesList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Column(
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            style: AppTypography.bodyLg,
            decoration: InputDecoration(
              hintText: 'Search members...',
              hintStyle: AppTypography.label.copyWith(color: kForegroundDisabled),
              icon: const Icon(Icons.search_rounded, color: kAccent, size: 20),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip(null, 'All'),
              const SizedBox(width: 8),
              ..._availableRoles.map((r) => Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: _buildFilterChip(r['name'], r['name'].toString()),
              )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String? value, String label) {
    final isSelected = _roleFilter == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _roleFilter = value),
        borderRadius: BorderRadius.circular(kRadiusSmall),
        splashColor: kAccent.withValues(alpha: 0.12),
        highlightColor: kAccent.withValues(alpha: 0.06),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? kAccent.withValues(alpha: 0.12) : kSurfaceElevated,
            borderRadius: BorderRadius.circular(kRadiusSmall),
            border: Border.all(
              color: isSelected ? kAccent : kBorder.withValues(alpha: 0.3),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.label.copyWith(
              color: isSelected ? kAccent : kForegroundMuted,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTraineesList() {
    final items = _getSessionListItems();

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: kForegroundDisabled),
            const SizedBox(height: 16),
            Text('No results found', style: AppTypography.label.copyWith(color: kForegroundMuted)),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        if (item['type'] == 'header') {
          return Padding(
            padding: EdgeInsets.only(top: index > 0 ? 16 : 0, bottom: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: kAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(kRadiusSmall),
                  ),
                  child: Icon(
                    item['id'] == null ? Icons.person_off_rounded : Icons.folder_rounded,
                    size: 14,
                    color: kAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item['name'].toString().toUpperCase(),
                    style: AppTypography.label.copyWith(color: kAccent, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }

        final trainee = item['data'] as Map<String, dynamic>;
        final List<dynamic> traineeRoles = trainee['role'] ?? [];

        return Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(kRadiusSmall),
                ),
                child: const Icon(Icons.person_outline_rounded, color: kAccent, size: 16),
              ),
              title: Text(
                trainee['full_name'].toString(),
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: trainee['email'] != null || traineeRoles.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (trainee['email'] != null)
                          Text(
                            trainee['email'].toString().toLowerCase(),
                            style: AppTypography.caption.copyWith(fontSize: 10),
                          ),
                        if (traineeRoles.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Wrap(
                            spacing: 3,
                            runSpacing: 2,
                            children: traineeRoles.map((r) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: kAccent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                r.toString(),
                                style: TextStyle(color: kAccent, fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            )).toList(),
                          ),
                        ],
                      ],
                    )
                  : null,
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: kError, size: 20),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: kSurface,
                      title: const Text('Delete member?', style: AppTypography.h3),
                      content: Text('Are you sure you want to remove ${trainee['full_name']} from the directory?', style: AppTypography.body),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete', style: TextStyle(color: kError, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await supabase.from('trainees').delete().eq('id', trainee['id']);
                    _fetchData();
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off_rounded, size: 64, color: kForegroundDisabled.withValues(alpha: 0.2)),
              const SizedBox(height: 24),
              Text(
                'Directory is empty',
                style: AppTypography.h3.copyWith(color: kForegroundMuted),
              ),
              const SizedBox(height: 8),
              const Text(
                'You can add members when you start a new session.',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
