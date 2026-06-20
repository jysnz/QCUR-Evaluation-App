import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Sessions/create_session_page.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Sessions/edit_session_page.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Sessions/session_details_page.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Trainees/trainees_page.dart';
import 'package:qcur_evaluation/Pages/Auth/account_page.dart';
import 'package:intl/intl.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _SessionsTab(),
          TraineesPage(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: kSurface,
          border: Border(top: BorderSide(color: kBorder.withValues(alpha: 0.3))),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: kSurface,
          selectedItemColor: kAccent,
          unselectedItemColor: kForegroundDisabled,
          selectedLabelStyle: AppTypography.label.copyWith(fontSize: 10),
          unselectedLabelStyle: AppTypography.label.copyWith(fontSize: 10, color: kForegroundDisabled),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.layers_rounded),
              label: 'Sessions',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded),
              label: 'Members',
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionsTab extends StatefulWidget {
  const _SessionsTab();

  @override
  State<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<_SessionsTab> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final cache = AppCache.instance;
      final user = supabase.auth.currentUser;
      if (user != null) {
        final userKey = 'user:${user.id}';
        final cachedProfile = cache.get<Map<String, dynamic>>(userKey);
        if (cachedProfile != null) {
          _userProfile = cachedProfile;
        } else {
          final profileData = await supabase
              .from('user_accounts')
              .select()
              .eq('id', user.id)
              .single();
          cache.set(userKey, profileData);
          _userProfile = profileData;
        }
      }

      final cachedSessions = cache.get<List<dynamic>>('sessions');
      final sessionsData = cachedSessions ??
          await supabase
              .from('training_sessions')
              .select()
              .order('date', ascending: false);
      if (cachedSessions == null) cache.set('sessions', sessionsData);

      setState(() {
        _sessions = List<Map<String, dynamic>>.from(sessionsData);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching data: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteSession(Map<String, dynamic> session) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Delete session?', style: AppTypography.h3),
        content: Text(
          'This will permanently delete "${session['name']}" and all its activities, scores, and members. This cannot be undone.',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: kError, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final sessionId = session['id'] as String;
      await supabase.from('training_sessions').delete().eq('id', sessionId);
      AppCache.instance.invalidate('sessions');
      AppCache.instance.invalidateWhere((k) =>
          k.contains(sessionId) || k.startsWith('st:'));
      _fetchSessions();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _fetchSessions() async {
    try {
      AppCache.instance.invalidate('sessions');
      final data = await supabase
          .from('training_sessions')
          .select()
          .order('date', ascending: false);
      AppCache.instance.set('sessions', data);
      setState(() {
        _sessions = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching sessions: $e')),
        );
      }
    }
  }

  Future<void> _refreshData() async {
    AppCache.instance.invalidate('sessions');
    await _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: kPadding,
        title: Row(
          children: [
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const AccountPage()),
                ).then((_) => _fetchData());
              },
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: kAccent.withValues(alpha: 0.2), width: 2),
                ),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: kSurfaceElevated,
                  backgroundImage: _userProfile?['avatar_url'] != null
                      ? NetworkImage(_userProfile!['avatar_url'])
                      : null,
                  child: _userProfile?['avatar_url'] == null
                      ? const Icon(Icons.person, size: 20, color: kForegroundMuted)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome back,', style: AppTypography.caption),
                  Text(
                    _userProfile?['full_name']?.toString() ?? 'User',
                    style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Notifications coming soon'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.notifications_none_rounded, color: kForeground),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          const TechnicalGridBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const SectionHeader(
                    title: 'Overview',
                    subtitle: 'Track your current progress',
                  ),
                  const SizedBox(height: 24),
                  _buildStatsRow(),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _isLoading
                        ? const AppLoader()
                        : RefreshIndicator(
                            onRefresh: _refreshData,
                            color: kAccent,
                            backgroundColor: kSurfaceElevated,
                            child: _sessions.isEmpty
                                ? _buildEmptyState()
                                : _buildSessionsList(),
                          ),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: 'New Training Session',
                    icon: Icons.add_rounded,
                    onTap: () async {
                      final result = await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const CreateSessionPage(),
                        ),
                      );
                      if (result == true) {
                        _fetchSessions();
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatItem('Total', _sessions.length.toString(), kInfo, Icons.auto_awesome_rounded),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatItem('Active', _sessions.where((s) => s['status'] == 'active').length.toString(), kAccent, Icons.rocket_launch_rounded),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatItem('Done', _sessions.where((s) => s['status'] == 'completed').length.toString(), kSuccess, Icons.task_alt_rounded),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, Color color, IconData icon) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      color: kSurface,
      border: Border.all(color: color.withValues(alpha: 0.15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(label, style: AppTypography.label.copyWith(color: color, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 10),
          Text(value, style: AppTypography.statValue.copyWith(color: color)),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active': return kAccent;
      case 'completed': return kSuccess;
      case 'planned': return kInfo;
      default: return kForegroundMuted;
    }
  }

  Widget _buildSessionsList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 4),
      itemCount: _sessions.length,
      itemBuilder: (context, index) {
        final session = _sessions[index];
        final date = DateTime.parse(session['date']);
        final color = _statusColor(session['status']);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: kSurface,
            borderRadius: BorderRadius.circular(kRadius),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kRadius),
                border: Border.all(color: kBorder.withValues(alpha: 0.5)),
                boxShadow: kCardShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(kRadius),
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => SessionDetailsPage(
                          sessionId: session['id'],
                          sessionName: session['name'],
                        ),
                      ),
                    );
                  },
                  splashColor: kAccent.withValues(alpha: 0.06),
                  highlightColor: kAccent.withValues(alpha: 0.03),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: 4,
                          color: color,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  session['name'].toString(),
                                  style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today_rounded, size: 11, color: kForegroundDisabled),
                                    const SizedBox(width: 4),
                                    Text(
                                      DateFormat('MMM dd, yyyy').format(date),
                                      style: AppTypography.caption.copyWith(fontSize: 11, color: kForegroundDisabled),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        Center(
                          child: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded, color: kForegroundDisabled, size: 18),
                            color: kSurfaceElevated,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSmall)),
                            onSelected: (value) async {
                              if (value == 'edit') {
                                final result = await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EditSessionPage(session: session),
                                  ),
                                );
                                if (result == true) _fetchSessions();
                              } else if (value == 'delete') {
                                _deleteSession(session);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'edit',
                                height: 40,
                                child: Row(children: [
                                  const Icon(Icons.edit_outlined, size: 15, color: kForeground),
                                  const SizedBox(width: 10),
                                  Text('Edit', style: AppTypography.body.copyWith(fontSize: 13)),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                height: 40,
                                child: Row(children: [
                                  const Icon(Icons.delete_outline_rounded, size: 15, color: kError),
                                  const SizedBox(width: 10),
                                  Text('Delete', style: AppTypography.body.copyWith(fontSize: 13, color: kError)),
                                ]),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    // Kept scrollable so pull-to-refresh still works on an empty list.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
        const AppEmptyState(
          icon: Icons.layers_clear_outlined,
          title: 'No Sessions Yet',
          message: 'Tap the button below to create your first training session.',
        ),
      ],
    );
  }
}
