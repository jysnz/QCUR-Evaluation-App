import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Trainees/add_trainee_page.dart';

class SessionMembersTab extends StatefulWidget {
  final String sessionId;

  const SessionMembersTab({
    super.key,
    required this.sessionId,
  });

  @override
  State<SessionMembersTab> createState() => _SessionMembersTabState();
}

class _SessionMembersTabState extends State<SessionMembersTab> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _allTrainees = [];
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
      final cached = AppCache.instance.get<List<dynamic>>('roles');
      final data = cached ?? await supabase.from('roles').select().order('name');
      if (cached == null) {
        AppCache.instance.set('roles', data, ttl: const Duration(minutes: 30));
      }
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
      final cached = AppCache.instance.get<List<dynamic>>('trainees');
      final allTraineesData = cached ??
          await supabase.from('trainees').select().order('full_name');
      if (cached == null) AppCache.instance.set('trainees', allTraineesData);

      setState(() {
        _allTrainees = List<Map<String, dynamic>>.from(allTraineesData);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredTrainees {
    return _allTrainees.where((t) {
      final matchesSearch = t['full_name']
          .toString()
          .toLowerCase()
          .contains(_searchQuery.toLowerCase());
      
      if (_roleFilter == null) return matchesSearch;
      
      final List<dynamic> traineeRoles = t['role'] ?? [];
      final matchesRole = traineeRoles.contains(_roleFilter);
      
      return matchesSearch && matchesRole;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Session Members', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        actions: [
          IconButton(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddTraineePage(sessionId: widget.sessionId),
                ),
              );
              if (result == true) {
                _fetchData();
              }
            },
            icon: const Icon(Icons.person_add_rounded, color: kAccent),
            tooltip: 'Add New members',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(kPadding),
            child: Column(
              children: [
                const SectionHeader(
                  title: 'Members',
                  subtitle: 'Manage members in this training session',
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
                          child: _allTrainees.isEmpty
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
    return GestureDetector(
      onTap: () => setState(() => _roleFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? kAccent.withValues(alpha: 0.1) : kSurfaceElevated,
          borderRadius: BorderRadius.circular(kRadiusSmall),
          border: Border.all(
            color: isSelected ? kAccent : kBorder.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.label.copyWith(
            color: isSelected ? kAccent : kForegroundMuted,
            fontSize: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildTraineesList() {
    final trainees = _filteredTrainees;
    
    if (trainees.isEmpty) {
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
      itemCount: trainees.length,
      itemBuilder: (context, index) {
        final trainee = trainees[index];
        final id = trainee['id'].toString();
        final List<dynamic> traineeRoles = trainee['role'] ?? [];
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
                                style: TextStyle(color: kAccent, fontSize: 9, fontWeight: FontWeight.w600),
                              ),
                            )).toList(),
                          ),
                        ],
                      ],
                    )
                  : null,
              trailing: IconButton(
                icon: const Icon(Icons.person_remove_rounded, color: kError, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Remove member',
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: kSurface,
                      title: const Text('Remove from session?', style: AppTypography.h3),
                      content: Text('Are you sure you want to remove ${trainee['full_name']}?', style: AppTypography.body),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true), 
                          child: const Text('Remove', style: TextStyle(color: kError, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                  
                  if (confirm == true) {
                    try {
                      await supabase.from('session_trainees')
                          .delete()
                          .eq('session_id', widget.sessionId)
                          .eq('trainee_id', id);
                      AppCache.instance.invalidate('trainees');
                      AppCache.instance.invalidate('st_full:${widget.sessionId}');
                      _fetchData();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Remove failed: $e')));
                      }
                    }
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
                'List is empty',
                style: AppTypography.h3.copyWith(color: kForegroundMuted),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add members to this session to see them here.',
                style: AppTypography.caption,
              ),
              const SizedBox(height: 32),
              AppButton(
                label: 'Add Members',
                isFullWidth: false,
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddTraineePage(sessionId: widget.sessionId),
                    ),
                  );
                  if (result == true) {
                    _fetchData();
                  }
                },
                icon: Icons.person_add_rounded,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
