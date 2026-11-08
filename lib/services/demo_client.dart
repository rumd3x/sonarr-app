import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory fake Sonarr server used by demo mode. It answers the same
/// endpoints as the real API, so every screen works without a server.
class DemoServer {
  static const url = 'http://demo.sonarr.local';

  final DateTime _now = DateTime.now();
  final List<Map<String, dynamic>> _series = [];
  final Map<int, List<Map<String, dynamic>>> _episodes = {};
  final List<Map<String, dynamic>> _queue = [];
  final List<Map<String, dynamic>> _history = [];
  var _nextId = 100;

  DemoServer() {
    _seed();
  }

  http.Client client() => MockClient(_handle);

  static const _specs = [
    (
      'Starfall Station',
      2021,
      'Orbit TV',
      'continuing',
      3,
      8,
      'A crew of engineers keeps a failing deep-space station alive while '
          'uncovering why its original builders vanished.',
      'Sci-Fi',
    ),
    (
      'The Lighthouse Files',
      2018,
      'Coastline',
      'ended',
      4,
      6,
      'A retired detective reopens cold cases from a remote island '
          'lighthouse, one tape recording at a time.',
      'Mystery',
    ),
    (
      'Midnight Kitchen',
      2022,
      'Foodies',
      'continuing',
      2,
      10,
      'Chefs compete after dark in a hidden kitchen where the only rule is '
          'that every dish must tell a story.',
      'Reality',
    ),
    (
      'Northern Lines',
      2019,
      'Rail One',
      'continuing',
      3,
      8,
      'Rival railway families fight to connect a frozen frontier at the '
          'dawn of the steam age.',
      'Drama',
    ),
    (
      'Paper Tigers',
      2016,
      'Studio 9',
      'ended',
      5,
      8,
      'Two struggling comic artists turn a basement hobby into a '
          'publishing empire.',
      'Comedy',
    ),
    (
      'Echo Valley',
      2023,
      'Orbit TV',
      'continuing',
      1,
      8,
      'Strange sounds echo through a mountain town, and only the new '
          'sheriff seems to hear them.',
      'Thriller',
    ),
  ];

