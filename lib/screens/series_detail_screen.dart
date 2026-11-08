import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

class SeriesDetailScreen extends StatefulWidget {
  final Json series;
  const SeriesDetailScreen({super.key, required this.series});

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  late Json _series;
  List<Json> _episodes = [];
  bool _loading = true;
  Object? _error;

  SonarrApi get _api => context.read<AppState>().api!;

  @override
  void initState() {
    super.initState();
    _series = widget.series;
    _load();
  }

  Future<void> _load() async {
    try {
      final id = _series['id'] as int;
      final results = await Future.wait([
        _api.seriesById(id),
        _api.episodes(id),
      ]);
      if (!mounted) return;
      setState(() {
        _series = results[0] as Json;
        _episodes = results[1] as List<Json>;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String ok) async {
    try {
      await action();
      if (mounted) toast(context, ok);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _toggleSeries() async {
    final updated = {..._series, 'monitored': !(_series['monitored'] == true)};
    await _run(
      () async {
        final r = await _api.updateSeries(updated);
        setState(() => _series = r);
      },
      updated['monitored'] == true ? 'Monitoring series' : 'Series unmonitored',
    );
  }

  Future<void> _toggleSeason(int number, bool monitored) async {
    final seasons = (_series['seasons'] as List)
        .map((s) => Json.from(s as Map))
        .map(
          (s) =>
              s['seasonNumber'] == number ? {...s, 'monitored': monitored} : s,
        )
        .toList();
    await _run(() async {
      final r = await _api.updateSeries({..._series, 'seasons': seasons});
      setState(() => _series = r);
      await _load();
    }, monitored ? 'Season monitored' : 'Season unmonitored');
  }

  Future<void> _toggleEpisode(Json e) async {
    final updated = {...e, 'monitored': !(e['monitored'] == true)};
    try {
      final r = await _api.updateEpisode(updated);
      setState(() {
        final i = _episodes.indexWhere((x) => x['id'] == e['id']);
        if (i >= 0) {
          _episodes[i] = {..._episodes[i], 'monitored': r['monitored']};
        }
      });
    } catch (err) {
      if (mounted) toast(context, '$err');
    }
  }

  Future<void> _delete() async {
    var deleteFiles = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Delete ${_series['title']}?'),
          content: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: deleteFiles,
            onChanged: (v) => setD(() => deleteFiles = v ?? false),
            title: const Text('Also delete files from disk'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteSeries(_series['id'] as int, deleteFiles: deleteFiles);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Map<int, List<Json>> get _bySeason {
    final map = <int, List<Json>>{};
    for (final e in _episodes) {
      map.putIfAbsent(e['seasonNumber'] as int, () => []).add(e);
    }
    for (final l in map.values) {
      l.sort(
        (a, b) =>
            (a['episodeNumber'] as int).compareTo(b['episodeNumber'] as int),
      );
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final id = _series['id'] as int;
    final st = _series['statistics'] as Map? ?? {};
    final seasons = _bySeason.keys.toList()..sort((a, b) => b.compareTo(a));
    final monitored = _series['monitored'] == true;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 240,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  '${_series['title']}',
                  style: const TextStyle(shadows: [Shadow(blurRadius: 8)]),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Poster(_series, type: 'fanart'),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  tooltip: monitored ? 'Unmonitor' : 'Monitor',
                  icon: Icon(
                    monitored ? Icons.bookmark : Icons.bookmark_border,
                  ),
                  onPressed: _toggleSeries,
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'refresh':
                        _run(() => _api.refreshSeries(id), 'Refresh queued');
                      case 'search':
                        _run(() => _api.searchSeries(id), 'Search started');
                      case 'delete':
                        _delete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'refresh',
                      child: Text('Refresh & scan'),
                    ),
                    PopupMenuItem(
                      value: 'search',
                      child: Text('Search all monitored'),
                    ),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (_series['year'] != null)
                          Chip(label: Text('${_series['year']}')),
                        if (_series['network'] != null &&
                            '${_series['network']}'.isNotEmpty)
                          Chip(label: Text('${_series['network']}')),
                        Chip(label: Text(_cap('${_series['status']}'))),
                        if (_series['runtime'] != null &&
                            _series['runtime'] != 0)
                          Chip(label: Text('${_series['runtime']} min')),
                        Chip(
                          label: Text(
                            '${st['episodeFileCount'] ?? 0}/${st['episodeCount'] ?? 0} episodes',
                          ),
                        ),
                        if ((st['sizeOnDisk'] as num?) != null)
                          Chip(
                            label: Text(formatBytes(st['sizeOnDisk'] as num)),
                          ),
                      ],
                    ),
                    if ('${_series['overview'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${_series['overview']}',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                    if ('${_series['path'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.folder_outlined, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${_series['path']}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorView(error: _error!, onRetry: _load),
              )
            else
              SliverList.list(
                children: [
                  for (final n in seasons) _seasonTile(n),
                  const SizedBox(height: 32),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _seasonTile(int number) {
    final eps = _bySeason[number]!;
    final have = eps.where((e) => e['hasFile'] == true).length;
    final seasonInfo = (_series['seasons'] as List? ?? [])
        .cast<Map>()
        .where((s) => s['seasonNumber'] == number)
        .firstOrNull;
    final seasonMonitored = seasonInfo?['monitored'] == true;
    return ExpansionTile(
      shape: const Border(),
      title: Text(number == 0 ? 'Specials' : 'Season $number'),
      subtitle: Text('$have / ${eps.length} episodes'),
      leading: IconButton(
        icon: Icon(seasonMonitored ? Icons.bookmark : Icons.bookmark_border),
        onPressed: () => _toggleSeason(number, !seasonMonitored),
      ),
      trailing: IconButton(
        tooltip: 'Search season',
        icon: const Icon(Icons.search),
        onPressed: () => _run(
          () => _api.searchSeason(_series['id'] as int, number),
          'Season search started',
        ),
      ),
      children: [for (final e in eps) _episodeTile(e)],
    );
  }

  Widget _episodeTile(Json e) {
    final hasFile = e['hasFile'] == true;
    final air = DateTime.tryParse('${e['airDateUtc']}')?.toLocal();
    final aired = air != null && air.isBefore(DateTime.now());
    final color = hasFile
        ? Colors.green
        : (aired && e['monitored'] == true ? Colors.redAccent : Colors.grey);
    final quality = (e['episodeFile'] as Map?)?['quality']?['quality']?['name'];
    return ListTile(
      dense: true,
      onTap: () => openEpisode(context, e, '${_series['title']}'),
      leading: Icon(
        hasFile ? Icons.check_circle : Icons.circle_outlined,
        color: color,
      ),
      title: Text(
        '${e['episodeNumber']}. ${e['title'] ?? 'TBA'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (air != null) DateFormat.yMMMd().format(air),
          if (quality != null) '$quality',
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Automatic search',
            icon: const Icon(Icons.search, size: 20),
            onPressed: () => _run(
              () => _api.searchEpisodes([e['id'] as int]),
              'Search started',
            ),
          ),
          ManualSearchButton(episode: e, seriesTitle: '${_series['title']}'),
          IconButton(
            icon: Icon(
              e['monitored'] == true ? Icons.bookmark : Icons.bookmark_border,
              size: 20,
            ),
            onPressed: () => _toggleEpisode(e),
          ),
        ],
      ),
    );
  }
}
