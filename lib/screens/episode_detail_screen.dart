import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'manual_search_screen.dart';

/// Episode screen with three tabs: Details, History and Manual search.
class EpisodeDetailScreen extends StatefulWidget {
  final Json episode;
  final String seriesTitle;
  final int initialTab;
  const EpisodeDetailScreen({
    super.key,
    required this.episode,
    required this.seriesTitle,
    this.initialTab = 0,
  });

  @override
  State<EpisodeDetailScreen> createState() => _EpisodeDetailScreenState();
}

class _EpisodeDetailScreenState extends State<EpisodeDetailScreen> {
  late Json _episode = widget.episode;
  final _detailsKey = GlobalKey<AsyncBodyState<Json>>();

  int get _id => _episode['id'] as int;
  String get _label => '${widget.seriesTitle} · ${episodeCode(_episode)}';
  SonarrApi get _api => context.read<AppState>().api!;

  Future<void> _run(Future<void> Function() action, String ok) async {
    try {
      await action();
      if (mounted) toast(context, ok);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _toggleMonitor(Json current) async {
    try {
      final r = await _api.updateEpisode({
        ...current,
        'monitored': !(current['monitored'] == true),
      });
      setState(() => _episode = {..._episode, 'monitored': r['monitored']});
      _detailsKey.currentState?.reload();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _deleteFile(int fileId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete episode file?'),
        content: const Text('The file will be removed from disk.'),
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
    );
    if (ok != true) return;
    await _run(() async {
      await _api.deleteEpisodeFile(fileId);
      _detailsKey.currentState?.reload();
    }, 'File deleted');
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    initialIndex: widget.initialTab,
    child: Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_episode['title'] ?? 'TBA'}',
              style: const TextStyle(fontSize: 18),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _label,
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Details'),
            Tab(text: 'History'),
            Tab(text: 'Search'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          AsyncBody<Json>(
            key: _detailsKey,
            load: (api) => api.episodeById(_id),
            builder: (context, ep) => _details(ep),
          ),
          AsyncBody<List<Json>>(
            load: (api) => api.episodeHistory(_id),
            builder: (context, list) => _history(list),
          ),
          ManualSearchView(episodeId: _id, label: _label),
        ],
      ),
    ),
  );

  Widget _details(Json ep) {
    final cs = Theme.of(context).colorScheme;
    final air = DateTime.tryParse('${ep['airDateUtc']}')?.toLocal();
    final file = ep['episodeFile'] is Map
        ? Json.from(ep['episodeFile'] as Map)
        : null;
    final monitored = ep['monitored'] == true;
    final runtime = ep['runtime'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Chip(label: Text(episodeCode(ep))),
            if (air != null)
              Chip(label: Text(DateFormat.yMMMEd().add_jm().format(air))),
            if (runtime != null && runtime != 0)
              Chip(label: Text('$runtime min')),
            if ('${ep['finaleType'] ?? ''}'.isNotEmpty)
              Chip(label: Text('${ep['finaleType']}'.replaceAll('_', ' '))),
          ],
        ),
        if ('${ep['overview'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '${ep['overview']}',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _toggleMonitor(ep),
                icon: Icon(monitored ? Icons.bookmark : Icons.bookmark_border),
                label: Text(monitored ? 'Monitored' : 'Unmonitored'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () =>
                    _run(() => _api.searchEpisodes([_id]), 'Search started'),
                icon: const Icon(Icons.search),
                label: const Text('Auto search'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'File',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(color: cs.primary),
        ),
        const SizedBox(height: 8),
        if (file == null)
          const Card(
            child: ListTile(
              leading: Icon(Icons.insert_drive_file_outlined),
              title: Text('No file'),
              subtitle: Text(
                'Use Auto search or the Search tab to find a release.',
              ),
            ),
          )
        else
          _fileCard(file),
      ],
    );
  }

  Widget _fileCard(Json f) {
    final media = f['mediaInfo'] is Map
        ? Json.from(f['mediaInfo'] as Map)
        : <String, dynamic>{};
    final quality = (f['quality'] as Map?)?['quality']?['name'];
    final languages = (f['languages'] as List? ?? [])
        .map((l) => (l as Map)['name'])
        .join(', ');
    final added = DateTime.tryParse('${f['dateAdded']}')?.toLocal();
    final rows = <(String, String)>[
      ('Path', '${f['path'] ?? f['relativePath'] ?? ''}'),
      if (quality != null) ('Quality', '$quality'),
      ('Size', formatBytes((f['size'] as num?) ?? 0)),
      if ('${f['releaseGroup'] ?? ''}'.isNotEmpty)
        ('Release group', '${f['releaseGroup']}'),
      if (languages.isNotEmpty) ('Languages', languages),
      if (media['resolution'] != null) ('Resolution', '${media['resolution']}'),
      if (media['videoCodec'] != null)
        (
          'Video',
          '${media['videoCodec']}'
              '${'${media['videoDynamicRangeType'] ?? ''}'.isNotEmpty ? ' · ${media['videoDynamicRangeType']}' : ''}',
        ),
      if (media['audioCodec'] != null)
        (
          'Audio',
          '${media['audioCodec']}'
              '${media['audioChannels'] != null ? ' ${media['audioChannels']}ch' : ''}',
        ),
      if ('${media['subtitles'] ?? ''}'.isNotEmpty)
        ('Subtitles', '${media['subtitles']}'),
      if (added != null) ('Added', DateFormat.yMMMd().add_jm().format(added)),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 104,
                      child: Text(
                        r.$1,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    Expanded(child: SelectableText(r.$2)),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _deleteFile(f['id'] as int),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete file'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _events = {
    'grabbed': ('Grabbed', Icons.cloud_download),
    'downloadFolderImported': ('Imported', Icons.download_done),
    'episodeFileImported': ('Imported', Icons.download_done),
    'downloadFailed': ('Download failed', Icons.error_outline),
    'episodeFileDeleted': ('File deleted', Icons.delete_outline),
    'episodeFileRenamed': ('Renamed', Icons.drive_file_rename_outline),
    'downloadIgnored': ('Ignored', Icons.block),
  };

  Widget _history(List<Json> list) {
    if (list.isEmpty) {
      return const EmptyView(Icons.history, 'No history for this episode');
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final h = list[i];
        final ev =
            _events['${h['eventType']}'] ??
            ('${h['eventType']}', Icons.history);
        final date = DateTime.tryParse('${h['date']}')?.toLocal();
        final quality = (h['quality'] as Map?)?['quality']?['name'];
        final data = h['data'] is Map ? h['data'] as Map : const {};
        return ListTile(
          leading: Icon(ev.$2),
          title: Text(ev.$1),
          subtitle: Text(
            [
              '${h['sourceTitle'] ?? ''}',
              if (quality != null) '$quality',
              if (data['indexer'] != null) '${data['indexer']}',
              if (data['downloadClientName'] != null)
                '${data['downloadClientName']}',
            ].join('\n'),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          trailing: date == null
              ? null
              : Text(
                  DateFormat('MMM d, y\nHH:mm').format(date),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
        );
      },
    );
  }
}