  void _seed() {
    var id = 1;
    for (final (
          title,
          year,
          network,
          status,
          seasons,
          perSeason,
          overview,
          genre,
        )
        in _specs) {
      final sid = id++;
      final eps = <Map<String, dynamic>>[];
      for (var s = 1; s <= seasons; s++) {
        final last = s == seasons;
        for (var n = 1; n <= perSeason; n++) {
          final DateTime air;
          if (status == 'continuing' && last) {
            air = _now.add(Duration(days: (n - 4) * 7 - 1));
          } else {
            air = _now.subtract(
              Duration(days: 400 + (seasons - s) * 365 - n * 7),
            );
          }
          final aired = air.isBefore(_now);
          final missing = aired && last && status == 'continuing' && n % 4 == 0;
          final fid = _nextId++;
          eps.add({
            'id': _nextId++,
            'seriesId': sid,
            'seasonNumber': s,
            'episodeNumber': n,
            'title': _episodeTitle(sid, s, n),
            'overview':
                'Episode $n of season $s. The story moves forward as new '
                'secrets come to light.',
            'airDateUtc': air.toUtc().toIso8601String(),
            'runtime': 45,
            'monitored': true,
            'hasFile': aired && !missing,
            if (aired && !missing)
              'episodeFile': {
                'id': fid,
                'relativePath':
                    'Season ${s.toString().padLeft(2, '0')}/'
                    '$title - S${_p(s)}E${_p(n)}.mkv',
                'path':
                    '/media/tv/$title/Season ${_p(s)}/'
                    '$title - S${_p(s)}E${_p(n)}.mkv',
                'size': 1500000000 + n * 90000000,
                'dateAdded': air
                    .add(const Duration(hours: 2))
                    .toUtc()
                    .toIso8601String(),
                'releaseGroup': 'DEMO',
                'quality': {
                  'quality': {'id': 7, 'name': 'WEBDL-1080p'},
                },
                'languages': [
                  {'id': 1, 'name': 'English'},
                ],
                'mediaInfo': {
                  'videoCodec': 'x265',
                  'audioCodec': 'EAC3',
                  'audioChannels': 5.1,
                  'resolution': '1920x1080',
                  'runTime': '45:00',
                },
              },
          });
        }
      }
      _episodes[sid] = eps;
      _series.add({
        'id': sid,
        'title': title,
        'sortTitle': title.toLowerCase(),
        'year': year,
        'status': status,
        'network': network,
        'overview': overview,
        'runtime': 45,
        'genres': [genre],
        'monitored': true,
        'seasonFolder': true,
        'qualityProfileId': 1,
        'path': '/media/tv/$title',
        'added': _now.subtract(Duration(days: 200 - sid * 9)).toIso8601String(),
        'images': const [],
        'seasons': [
          for (var s = 1; s <= seasons; s++)
            {'seasonNumber': s, 'monitored': true},
        ],
      });
    }

    final starfall = _episodes[1]!;
    final queued = starfall.where((e) => e['hasFile'] != true).toList();
    for (var i = 0; i < queued.length && i < 2; i++) {
      final e = queued[i];
      final size = 2100000000 + i * 300000000;
      _queue.add({
        'id': 500 + i,
        'title':
            'Starfall.Station.S${_p(e['seasonNumber'] as int)}'
            'E${_p(e['episodeNumber'] as int)}.1080p.WEB-DL',
        'status': 'downloading',
        'size': size,
        'sizeleft': (size * (0.65 - i * 0.4)).round(),
        'timeleft': i == 0 ? '00:12:40' : '00:41:05',
        'downloadClient': 'qBittorrent',
        'series': _series[0],
        'episode': e,
      });
    }

    for (final e in starfall.where((e) => e['hasFile'] == true).take(6)) {
      _history.add({
        'id': _nextId++,
        'eventType': 'downloadFolderImported',
        'sourceTitle':
            'Starfall.Station.S${_p(e['seasonNumber'] as int)}'
            'E${_p(e['episodeNumber'] as int)}.1080p.WEB-DL',
        'date': e['airDateUtc'],
        'episodeId': e['id'],
        'seriesId': 1,
        'quality': {
          'quality': {'id': 7, 'name': 'WEBDL-1080p'},
        },
        'data': {
          'indexer': 'Demo Indexer',
          'downloadClientName': 'qBittorrent',
        },
        'series': _series[0],
        'episode': e,
      });
    }
  }

  static const _titles = [
    'Pilot',
    'Signal Lost',
    'The Long Night',
    'Breaking Point',
    'Old Debts',
    'Crossing Over',
    'Fault Lines',
    'The Reckoning',
    'Silent Hours',
    'Homecoming',
  ];

  String _episodeTitle(int sid, int s, int n) =>
      (s == 1 && n == 1) ? 'Pilot' : _titles[(sid + s + n) % _titles.length];

  static String _p(int n) => n.toString().padLeft(2, '0');

  Map<String, dynamic> _withStats(Map<String, dynamic> s) {
    final eps = _episodes[s['id']] ?? const [];
    final aired = eps.where(
      (e) => DateTime.parse(e['airDateUtc'] as String).isBefore(_now),
    );
    final files = eps.where((e) => e['hasFile'] == true);
    final seasons = (s['seasons'] as List).map((raw) {
      final se = Map<String, dynamic>.from(raw as Map);
      final sn = se['seasonNumber'];
      final seps = eps.where((e) => e['seasonNumber'] == sn);
      final sfiles = seps.where((e) => e['hasFile'] == true).length;
      final saired = seps
          .where(
            (e) => DateTime.parse(e['airDateUtc'] as String).isBefore(_now),
          )
          .length;
      return {
        ...se,
        'statistics': {
          'episodeFileCount': sfiles,
          'episodeCount': saired,
          'totalEpisodeCount': seps.length,
          'percentOfEpisodes': saired == 0 ? 0.0 : sfiles * 100.0 / saired,
        },
      };
    }).toList();
    return {
      ...s,
      'seasons': seasons,
      'statistics': {
        'seasonCount': seasons.length,
        'episodeFileCount': files.length,
        'episodeCount': aired.length,
        'totalEpisodeCount': eps.length,
        'sizeOnDisk': files.fold<int>(
          0,
          (a, e) => a + ((e['episodeFile'] as Map)['size'] as int),
        ),
        'percentOfEpisodes': aired.isEmpty
            ? 0.0
            : files.length * 100.0 / aired.length,
      },
    };
  }

