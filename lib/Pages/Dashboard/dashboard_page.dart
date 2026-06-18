import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:qcur_evaluation/Pages/Dashboard/create_session_page.dart';
import 'package:qcur_evaluation/Pages/Dashboard/session_details_page.dart';
import 'package:qcur_evaluation/Pages/Dashboard/trainees_page.dart';
import 'package:qcur_evaluation/Pages/Auth/account_page.dart';
import 'package:intl/intl.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
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
      final user = supabase.auth.currentUser;
      if (user != null) {
        final profileData = await supabase
            .from('user_accounts')
            .select()
            .eq('id', user.id)
            .single();
        _userProfile = profileData;
      }

      final sessionsData = await supabase
          .from('training_sessions')
          .select()
          .order('date', ascending: false);
      
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

  Future<void> _fetchSessions() async {
    try {
      final data = await supabase
          .from('training_sessions')
          .select()
          .order('date', ascending: false);
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
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const TraineesPage()),
              );
            },
            icon: const Icon(Icons.people_outline_rounded, color: kForeground),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          const AppBackground(child: SizedBox.expand()),
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
                        ? const Center(child: CircularProgressIndicator(color: kAccent))
                        : RefreshIndicator(
                            onRefresh: _fetchData,
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
          Text(value, style: AppTypography.h1.copyWith(color: color, fontSize: 24)),
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
          child: AppCard(
            padding: EdgeInsets.zero,
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
              borderRadius: BorderRadius.circular(kRadius),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 56,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(kRadius),
                        bottomLeft: Radius.circular(kRadius),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
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
                  _buildStatusBadge(session['status']),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded, color: kForegroundDisabled, size: 18),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  Widget _buildStatusBadge(String status) {
    return AppStatusBadge(label: status, color: _statusColor(status));
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
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kSurfaceElevated.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.layers_clear_outlined, size: 40, color: kForegroundMuted.withValues(alpha: 0.3)),
              ),
              const SizedBox(height: 20),
              Text(
                'No Sessions Yet',
                style: AppTypography.h3.copyWith(color: kForegroundMuted),
              ),
              const SizedBox(height: 6),
              Text(
                'Tap the button below to create your first training session.',
                style: AppTypography.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
