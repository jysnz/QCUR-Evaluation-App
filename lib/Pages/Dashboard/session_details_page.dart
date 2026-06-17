import 'package:flutter/material.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:qcur_evaluation/Pages/Dashboard/activity_management_page.dart';
import 'package:qcur_evaluation/Pages/Dashboard/session_members_tab.dart';
import 'package:qcur_evaluation/Pages/Dashboard/rankings_tab.dart';

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
      RankingsTab(
        sessionId: widget.sessionId,
      ),
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
          selectedLabelStyle: AppTypography.label.copyWith(fontSize: 10),
          unselectedLabelStyle: AppTypography.label.copyWith(fontSize: 10, color: kForegroundDisabled),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.list_alt_rounded),
              label: 'Activities',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded),
              label: 'Members',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.emoji_events_outlined),
              label: 'Rankings',
            ),
          ],
        ),
      ),
    );
  }
}
