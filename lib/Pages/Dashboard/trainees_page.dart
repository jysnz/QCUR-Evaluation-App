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
    _fetchTrainees();
  }

  Future<void> _fetchTrainees() async {
    setState(() => _isLoading = true);
    try {
      final data = await supabase
          .from('trainees')
          .select()
          .order('full_name');
      setState(() {
        _trainees = List<Map<String, dynamic>>.from(data);
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
    return _trainees.where((t) {
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
        title: Text('ALL PEOPLE', style: AppTypography.h3.copyWith(letterSpacing: 2)),
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
                    title: 'People List',
                    subtitle: 'All the people you have added',
                  ),
                  const SizedBox(height: 24),
                  _buildSearchAndFilters(),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator(color: kAccent))
                        : RefreshIndicator(
                            onRefresh: _fetchTrainees,
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
              hintText: 'SEARCH LIST...',
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
                child: const Icon(Icons.person_outline, color: kAccent, size: 20),
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
                icon: const Icon(Icons.delete_outline, color: kError, size: 20),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: kSurface,
                      title: const Text('REMOVE PERSON?', style: AppTypography.h3),
                      content: Text('Are you sure you want to remove ${trainee['full_name']}?', style: AppTypography.body),
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
                    await supabase.from('trainees').delete().eq('id', trainee['id']);
                    _fetchTrainees();
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
                style: AppTypography.overline.copyWith(color: kForegroundMuted, letterSpacing: 2),
              ),
              const SizedBox(height: 8),
              Text(
                'You can add people when you start a session.',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
