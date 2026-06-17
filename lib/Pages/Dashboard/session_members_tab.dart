import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:qcur_evaluation/Pages/Dashboard/add_trainee_page.dart';

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
  List<String> _selectedTraineeIds = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _roleFilter;

  final List<String> _roles = [
    'Programmer',
    'Builder',
    'Designer',
    'Notebook Manager',
    'Driver',
    'Coach Driver'
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // Fetch all trainees
      final allTraineesData = await supabase
          .from('trainees')
          .select()
          .order('full_name');

      // Fetch session members
      final sessionMembersData = await supabase
          .from('session_trainees')
          .select('trainee_id')
          .eq('session_id', widget.sessionId);

      setState(() {
        _allTrainees = List<Map<String, dynamic>>.from(allTraineesData);
        _selectedTraineeIds = sessionMembersData
            .map((m) => m['trainee_id'].toString())
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleMember(String traineeId, bool isSelected) async {
    try {
      if (isSelected) {
        await supabase.from('session_trainees').insert({
          'session_id': widget.sessionId,
          'trainee_id': traineeId,
        });
        setState(() => _selectedTraineeIds.add(traineeId));
      } else {
        await supabase.from('session_trainees')
            .delete()
            .eq('session_id', widget.sessionId)
            .eq('trainee_id', traineeId);
        setState(() => _selectedTraineeIds.remove(traineeId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
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
        title: Text('SESSION TRAINEES', style: AppTypography.h3.copyWith(letterSpacing: 2)),
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
            icon: const Icon(Icons.person_add_alt_1_outlined, color: kAccent),
            tooltip: 'Add New People',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          const TechnicalGridBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(kPadding),
              child: Column(
                children: [
                  const SectionHeader(
                    title: 'People in this Session',
                    subtitle: 'Manage the people taking part in this training',
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
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Column(
      children: [
        TechnicalCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            style: AppTypography.bodyLg,
            decoration: InputDecoration(
              hintText: 'SEARCH PEOPLE...',
              hintStyle: AppTypography.overline.copyWith(color: kForegroundDisabled),
              icon: const Icon(Icons.search, color: kAccent, size: 20),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip(null, 'ALL'),
              const SizedBox(width: 8),
              ..._roles.map((r) => Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: _buildFilterChip(r, r.toUpperCase()),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? kAccent.withValues(alpha: 0.1) : kSurfaceElevated,
          borderRadius: BorderRadius.circular(kRadiusSmall),
          border: Border.all(
            color: isSelected ? kAccent : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.overline.copyWith(
            color: isSelected ? kAccent : kForegroundMuted,
            fontSize: 8,
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
            const Icon(Icons.search_off_outlined, size: 48, color: kForegroundDisabled),
            const SizedBox(height: 16),
            Text('NO ONE FOUND', style: AppTypography.overline.copyWith(color: kForegroundMuted)),
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
          padding: const EdgeInsets.only(bottom: 12.0),
          child: TechnicalCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person, color: kAccent, size: 20),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trainee['full_name'].toString().toUpperCase(),
                    style: AppTypography.bodyLg.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  if (traineeRoles.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: traineeRoles.map((r) => AppStatusBadge(
                        label: r.toString(),
                        color: kAccent,
                      )).toList(),
                    ),
                  ],
                ],
              ),
              subtitle: trainee['email'] != null 
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        trainee['email'].toString().toLowerCase(), 
                        style: AppTypography.caption.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ) 
                  : null,
              trailing: IconButton(
                icon: const Icon(Icons.person_remove_alt_1_outlined, color: kError, size: 20),
                tooltip: 'Remove from Session',
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: kSurface,
                      title: const Text('REMOVE FROM SESSION?', style: AppTypography.h3),
                      content: Text('Remove ${trainee['full_name']} from this training session?', style: AppTypography.body),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true), 
                          child: const Text('REMOVE', style: TextStyle(color: kError, fontWeight: FontWeight.bold)),
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
              Icon(Icons.person_off_outlined, size: 64, color: kForegroundDisabled.withValues(alpha: 0.2)),
              const SizedBox(height: 24),
              Text(
                'LIST IS EMPTY',
                style: AppTypography.h3.copyWith(color: kForegroundMuted, letterSpacing: 2),
              ),
              const SizedBox(height: 8),
              Text(
                'Add people to this session to see them here.',
                style: AppTypography.caption,
              ),
              const SizedBox(height: 32),
              TechnicalButton(
                label: 'ADD PEOPLE',
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
                icon: Icons.person_add_alt_1_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
