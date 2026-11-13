import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'demo_client.dart';
import 'settings.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

typedef Json = Map<String, dynamic>;

/// Sonarr API client. Tries the primary URL first and falls back to the
/// secondary URL when the primary is unreachable.
class SonarrApi {
  final ServerConfig config;
  final http.Client _client;
  static const _timeout = Duration(seconds: 12);

  String? _activeBase;
  final Map<String, String> _versionByBase = {};

  SonarrApi(this.config, {http.Client? client})
    : _client =
          client ?? (config.isDemo ? DemoServer().client() : http.Client());

  bool get isDemo => config.isDemo;

  List<String> get _bases => [
    ?_activeBase,
    for (final u in [config.primaryUrl, config.secondaryUrl])
      if (u.isNotEmpty && u != _activeBase) u,
  ];

  String? get activeBase => _activeBase;

  Map<String, String> get headers => {
    'X-Api-Key': config.apiKey,
    'Accept': 'application/json',
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
    'Content-Type': 'application/json',
  };

  /// Absolute URL for a relative asset path (e.g. series images).
  String assetUrl(String path) {
    if (path.startsWith('http')) return path;
    final base = _activeBase ?? config.primaryUrl;
    final sep = path.contains('?') ? '&' : '?';
    return '$base$path${sep}apikey=${config.apiKey}';
  }