  Map<String, dynamic> _episodeOut(Map<String, dynamic> e) {
    final s = _series.firstWhere((s) => s['id'] == e['seriesId']);
    return {...e, 'series': _withStats(s)};
  }

  http.Response _json(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<http.Response> _handle(http.Request req) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final path = req.url.path;
    final q = req.url.queryParameters;
    final m = req.method;
    final body = req.body.isEmpty ? null : jsonDecode(req.body);

    if (path == '/api') return _json({'current': 'v3'});
    final p = path.replaceFirst('/api/v3', '');

    switch (p) {
      case '/system/status':
        return _json({'appName': 'Sonarr', 'version': '4.0.0.0 (demo)'});
      case '/health':
        return _json([
          {
            'type': 'warning',
            'source': 'IndexerStatusCheck',
            'message': 'Demo Indexer unavailable due to failures (sample)',
          },
        ]);
      case '/diskspace':
        return _json([
          {
            'path': '/media/tv',
            'label': 'Media',
            'freeSpace': 1200000000000,
            'totalSpace': 4000000000000,
          },
        ]);
      case '/rootfolder':
        return _json([
          {'id': 1, 'path': '/media/tv', 'freeSpace': 1200000000000},
        ]);
      case '/qualityprofile':
        return _json([
          {'id': 1, 'name': 'HD - 1080p'},
          {'id': 2, 'name': 'Ultra-HD'},
          {'id': 3, 'name': 'Any'},
        ]);
      case '/series':
        if (m == 'POST') {
          final s = {
            ...Map<String, dynamic>.from(body as Map),
            'id': _nextId++,
            'added': _now.toIso8601String(),
            'images': const [],
            'seasons': (body['seasons'] as List? ?? const [])
                .map((e) => {...Map<String, dynamic>.from(e as Map)})
                .toList(),
          };
          _series.add(s);
          _episodes[s['id'] as int] = [];
          return _json(_withStats(s), 201);
        }
        return _json(_series.map(_withStats).toList());
      case '/series/lookup':
        final term = (q['term'] ?? '').toLowerCase();
        return _json([
          for (final t in _lookupCatalog)
            if (term.isEmpty || '${t['title']}'.toLowerCase().contains(term)) t,
        ]);
      case '/episode':
        final sid = int.tryParse(q['seriesId'] ?? '');
        return _json((_episodes[sid] ?? const []).map(_episodeOut).toList());
      case '/calendar':
        final start = DateTime.parse(q['start']!);
        final end = DateTime.parse(q['end']!);
        final out = [
          for (final eps in _episodes.values)
            for (final e in eps)
              if (!DateTime.parse(e['airDateUtc'] as String).isBefore(start) &&
                  DateTime.parse(e['airDateUtc'] as String).isBefore(end))
                _episodeOut(e),
        ]..sort((a, b) => '${a['airDateUtc']}'.compareTo('${b['airDateUtc']}'));
        return _json(out);
      case '/history':
        var list = [..._history];
        if (q['episodeId'] != null) {
          list = list
              .where((h) => '${h['episodeId']}' == q['episodeId'])
              .toList();
        }
        return _json({'page': 1, 'totalRecords': list.length, 'records': list});
      case '/queue':
        return _json({
          'page': 1,
          'totalRecords': _queue.length,
          'records': _queue,
        });
      case '/wanted/missing':
        final recs = [
          for (final eps in _episodes.values)
            for (final e in eps)
              if (e['hasFile'] != true &&
                  e['monitored'] == true &&
                  DateTime.parse(e['airDateUtc'] as String).isBefore(_now))
                _episodeOut(e),
        ];
        return _json({'page': 1, 'totalRecords': recs.length, 'records': recs});
      case '/release':
        if (m == 'POST') return _json({});
        await Future<void>.delayed(const Duration(milliseconds: 900));
        return _json(_releases(int.tryParse(q['episodeId'] ?? '') ?? 0));
      case '/command':
        return _json({'id': _nextId++, 'status': 'queued'}, 201);
    }

    final seriesMatch = RegExp(r'^/series/(\d+)$').firstMatch(p);
    if (seriesMatch != null) {
      final id = int.parse(seriesMatch.group(1)!);
      final idx = _series.indexWhere((s) => s['id'] == id);
      if (idx < 0) return _json({'message': 'Not found'}, 404);
      if (m == 'DELETE') {
        _series.removeAt(idx);
        _episodes.remove(id);
        return _json({});
      }
      if (m == 'PUT') {
        final b = Map<String, dynamic>.from(body as Map);
        _series[idx] = {
          ..._series[idx],
          'monitored': b['monitored'],
          'seasons': b['seasons'],
        };
      }
      return _json(_withStats(_series[idx]));
    }

    final epMatch = RegExp(r'^/episode/(\d+)$').firstMatch(p);
    if (epMatch != null) {
      final id = int.parse(epMatch.group(1)!);
      for (final eps in _episodes.values) {
        final i = eps.indexWhere((e) => e['id'] == id);
        if (i < 0) continue;
        if (m == 'PUT') {
          eps[i] = {...eps[i], 'monitored': (body as Map)['monitored']};
        }
        return _json(_episodeOut(eps[i]));
      }
      return _json({'message': 'Not found'}, 404);
    }

    final fileMatch = RegExp(r'^/episodefile/(\d+)$').firstMatch(p);
    if (fileMatch != null && m == 'DELETE') {
      final id = int.parse(fileMatch.group(1)!);
      for (final eps in _episodes.values) {
        for (var i = 0; i < eps.length; i++) {
          if ((eps[i]['episodeFile'] as Map?)?['id'] == id) {
            eps[i] = {...eps[i], 'hasFile': false}..remove('episodeFile');
          }
        }
      }
      return _json({});
    }

    final queueMatch = RegExp(r'^/queue/(\d+)$').firstMatch(p);
    if (queueMatch != null && m == 'DELETE') {
      final id = int.parse(queueMatch.group(1)!);
      _queue.removeWhere((e) => e['id'] == id);
      return _json({});
    }

    return _json({'message': 'Not found'}, 404);
  }

