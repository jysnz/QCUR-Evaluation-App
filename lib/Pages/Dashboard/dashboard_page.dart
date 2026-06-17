import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:qcur_evaluation/Pages/Dashboard/create_session_page.dart';
import 'package:qcur_evaluation/Pages/Dashboard/activity_management_page.dart';
import 'package:qcur_evaluation/Pages/Dashboard/trainees_page.dart';
import 'package:intl/intl.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSessions();
  }

  Future<void> _fetchSessions() async {
    setState(() => _isLoading = true);
    try {
      final data = await supabase
          .from('training_sessions')
          .select()
          .order('date', ascending: false);
      setState(() {
        _sessions = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching sessions: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const TechnicalGridBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(kPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildStatsRow(),
                  const SizedBox(height: 24),
                  Expanded(
                    child: TechnicalCard(
                      padding: const EdgeInsets.all(0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTableHeader(),
                          const Divider(height: 1, color: Colors.white10),
                          Expanded(
                            child: _isLoading
                                ? const Center(child: CircularProgressIndicator(color: kAccent))
                                : _sessions.isEmpty
                                    ? _buildEmptyState()
                                    : _buildSessionsList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TechnicalButton(
                    label: 'Create Training Session',
                    icon: Icons.add,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'COMMAND CENTER',
                style: TextStyle(
                  color: kAccent.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
              const Text(
                'Training Sessions',
                style: TextStyle(
                  color: kForeground,
                  fontWeight: FontWeight.w900,
                  fontSize: 28,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const TraineesPage()),
            );
          },
          icon: const Icon(Icons.people_outline, color: kAccent),
        ),
        IconButton(
          onPressed: _signOut,
          icon: const Icon(Icons.logout, color: kForegroundMuted),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatItem('TOTAL SESSIONS', _sessions.length.toString()),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatItem('ACTIVE', _sessions.where((s) => s['status'] == 'active').length.toString()),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatItem('COMPLETED', _sessions.where((s) => s['status'] == 'completed').length.toString()),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return TechnicalCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: kForegroundMuted,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: kAccent,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white.withValues(alpha: 0.02),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('SESSION NAME', style: _columnHeaderStyle)),
          Expanded(flex: 2, child: Text('DATE', style: _columnHeaderStyle)),
          Expanded(flex: 1, child: Text('STATUS', style: _columnHeaderStyle)),
          SizedBox(width: 48), // Actions space
        ],
      ),
    );
  }

  Widget _buildSessionsList() {
    return ListView.separated(
      itemCount: _sessions.length,
      separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.white10),
      itemBuilder: (context, index) {
        final session = _sessions[index];
        final date = DateTime.parse(session['date']);
        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ActivityManagementPage(
                  sessionId: session['id'],
                  sessionName: session['name'],
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    session['name'].toString().toUpperCase(),
                    style: const TextStyle(
                      color: kForeground,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    DateFormat('MMM dd, yyyy').format(date),
                    style: const TextStyle(
                      color: kForegroundMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: _buildStatusChip(session['status']),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.chevron_right, color: kAccent, size: 20),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    switch (status) {
      case 'active':
        color = kAccent;
        break;
      case 'completed':
        color = Colors.blue;
        break;
      default:
        color = kForegroundMuted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          const Text(
            'NO SESSIONS FOUND',
            style: TextStyle(
              color: kForegroundMuted,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start by creating your first training session.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.2),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

const _columnHeaderStyle = TextStyle(
  color: kForegroundMuted,
  fontSize: 10,
  fontWeight: FontWeight.w900,
  letterSpacing: 1,
);
