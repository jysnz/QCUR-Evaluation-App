import 'package:flutter/material.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Activities/activity_management_page.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Sessions/session_members_tab.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Sessions/rankings_tab.dart';
import 'package:qcur_evaluation/Pages/Dashboard/Sessions/session_settings_tab.dart';

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
  final _rankingsVisibilityTrigger = ValueNotifier<int>(0);

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
        visibilityTrigger: _rankingsVisibilityTrigger,
      ),
      SessionSettingsTab(
        sessionId: widget.sessionId,
        sessionName: widget.sessionName,
      ),
    ];
  }

  @override
  void dispose() {
    _rankingsVisibilityTrigger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
      backgroundColor: kBackground,
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
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
          onTap: (index) {
            if (index == 2 && _currentIndex != 2) {
              _rankingsVisibilityTrigger.value++;
            }
            setState(() => _currentIndex = index);
          },
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
            BottomNavigationBarItem(
              icon: Icon(Icons.tune_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
      ),
    );
  }
}
