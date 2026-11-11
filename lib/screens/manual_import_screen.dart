import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

/// True when a queue item is waiting for the user to resolve the import
/// (Sonarr state `importBlocked`/`importPending`, or a warning on a finished
/// download).
bool needsManualImport(Json q) {
  final state = '${q['trackedDownloadState']}';
  final warning = q['trackedDownloadStatus'] == 'warning';
  return q['downloadId'] != null &&
      (state == 'importBlocked' ||
          (warning && (state == 'importPending' || state == 'importFailed')));
}

/// Mobile version of Sonarr's "Interactive Import" for a queue item.
class ManualImportScreen extends StatefulWidget {
  final Json queueItem;
  const ManualImportScreen({super.key, required this.queueItem});

  @override
  State<ManualImportScreen> createState() => _ManualImportScreenState();
}

class _ManualImportScreenState extends State<ManualImportScreen> {
  List<Json>? _files;
  List<Json> _qualities = [];
  List<Json> _languages = [];
  final _selected = <int>{};
  Object? _error;
  var _importing = false;

  SonarrApi get _api => context.read<AppState>().api!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _files = null;
      _error = null;
    });
    try {
      final api = _api;
      final results = await Future.wait([
        api.manualImportCandidates(
          folder: widget.queueItem['outputPath'] as String?,
          downloadId: widget.queueItem['downloadId'] as String?,
        ),
        api.qualityDefinitions(),
        api.languages(),
      ]);
      final prefill = await _queueSeries(api, results[0]);
      if (!mounted) return;
      setState(() {
        _files = results[0];
        _qualities = [
          for (final d in results[1])
            if (d['quality'] is Map) Json.from(d['quality'] as Map),
        ];
        _languages = results[2].where((l) => (l['id'] as num) >= 0).toList();
        for (final f in _files!) {
          f['series'] ??= prefill;
        }
        _selected
          ..clear()
          ..addAll([
            for (var i = 0; i < _files!.length; i++)
              if (_ready(_files![i])) i,
          ]);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Series for files Sonarr could not match: the queue item's series, found
  /// by its embedded object, its id, or by parsing the release title.
  Future<Json?> _queueSeries(SonarrApi api, List<Json> files) async {
    if (files.every((f) => f['series'] != null)) return null;
    final q = widget.queueItem;
    if (q['series'] is Map) return Json.from(q['series'] as Map);
    try {
      final id = q['seriesId'];
      if (id is int) {
        return (await api.series()).where((s) => s['id'] == id).firstOrNull;
      }
      final parsed = await api.parse('${q['title']}');
      if (parsed['series'] is Map) return Json.from(parsed['series'] as Map);
    } catch (_) {}
    return null;
  }

  /// Sonarr's queue status messages are titled with the file they refer to.
  List<String> _errors(int i, Json f) {
    final msgs = (widget.queueItem['statusMessages'] as List? ?? const [])
        .map((m) => m as Map)
        .toList();
    String base(Object? p) => '$p'.split(RegExp(r'[\\/]')).last.toLowerCase();
    final names = {base(f['name']), base(f['relativePath']), base(f['path'])}
      ..remove('null');
    var mine = [
      for (final m in msgs)
        if (names.contains(base(m['title']))) m,
    ];
    if (mine.isEmpty && msgs.length == _files!.length) mine = [msgs[i]];
    final out = [
      for (final m in mine)
        ...(m['messages'] as List? ?? const []).map((e) => '$e'),
    ];
    if (out.isNotEmpty) return out;
    return [
      for (final r in (f['rejections'] as List? ?? const []))
        '${(r as Map)['reason']}',
    ];
  }

  bool _ready(Json f) =>
      f['series'] != null &&
      ((f['episodes'] as List?)?.isNotEmpty ?? false) &&
      f['quality'] != null;

  Future<void> _import() async {
    final files = _files!;
    final payload = <Json>[
      for (final i in _selected)
        {
          'path': files[i]['path'],
          'seriesId': (files[i]['series'] as Map)['id'],
          'episodeIds': [
            for (final e in files[i]['episodes'] as List) (e as Map)['id'],
          ],
          'quality': files[i]['quality'],
          'languages': files[i]['languages'] ?? const [],
          'releaseGroup': files[i]['releaseGroup'],
          'downloadId':
              files[i]['downloadId'] ?? widget.queueItem['downloadId'],
          if (files[i]['indexerFlags'] != null)
            'indexerFlags': files[i]['indexerFlags'],
          if (files[i]['releaseType'] != null)
            'releaseType': files[i]['releaseType'],
        },
    ];
    setState(() => _importing = true);
    try {
      await _api.manualImport(payload);
      if (!mounted) return;
      toast(context, 'Import started');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        toast(context, '$e');
      }
    }
  }

  Future<void> _pickSeries(Json f) async {
    final all = await _api.series();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SeriesPicker(series: all),
    );
    if (chosen == null) return;
    setState(() {
      f['series'] = chosen;
      f['seasonNumber'] = null;
      f['episodes'] = <Json>[];
    });
    await _pickEpisodes(f);
  }

  Future<void> _pickEpisodes(Json f) async {
    final series = f['series'] as Map?;
    if (series == null) return;
    final List<Json> eps;
    try {
      eps = await _api.episodes(series['id'] as int);
    } catch (e) {
      if (mounted) toast(context, '$e');
      return;
    }
    if (!mounted) return;
    final current = {
      for (final e in (f['episodes'] as List? ?? const [])) (e as Map)['id'],
    };
    final chosen = await showModalBottomSheet<List<Json>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EpisodePicker(episodes: eps, selectedIds: current),
    );
    if (chosen == null) return;
    setState(() {
      f['episodes'] = chosen;
      if (chosen.isNotEmpty) f['seasonNumber'] = chosen.first['seasonNumber'];
    });
  }

  Future<void> _pickOption(
    String title,
    List<Json> options,
    ValueChanged<Json> onPick,
  ) async {
    final chosen = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, scroll) => ListView(
          controller: scroll,
          children: [
            ListTile(
              title: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final o in options)
              ListTile(
                title: Text('${o['name']}'),
                onTap: () => Navigator.pop(ctx, o),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) setState(() => onPick(chosen));
  }

  Future<void> _pickLanguages(Json f) async {
    final ids = {
      for (final l in (f['languages'] as List? ?? const [])) (l as Map)['id'],
    };
    final chosen = await showModalBottomSheet<List<Json>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    for (final l in _languages)
                      CheckboxListTile(
                        title: Text('${l['name']}'),
                        value: ids.contains(l['id']),
                        onChanged: (v) => setS(
                          () => v == true
                              ? ids.add(l['id'])
                              : ids.remove(l['id']),
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, [
                        for (final l in _languages)
                          if (ids.contains(l['id'])) l,
                      ]),
                      child: const Text('Done'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) setState(() => f['languages'] = chosen);
  }

  String _qualityName(Json f) =>
      (((f['quality'] as Map?)?['quality']) as Map?)?['name']?.toString() ??
      'Unknown';

  String _languageName(Json f) {
    final l = f['languages'] as List? ?? const [];
    return l.isEmpty ? 'Unknown' : l.map((e) => (e as Map)['name']).join(', ');
  }

  Widget _fileCard(int i, Json f) {
    final theme = Theme.of(context);
    final series = f['series'] as Map?;
    final eps = (f['episodes'] as List? ?? const [])
        .map((e) => Json.from(e as Map))
        .toList();
    final rejections = _errors(i, f);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _selected.contains(i),
                  onChanged: _ready(f)
                      ? (v) => setState(
                          () => v == true
                              ? _selected.add(i)
                              : _selected.remove(i),
                        )
                      : null,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      '${f['relativePath'] ?? f['name'] ?? f['path']}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (f['size'] != null)
                    Text(
                      formatBytes(f['size'] as num),
                      style: theme.textTheme.labelSmall,
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.tv, size: 16),
                        label: Text('${series?['title'] ?? 'Select series'}'),
                        onPressed: () => _pickSeries(f),
                      ),
                      ActionChip(
                        avatar: const Icon(
                          Icons.format_list_numbered,
                          size: 16,
                        ),
                        label: Text(
                          eps.isEmpty
                              ? 'Select episodes'
                              : eps.map(episodeCode).join(', '),
                        ),
                        onPressed: series == null
                            ? null
                            : () => _pickEpisodes(f),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.high_quality, size: 16),
                        label: Text(_qualityName(f)),
                        onPressed: () => _pickOption(
                          'Quality',
                          _qualities,
                          (q) => f['quality'] = {
                            'quality': q,
                            'revision':
                                (f['quality'] as Map?)?['revision'] ??
                                {'version': 1, 'real': 0, 'isRepack': false},
                          },
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.language, size: 16),
                        label: Text(_languageName(f)),
                        onPressed: () => _pickLanguages(f),
                      ),
                    ],
                  ),
                  for (final r in rejections)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber,
                            size: 14,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              r,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.queueItem;
    final files = _files;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual import'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : files == null
          ? const Center(child: CircularProgressIndicator())
          : files.isEmpty
          ? const EmptyView(Icons.folder_off_outlined, 'No files to import')
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${q['title']}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < files.length; i++) _fileCard(i, files[i]),
              ],
            ),
      bottomNavigationBar: files == null || files.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _selected.isEmpty || _importing
                            ? null
                            : _import,
                        icon: _importing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_done),
                        label: Text('Import (${_selected.length})'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SeriesPicker extends StatefulWidget {
  final List<Json> series;
  const _SeriesPicker({required this.series});

  @override
  State<_SeriesPicker> createState() => _SeriesPickerState();
}

class _SeriesPickerState extends State<_SeriesPicker> {
  var _term = '';

  @override
  Widget build(BuildContext context) {
    final list =
        [
          for (final s in widget.series)
            if ('${s['title']}'.toLowerCase().contains(_term.toLowerCase())) s,
        ]..sort(
          (a, b) => '${a['sortTitle'] ?? a['title']}'.compareTo(
            '${b['sortTitle'] ?? b['title']}',
          ),
        );
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search series',
                ),
                onChanged: (v) => setState(() => _term = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text('${list[i]['title']}'),
                  subtitle: list[i]['year'] == null
                      ? null
                      : Text('${list[i]['year']}'),
                  onTap: () => Navigator.pop(context, list[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _airDate(Json e) {
  final d = (e['airDate'] ?? e['airDateUtc'])?.toString();
  return d == null || d.length < 10 ? null : d.substring(0, 10);
}

class _EpisodePicker extends StatefulWidget {
  final List<Json> episodes;
  final Set<Object?> selectedIds;
  const _EpisodePicker({required this.episodes, required this.selectedIds});

  @override
  State<_EpisodePicker> createState() => _EpisodePickerState();
}

class _EpisodePickerState extends State<_EpisodePicker> {
  late final Set<Object?> _ids = {...widget.selectedIds};

  @override
  Widget build(BuildContext context) {
    final bySeason = <int, List<Json>>{};
    for (final e in widget.episodes) {
      bySeason.putIfAbsent(e['seasonNumber'] as int, () => []).add(e);
    }
    final seasons = bySeason.keys.toList()..sort();
    final firstSelected = [
      for (final e in widget.episodes)
        if (_ids.contains(e['id'])) e['seasonNumber'],
    ].firstOrNull;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                for (final s in seasons)
                  ExpansionTile(
                    title: Text(s == 0 ? 'Specials' : 'Season $s'),
                    initiallyExpanded: s == firstSelected,
                    children: [
                      for (final e in bySeason[s]!)
                        CheckboxListTile(
                          dense: true,
                          value: _ids.contains(e['id']),
                          title: Text(
                            '${e['episodeNumber']}. ${e['title'] ?? ''}',
                          ),
                          subtitle: _airDate(e) == null
                              ? null
                              : Text('Aired ${_airDate(e)}'),
                          onChanged: (v) => setState(
                            () => v == true
                                ? _ids.add(e['id'])
                                : _ids.remove(e['id']),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, [
                    for (final e in widget.episodes)
                      if (_ids.contains(e['id'])) e,
                  ]),
                  child: Text('Done (${_ids.length})'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