  List<Map<String, dynamic>> _releases(int episodeId) => [
    for (final (i, r) in const [
      ('1080p WEB-DL', 'WEBDL-1080p', 2300000000, 128, 4, <String>[]),
      ('2160p WEB-DL HDR', 'WEBDL-2160p', 8200000000, 54, 9, <String>[]),
      ('720p HDTV', 'HDTV-720p', 900000000, 12, 30, <String>[]),
      (
        '1080p WEB-DL x264',
        'WEBDL-1080p',
        2000000000,
        0,
        2,
        ['Not an upgrade for existing episode file'],
      ),
    ].indexed)
      {
        'guid': 'demo-$episodeId-$i',
        'indexerId': 1,
        'indexer': 'Demo Indexer',
        'title': 'Sample.Release.${r.$1.replaceAll(' ', '.')}-DEMO',
        'size': r.$3,
        'seeders': r.$4,
        'leechers': r.$4 ~/ 4,
        'age': r.$5,
        'ageHours': r.$5 * 24,
        'protocol': 'torrent',
        'quality': {
          'quality': {'id': 7, 'name': r.$2},
        },
        'languages': [
          {'id': 1, 'name': 'English'},
        ],
        'customFormatScore': 0,
        'rejected': r.$6.isNotEmpty,
        'rejections': r.$6,
      },
  ];

  static final List<Map<String, dynamic>> _lookupCatalog = [
    for (final (i, t) in const [
      ('Harbor Lights', 2020, 'A night-shift crew keeps a busy port running.'),
      ('Glass Orchard', 2017, 'A family inherits an orchard with a secret.'),
      ('Signal Fire', 2024, 'Volunteer firefighters battle more than flames.'),
    ].indexed)
      {
        'title': t.$1,
        'sortTitle': t.$1.toLowerCase(),
        'year': t.$2,
        'overview': t.$3,
        'status': 'continuing',
        'network': 'Demo TV',
        'tvdbId': 900000 + i,
        'titleSlug': t.$1.toLowerCase().replaceAll(' ', '-'),
        'images': const [],
        'seasons': [
          {'seasonNumber': 1, 'monitored': true},
        ],
      },
  ];
}