  Future<String> _version(String base) async {
    final cached = _versionByBase[base];
    if (cached != null) return cached;
    var v = 'v3';
    try {
      final r = await _client
          .get(Uri.parse('$base/api'), headers: headers)
          .timeout(_timeout);
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        if (j is Map && j['current'] is String) v = j['current'] as String;
      }
    } catch (_) {}
    return _versionByBase[base] = v;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Duration timeout = _timeout,
  }) async {
    Object? lastError;
    for (final base in _bases) {
      try {
        final v = await _version(base);
        final uri = Uri.parse('$base/api/$v$path').replace(
          queryParameters: query?.map(
            (k, val) =>
                MapEntry(k, val is List ? [for (final e in val) '$e'] : '$val'),
          ),
        );
        final req = http.Request(method, uri)..headers.addAll(headers);
        if (body != null) req.body = jsonEncode(body);
        final res = await http.Response.fromStream(
          await _client.send(req).timeout(timeout),
        );
        _activeBase = base;
        if (res.statusCode == 401) {
          throw ApiException('Invalid API key', 401);
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw ApiException(_errorMessage(res), res.statusCode);
        }
        if (res.body.isEmpty) return null;
        return jsonDecode(utf8.decode(res.bodyBytes));
      } on ApiException {
        rethrow;
      } on Exception catch (e) {
        lastError = e;
      }
    }
    throw ApiException('Could not reach Sonarr (${lastError ?? 'no URL'})');
  }

  String _errorMessage(http.Response res) {
    try {
      final j = jsonDecode(res.body);
      if (j is List && j.isNotEmpty && j.first is Map) {
        return (j.first['errorMessage'] ?? 'Error ${res.statusCode}')
            .toString();
      }
      if (j is Map && j['message'] != null) return j['message'].toString();
    } catch (_) {}
    return 'Request failed (${res.statusCode})';
  }

  // ---- System ----
  Future<Json> systemStatus() async =>
      Json.from(await _send('GET', '/system/status'));
  Future<List<Json>> health() async => _list(await _send('GET', '/health'));
  Future<List<Json>> diskSpace() async =>
      _list(await _send('GET', '/diskspace'));

  // ---- Series ----
  Future<List<Json>> series() async => _list(await _send('GET', '/series'));

  Future<Json> seriesById(int id) async =>
      Json.from(await _send('GET', '/series/$id'));

  Future<List<Json>> lookup(String term) async =>
      _list(await _send('GET', '/series/lookup', query: {'term': term}));

  Future<Json> addSeries(Json body) async =>
      Json.from(await _send('POST', '/series', body: body));

  Future<Json> updateSeries(Json body) async =>
      Json.from(await _send('PUT', '/series/${body['id']}', body: body));

  Future<void> deleteSeries(int id, {bool deleteFiles = false}) async {
    await _send('DELETE', '/series/$id', query: {'deleteFiles': deleteFiles});
  }

  Future<List<Json>> rootFolders() async =>
      _list(await _send('GET', '/rootfolder'));

  Future<List<Json>> qualityProfiles() async =>
      _list(await _send('GET', '/qualityprofile'));

  // ---- Episodes ----
  Future<List<Json>> episodes(int seriesId) async => _list(
    await _send(
      'GET',
      '/episode',
      query: {
        'seriesId': seriesId,
        'includeEpisodeFile': true,
        'includeSubresources': ['episodeFile'],
      },
    ),
  ).map(_normalizeEpisode).toList();

  Future<Json> updateEpisode(Json body) async =>
      Json.from(await _send('PUT', '/episode/${body['id']}', body: body));

  Future<List<Json>> calendar(DateTime start, DateTime end) async => _list(
    await _send(
      'GET',
      '/calendar',
      query: {
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        'includeSeries': true,
        'includeSubresources': ['series', 'episodeFile'],
      },
    ),
  ).map(_normalizeEpisode).toList();

  // ---- Episode files / history ----
  Future<void> deleteEpisodeFile(int id) async {
    await _send('DELETE', '/episodefile/$id');
  }

  Future<List<Json>> episodeHistory(int episodeId) async {
    final r = await _send(
      'GET',
      '/history',
      query: {
        'page': 1,
        'pageSize': 100,
        'sortKey': 'date',
        'sortDirection': 'descending',
        'episodeId': episodeId,
      },
    );
    return _list(r is Map ? r['records'] : r);
  }

  Future<Json> episodeById(int id) async => _normalizeEpisode(
    Json.from(
      await _send('GET', '/episode/$id', query: {'includeEpisodeFile': true}),
    ),
  );

  // ---- Manual search ----
  // Indexer queries can take minutes, so use a generous timeout.
  static const releaseTimeout = Duration(minutes: 5);

  Future<List<Json>> releases(int episodeId) =>
      _releases({'episodeId': episodeId});

  /// Interactive search for a whole season (season packs and single episodes).
  Future<List<Json>> seasonReleases(int seriesId, int seasonNumber) =>
      _releases({'seriesId': seriesId, 'seasonNumber': seasonNumber});

  Future<List<Json>> _releases(Map<String, dynamic> query) async => _list(
    await _send('GET', '/release', query: query, timeout: releaseTimeout),
  ).map(_flattenRelease).toList();

  /// Newer Sonarr versions nest the release under `release`, the verdict under
  /// `decision` and the quality under `parsedInfo`; older ones return it flat.
  /// Normalizes both into the flat shape the UI reads.
  static Json _flattenRelease(Json r) {
    final nested = r['release'];
    if (nested is! Map) return r;
    final decision = r['decision'];
    final parsed = r['parsedInfo'];
    return {
      ...r,
      ...Json.from(nested),
      if (parsed is Map && parsed['quality'] != null)
        'quality': parsed['quality'],
      if (decision is Map) ...{
        'rejected': decision['rejected'] == true,
        'rejections': [
          for (final x in decision['rejections'] as List? ?? [])
            x is Map ? x['message'] : x,
        ],
      },
    };
  }

  /// v5 replaced `audioCodec`/`audioChannels`/`subtitles` in `mediaInfo` with
  /// `audioStreams`/`subtitleStreams`; fill the old keys the UI reads.
  static Json _normalizeEpisode(Json e) {
    final file = e['episodeFile'];
    final media = file is Map ? file['mediaInfo'] : null;
    if (media is! Map || media['audioCodec'] != null) return e;
    final audio = (media['audioStreams'] as List? ?? []).whereType<Map>();
    final subs = (media['subtitleStreams'] as List? ?? []).whereType<Map>();
    final langs = {
      for (final s in subs)
        if ('${s['language'] ?? ''}'.isNotEmpty) '${s['language']}',
    };
    return {
      ...e,
      'episodeFile': {
        ...Json.from(file as Map),
        'mediaInfo': {
          ...Json.from(media),
          if (audio.isNotEmpty) ...{
            'audioCodec': audio.first['codec'],
            'audioChannels': audio.first['channels'],
          },
          if (langs.isNotEmpty) 'subtitles': langs.join(' / '),
        },
      },
    };
  }

  /// v5 renamed `sizeleft`/`timeleft` and replaced `episode` with `episodes`.
  static Json _normalizeQueueItem(Json q) {
    final eps = q['episodes'];
    return {
      ...q,
      if (q['sizeleft'] == null && q['sizeLeft'] != null)
        'sizeleft': q['sizeLeft'],
      if (q['timeleft'] == null && q['timeLeft'] != null)
        'timeleft': q['timeLeft'],
      if (q['episode'] == null && eps is List && eps.isNotEmpty)
        'episode': eps.first,
    };
  }

  Future<void> grabRelease(String guid, int indexerId) async {
    await _send(
      'POST',
      '/release',
      body: {'guid': guid, 'indexerId': indexerId},
      timeout: releaseTimeout,
    );
  }

  // ---- Activity ----
  Future<List<Json>> queue() async {
    final r = await _send(
      'GET',
      '/queue',
      query: {
        'page': 1,
        'pageSize': 100,
        'includeSeries': true,
        'includeEpisode': true,
        'includeUnknownSeriesItems': true,
        'includeSubresources': ['series', 'episodes'],
      },
    );
    return _list(r is Map ? r['records'] : r).map(_normalizeQueueItem).toList();
  }

  Future<int> queueCount() async {
    final r = await _send('GET', '/queue/status');
    return (r is Map ? r['totalCount'] as num? : null)?.toInt() ?? 0;
  }

  Future<void> removeQueueItem(int id, {bool blocklist = false}) async {
    await _send(
      'DELETE',
      '/queue/$id',
      query: {
        'removeFromClient': true,
        'blocklist': blocklist,
        // Sonarr v5 replaced the two flags above with these (required there,
        // ignored by older versions).
        'removalMethod': 'removeFromClient',
        'blocklistMethod': blocklist ? 'blocklistAndSearch' : 'doNotBlocklist',
      },
    );
  }

  /// Files Sonarr found for a download that needs manual import
  /// (the web UI's "Interactive Import").
  /// Resolving by [downloadId] lets Sonarr match the series like the web UI
  /// does, but it fails when the client reports no output path; in that case
  /// (or when it finds nothing) the download's [folder] is used instead.
  Future<List<Json>> manualImportCandidates({
    String? folder,
    String? downloadId,
  }) async {
    Future<List<Json>> fetch(Map<String, dynamic> q) async => _list(
      await _send(
        'GET',
        '/manualimport',
        query: {...q, 'filterExistingFiles': false},
      ),
    );

    final hasFolder = folder != null && folder.trim().isNotEmpty;
    if (downloadId != null && downloadId.isNotEmpty) {
      try {
        final r = await fetch({
          'downloadId': downloadId,
          'downloadIds': [downloadId],
        });
        if (r.isNotEmpty || !hasFolder) return r;
      } on ApiException {
        if (!hasFolder) rethrow;
      }
    }
    return fetch({'folder': folder});
  }

  /// Series/episodes Sonarr infers from a release title.
  Future<Json> parse(String title) async =>
      Json.from(await _send('GET', '/parse', query: {'title': title}));

  Future<void> manualImport(List<Json> files, {String mode = 'auto'}) =>
      command('ManualImport', {'files': files, 'importMode': mode});

  Future<List<Json>> qualityDefinitions() async =>
      _list(await _send('GET', '/qualitydefinition'));

  Future<List<Json>> languages() async =>
      _list(await _send('GET', '/language'));

  Future<List<Json>> history({int pageSize = 50}) async {
    final r = await _send(
      'GET',
      '/history',
      query: {
        'page': 1,
        'pageSize': pageSize,
        'sortKey': 'date',
        'sortDirection': 'descending',
        'includeSeries': true,
        'includeEpisode': true,
        'includeSubresources': ['series', 'episode'],
      },
    );
    return _list(r is Map ? r['records'] : r);
  }

  Future<List<Json>> missing({int page = 1, int pageSize = 50}) =>
      _wanted('missing', page, pageSize);

  /// Episodes whose file quality is below the profile's cutoff.
  Future<List<Json>> cutoffUnmet({int page = 1, int pageSize = 50}) =>
      _wanted('cutoff', page, pageSize);

  Future<List<Json>> _wanted(String kind, int page, int pageSize) async {
    final r = await _send(
      'GET',
      '/wanted/$kind',
      query: {
        'page': page,
        'pageSize': pageSize,
        'sortKey': 'airDateUtc',
        'sortDirection': 'descending',
        'monitored': true,
        'includeSeries': true,
        'includeSubresources': kind == 'missing'
            ? ['series']
            : ['series', 'episodeFile'],
      },
    );
    return _list(r is Map ? r['records'] : r).map(_normalizeEpisode).toList();
  }

  // ---- Commands ----
  Future<void> command(String name, [Json extra = const {}]) async {
    await _send('POST', '/command', body: {'name': name, ...extra});
  }

  Future<void> searchSeries(int seriesId) =>
      command('SeriesSearch', {'seriesId': seriesId});
  Future<void> searchSeason(int seriesId, int season) =>
      command('SeasonSearch', {'seriesId': seriesId, 'seasonNumber': season});
  Future<void> searchEpisodes(List<int> ids) =>
      command('EpisodeSearch', {'episodeIds': ids});
  Future<void> refreshSeries(int seriesId) =>
      command('RefreshSeries', {'seriesId': seriesId});
  Future<void> searchMissing() => command('MissingEpisodeSearch');
  Future<void> searchCutoffUnmet() => command('CutoffUnmetEpisodeSearch');

  List<Json> _list(dynamic v) =>
      (v as List? ?? const []).map((e) => Json.from(e as Map)).toList();

  void dispose() => _client.close();
}
