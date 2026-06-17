import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:qcur_evaluation/Pages/Dashboard/activity_management_page.dart';
import 'package:qcur_evaluation/Pages/Dashboard/session_members_tab.dart';

class SessionDetailsPage extends StatefulWidget {
  final String sessionId;
  final String sessionName;

  const SessionDetailsPage({
    super.key,
    required this.sessionId,
    required this.sessionName,
  });

  @override
  State<SessionDetailsPage> createState() => _SessionDetailsPageState();
}

class _SessionDetailsPageState extends State<SessionDetailsPage> {
  int _currentIndex = 0;

  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      ActivityManagementView(
        sessionId: widget.sessionId,
        sessionName: widget.sessionName,
      ),
      SessionMembersTab(
        sessionId: widget.sessionId,
      ),
      const RankingsPlaceholder(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: kSurface,
          selectedItemColor: kAccent,
          unselectedItemColor: kForegroundDisabled,
          selectedLabelStyle: AppTypography.overline.copyWith(fontSize: 8),
          unselectedLabelStyle: AppTypography.overline.copyWith(fontSize: 8, color: kForegroundDisabled),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.list_alt_rounded),
              label: 'ACTIVITIES',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              label: 'MEMBERS',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.emoji_events_outlined),
              label: 'RANKINGS',
            ),
          ],
        ),
      ),
    );
  }
}

class RankingsPlaceholder extends StatelessWidget {
  const RankingsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('RANKINGS', style: AppTypography.h3.copyWith(letterSpacing: 2)),
      ),
      body: Stack(
        children: [
          const TechnicalGridBackground(),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.construction_rounded, size: 64, color: kWarning.withValues(alpha: 0.5)),
                const SizedBox(height: 24),
                Text(
                  'UNDER CONSTRUCTION',
                  style: AppTypography.h2.copyWith(color: kWarning, letterSpacing: 4),
                ),
                const SizedBox(height: 12),
                Text(
                  'The ranking algorithm is being calibrated.',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
