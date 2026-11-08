import 'package:flutter/material.dart';

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

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _pages = <Widget>[
    SeriesListScreen(),
    CalendarScreen(),
    ActivityScreen(),
    WantedScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: _pages),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      destinations: const [
        NavigationDestination(
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
          icon: Icon(Icons.downloading_outlined),
          selectedIcon: Icon(Icons.downloading),
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
