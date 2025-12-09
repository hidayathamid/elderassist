import 'package:flutter/material.dart';

import 'chat/caregiver_chat_list_screen.dart';
import 'home/caregiver_home_screen.dart';
import 'jobs/caregiver_jobs_screen.dart';
import 'profile/caregiver_profile_screen.dart';
import 'sos/caregiver_sos_alerts_screen.dart';

class CaregiverRootScreen extends StatefulWidget {
  const CaregiverRootScreen({super.key});

  @override
  State<CaregiverRootScreen> createState() => _CaregiverRootScreenState();
}

class _CaregiverRootScreenState extends State<CaregiverRootScreen> {
  int _selectedIndex = 0;

  static const _tabs = <BottomNavigationBarItem>[
    BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
    BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Jobs'),
    BottomNavigationBarItem(icon: Icon(Icons.warning_amber_rounded), label: 'SOS'),
    BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
    BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
  ];

  static const _pages = <Widget>[
    CaregiverHomeScreen(),
    CaregiverJobsScreen(),
    CaregiverSOSAlertsScreen(),
    CaregiverChatListScreen(),
    CaregiverProfileScreen(),
  ];

  void _onTabSelected(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        items: _tabs,
        type: BottomNavigationBarType.fixed,
        onTap: _onTabSelected,
        showUnselectedLabels: true,
      ),
    );
  }
}
