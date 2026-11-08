import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

/// Interactive search for an episode, meant to be embedded in the episode
/// detail screen. The search runs in [AppState] (not here), so it keeps going
/// if the user leaves the screen, and it only starts when the user asks.
class ManualSearchView extends StatefulWidget {
  final int episodeId;
  final String label;
  const ManualSearchView({
    super.key,
    required this.episodeId,
    required this.label,
  });

  @override
  State<ManualSearchView> createState() => _ManualSearchViewState();
}

class _ManualSearchViewState extends State<ManualSearchView> {
  bool _hideRejected = true;
  final Set<String> _grabbing = {};
  final Set<String> _grabbed = {};

  Future<void> _grab(Json r) async {
    final guid = '${r['guid']}';
    final state = context.read<AppState>();
    if (r['rejected'] == true) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Download anyway?'),
          content: Text((r['rejections'] as List? ?? []).join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Grab'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _grabbing.add(guid));
    try {
      await state.api!.grabRelease(guid, r['indexerId'] as int);
      if (mounted) {
        setState(() => _grabbed.add(guid));
        toast(context, 'Sent to download client');
      }
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _grabbing.remove(guid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final search = state.manualSearches[widget.episodeId];
    final running =
        search == null || search.status == ManualSearchStatus.running;
    final all = search?.releases ?? const <Json>[];
    final releases = all
        .where((r) => !_hideRejected || r['rejected'] != true)
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  search == null || running
                      ? ''
                      : '${releases.length} of ${all.length} releases',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              IconButton(
                tooltip: _hideRejected ? 'Show rejected' : 'Hide rejected',
                icon: Icon(
                  _hideRejected ? Icons.filter_alt : Icons.filter_alt_off,
                ),
                onPressed: () => setState(() => _hideRejected = !_hideRejected),
              ),
              IconButton(
                tooltip: 'Search again',
                icon: const Icon(Icons.refresh),
                onPressed: search == null || running
                    ? null
                    : () => state.manualSearch(
                        widget.episodeId,
                        widget.label,
                        restart: true,
                      ),
              ),
            ],
          ),
        ),
        Expanded(
          child: search == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.manage_search, size: 56),
                        const SizedBox(height: 12),
                        const Text(
                          'Search all indexers for releases of this episode.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => state.manualSearch(
                            widget.episodeId,
                            widget.label,
                          ),
                          icon: const Icon(Icons.search),
                          label: const Text('Search indexers'),
                        ),
                      ],
                    ),
                  ),
                )
              : running
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        Text(
                          'Querying indexers…',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'This can take a few minutes. You can leave this screen — '
                          'the search keeps running and results will be here when you come back.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : search.status == ManualSearchStatus.failed
              ? ErrorView(
                  error: search.error!,
                  onRetry: () => state.manualSearch(
                    widget.episodeId,
                    widget.label,
                    restart: true,
                  ),
                )
              : releases.isEmpty
              ? EmptyView(
                  Icons.search_off,
                  all.isEmpty
                      ? 'No releases found'
                      : 'All ${all.length} releases were rejected',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: releases.length,
                  itemBuilder: (_, i) => _ReleaseCard(
                    release: releases[i],
                    grabbing: _grabbing.contains('${releases[i]['guid']}'),
                    grabbed: _grabbed.contains('${releases[i]['guid']}'),
                    onGrab: () => _grab(releases[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  final Json release;
  final bool grabbing;
  final bool grabbed;
  final VoidCallback onGrab;
  const _ReleaseCard({
    required this.release,
    required this.grabbing,
    required this.grabbed,
    required this.onGrab,
  });

  String _age(Json r) {
    final days = (r['age'] as num?)?.toInt() ?? 0;
    if (days > 0) return '${days}d';
    return '${(r['ageHours'] as num?)?.toInt() ?? 0}h';
  }

  @override
  Widget build(BuildContext context) {
    final r = release;
    final rejected = r['rejected'] == true;
    final torrent = r['protocol'] == 'torrent';
    final quality = (r['quality'] as Map?)?['quality']?['name'];
    final languages = (r['languages'] as List? ?? [])
        .map((l) => (l as Map)['name'])
        .where((n) => n != null && n != 'Unknown')
        .join(', ');
    final score = (r['customFormatScore'] as num?)?.toInt() ?? 0;
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: rejected ? cs.errorContainer.withValues(alpha: 0.25) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r['title']}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (quality != null) _Tag('$quality', cs.primary),
                      _Tag(formatBytes((r['size'] as num?) ?? 0), cs.outline),
                      _Tag(_age(r), cs.outline),
                      _Tag('${r['indexer'] ?? ''}', cs.outline),
                      if (torrent)
                        _Tag(
                          '▲${r['seeders'] ?? 0} ▼${r['leechers'] ?? 0}',
                          (r['seeders'] as num? ?? 0) > 0
                              ? Colors.green
                              : Colors.redAccent,
                        )
                      else
                        _Tag('usenet', cs.outline),
                      if (languages.isNotEmpty) _Tag(languages, cs.outline),
                      if (score != 0)
                        _Tag('CF ${score > 0 ? '+' : ''}$score', cs.tertiary),
                    ],
                  ),
                  if (rejected)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        (r['rejections'] as List? ?? []).join(' · '),
                        style: TextStyle(color: cs.error, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            grabbing
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Download',
                    icon: Icon(
                      grabbed ? Icons.check_circle : Icons.download,
                      color: grabbed ? Colors.green : null,
                    ),
                    onPressed: grabbed ? null : onGrab,
                  ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: color)),
  );
}
