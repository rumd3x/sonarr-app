import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'calendar_screen.dart';

class WantedScreen extends StatefulWidget {
  const WantedScreen({super.key});

  @override
  State<WantedScreen> createState() => _WantedScreenState();
}

class _WantedScreenState extends State<WantedScreen> {
  final _key = GlobalKey<AsyncBodyState<List<Json>>>();

  Future<void> _search(List<int> ids, String ok) async {
    try {
      await context.read<AppState>().api!.searchEpisodes(ids);
      if (mounted) toast(context, ok);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Wanted'),
      actions: [
        IconButton(
          tooltip: 'Search all missing',
          icon: const Icon(Icons.manage_search),
          onPressed: () async {
            try {
              await context.read<AppState>().api!.searchMissing();
              if (context.mounted) {
                toast(context, 'Searching for all missing episodes');
              }
            } catch (e) {
              if (context.mounted) toast(context, '$e');
            }
          },
        ),
      ],
    ),
    body: AsyncBody<List<Json>>(
      key: _key,
      load: (api) => api.missing(),
      builder: (context, list) {
        if (list.isEmpty) {
          return const EmptyView(
            Icons.check_circle_outline,
            'No missing episodes',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: list.length,
          itemBuilder: (_, i) => EpisodeCard(
            list[i],
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Automatic search',
                  icon: const Icon(Icons.search),
                  onPressed: () =>
                      _search([list[i]['id'] as int], 'Search started'),
                ),
                ManualSearchButton(
                  episode: list[i],
                  seriesTitle: '${(list[i]['series'] as Map?)?['title'] ?? ''}',
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
