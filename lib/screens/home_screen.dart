import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import 'activity_screen.dart';
import 'calendar_screen.dart';
import 'more_screen.dart';
import 'series_list_screen.dart';
import 'wanted_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  void _startPolling() {
    final state = context.read<AppState>();
    state.refreshQueueCount();
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => state.refreshQueueCount(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _startPolling();
    } else if (s == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.select<AppState, int>((s) => s.queueCount);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const SeriesListScreen(),
          const CalendarScreen(),
          ActivityScreen(active: _index == 2),
          const WantedScreen(),
          const MoreScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: 'Series',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: queue > 0,
              label: Text('$queue'),
              child: const Icon(Icons.downloading_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: queue > 0,
              label: Text('$queue'),
              child: const Icon(Icons.downloading),
            ),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_off_outlined),
            selectedIcon: Icon(Icons.search_off),
            label: 'Wanted',
          ),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
