import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'calendar_screen.dart';

class WantedScreen extends StatelessWidget {
  const WantedScreen({super.key});

  Future<void> _searchAll(BuildContext context, bool cutoff) async {
    final api = context.read<AppState>().api!;
    try {
      if (cutoff) {
        await api.searchCutoffUnmet();
      } else {
        await api.searchMissing();
      }
      if (context.mounted) {
        toast(
          context,
          cutoff
              ? 'Searching for all cutoff unmet episodes'
              : 'Searching for all missing episodes',
        );
      }
    } catch (e) {
      if (context.mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Builder(
      builder: (context) {
        final tabs = DefaultTabController.of(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Wanted'),
            actions: [
              AnimatedBuilder(
                animation: tabs.animation!,
                builder: (context, _) {
                  final cutoff = tabs.animation!.value.round() == 1;
                  return IconButton(
                    tooltip: cutoff
                        ? 'Search all cutoff unmet'
                        : 'Search all missing',
                    icon: const Icon(Icons.manage_search),
                    onPressed: () => _searchAll(context, cutoff),
                  );
                },
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Missing'),
                Tab(text: 'Cutoff unmet'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [_WantedTab(cutoff: false), _WantedTab(cutoff: true)],
          ),
        );
      },
    ),
  );
}

class _WantedTab extends StatefulWidget {
  final bool cutoff;
  const _WantedTab({required this.cutoff});

  @override
  State<_WantedTab> createState() => _WantedTabState();
}

class _WantedTabState extends State<_WantedTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Future<void> _search(List<int> ids, String ok) async {
    try {
      await context.read<AppState>().api!.searchEpisodes(ids);
      if (mounted) toast(context, ok);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AsyncBody<List<Json>>(
      load: (api) => widget.cutoff ? api.cutoffUnmet() : api.missing(),
      builder: (context, list) {
        if (list.isEmpty) {
          return EmptyView(
            Icons.check_circle_outline,
            widget.cutoff ? 'No cutoff unmet episodes' : 'No missing episodes',
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
    );
  }
}
