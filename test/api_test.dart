import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonarr_app/services/api.dart';
import 'package:sonarr_app/services/settings.dart';

void main() {
  test('normalizeUrl adds scheme and strips trailing slash', () {
    expect(
      ServerConfig.normalizeUrl('192.168.1.2:8989/'),
      'http://192.168.1.2:8989',
    );
    expect(ServerConfig.normalizeUrl(' https://a.b '), 'https://a.b');
    expect(ServerConfig.normalizeUrl(''), '');
  });

  test('falls back to secondary URL and sends API key', () async {
    final seen = <Uri>[];
    String? key;
    final client = MockClient((req) async {
      seen.add(req.url);
      if (req.url.host == 'primary') throw http.ClientException('down');
      key = req.headers['X-Api-Key'];
      if (req.url.path == '/api') return http.Response('{"current":"v3"}', 200);
      return http.Response('{"version":"4.0"}', 200);
    });
    final api = SonarrApi(
      const ServerConfig(
        primaryUrl: 'http://primary',
        secondaryUrl: 'http://secondary',
        apiKey: 'abc',
      ),
      client: client,
    );
    final status = await api.systemStatus();
    expect(status['version'], '4.0');
    expect(key, 'abc');
    expect(api.activeBase, 'http://secondary');
    expect(seen.last.path, '/api/v3/system/status');
  });

  test('manual search lists and grabs releases', () async {
    final calls = <String>[];
    String? grabBody;
    final api = SonarrApi(
      const ServerConfig(primaryUrl: 'http://p', secondaryUrl: '', apiKey: 'k'),
      client: MockClient((r) async {
        if (r.url.path == '/api') return http.Response('{"current":"v3"}', 200);
        calls.add('${r.method} ${r.url.path}?${r.url.query}');
        if (r.method == 'POST') grabBody = r.body;
        return http.Response(
          r.method == 'GET' ? '[{"guid":"g","indexerId":2}]' : '{}',
          200,
        );
      }),
    );
    final list = await api.releases(7);
    await api.grabRelease('g', 2);
    expect(list.single['guid'], 'g');
    expect(calls, ['GET /api/v3/release?episodeId=7', 'POST /api/v3/release?']);
    expect(grabBody, '{"guid":"g","indexerId":2}');
  });

  test(
    'releases flattens the nested v5 shape and keeps the flat v3 one',
    () async {
      SonarrApi apiReturning(String json) => SonarrApi(
        const ServerConfig(
          primaryUrl: 'http://p',
          secondaryUrl: '',
          apiKey: 'k',
        ),
        client: MockClient(
          (r) async => r.url.path == '/api'
              ? http.Response('{"current":"v3"}', 200)
              : http.Response(json, 200),
        ),
      );

      final v5 = (await apiReturning(
        jsonEncode([
          {
            'parsedInfo': {
              'quality': {
                'quality': {'name': 'Bluray-1080p'},
              },
            },
            'release': {
              'guid': 'g5',
              'indexerId': 3,
              'title': 'Show.S01',
              'size': 10,
              'protocol': 'torrent',
            },
            'decision': {
              'rejected': true,
              'rejections': [
                {'message': 'Not an upgrade', 'reason': 'diskNotUpgrade'},
              ],
            },
            'languages': [
              {'name': 'English'},
            ],
            'customFormatScore': 5,
          },
        ]),
      ).releases(1)).single;
      expect(v5['title'], 'Show.S01');
      expect(v5['guid'], 'g5');
      expect(v5['indexerId'], 3);
      expect(v5['quality']['quality']['name'], 'Bluray-1080p');
      expect(v5['rejected'], true);
      expect(v5['rejections'], ['Not an upgrade']);
      expect(v5['customFormatScore'], 5);

      final v3 = (await apiReturning(
        jsonEncode([
          {
            'guid': 'g3',
            'title': 'Show.S01',
            'rejected': true,
            'rejections': ['Not an upgrade'],
          },
        ]),
      ).releases(1)).single;
      expect(v3['title'], 'Show.S01');
      expect(v3['rejections'], ['Not an upgrade']);
    },
  );

  test(
    'sends v5 subresources and normalizes v5 queue and media info',
    () async {
      Uri? wantedUri;
      final api = SonarrApi(
        const ServerConfig(
          primaryUrl: 'http://p',
          secondaryUrl: '',
          apiKey: 'k',
        ),
        client: MockClient((r) async {
          if (r.url.path == '/api') {
            return http.Response('{"current":"v5"}', 200);
          }
          if (r.url.path.endsWith('/wanted/missing')) wantedUri = r.url;
          if (r.url.path.endsWith('/queue')) {
            return http.Response(
              jsonEncode({
                'records': [
                  {
                    'sizeLeft': 5,
                    'timeLeft': '00:01:00',
                    'episodes': [
                      {'id': 9},
                    ],
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'records': [
                {
                  'id': 1,
                  'episodeFile': {
                    'mediaInfo': {
                      'audioStreams': [
                        {'codec': 'AAC', 'channels': 2.0},
                      ],
                      'subtitleStreams': [
                        {'language': 'eng'},
                        {'language': 'por'},
                      ],
                    },
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final missing = (await api.missing()).single;
      expect(wantedUri!.queryParametersAll['includeSubresources'], ['series']);
      final media = missing['episodeFile']['mediaInfo'];
      expect(media['audioCodec'], 'AAC');
      expect(media['audioChannels'], 2.0);
      expect(media['subtitles'], 'eng / por');

      final q = (await api.queue()).single;
      expect(q['sizeleft'], 5);
      expect(q['timeleft'], '00:01:00');
      expect(q['episode'], {'id': 9});
    },
  );

  test('seasonReleases queries by series and season', () async {
    Uri? uri;
    final api = SonarrApi(
      const ServerConfig(primaryUrl: 'http://p', secondaryUrl: '', apiKey: 'k'),
      client: MockClient((r) async {
        if (r.url.path == '/api') {
          return http.Response('{"current":"v3"}', 200);
        }
        uri = r.url;
        return http.Response('[{"guid":"g","indexerId":2}]', 200);
      }),
    );
    final list = await api.seasonReleases(4, 2);
    expect(list.single['guid'], 'g');
    expect(uri!.path, '/api/v3/release');
    expect(uri!.queryParameters, {'seriesId': '4', 'seasonNumber': '2'});
  });

  test('reports invalid API key on 401', () async {
    final api = SonarrApi(
      const ServerConfig(primaryUrl: 'http://p', secondaryUrl: '', apiKey: 'x'),
      client: MockClient((r) async => http.Response('', 401)),
    );
    expect(api.systemStatus(), throwsA(isA<ApiException>()));
  });

  test('demo mode serves sample data without a server', () async {
    final api = SonarrApi(ServerConfig.demo);
    expect(api.isDemo, isTrue);
    final series = await api.series();
    expect(series, isNotEmpty);
    final id = series.first['id'] as int;
    expect((await api.episodes(id)), isNotEmpty);
    expect(await api.queue(), isNotEmpty);
    expect(await api.missing(), isNotEmpty);
    expect(await api.releases(1), isNotEmpty);
    expect(
      await api.calendar(
        DateTime.now(),
        DateTime.now().add(const Duration(days: 30)),
      ),
      isNotEmpty,
    );
    final updated = await api.updateSeries({
      ...series.first,
      'monitored': false,
    });
    expect(updated['monitored'], false);
  });

  test('manualImport posts a ManualImport command', () async {
    Map? body;
    final api = SonarrApi(
      const ServerConfig(primaryUrl: 'http://p', secondaryUrl: '', apiKey: 'k'),
      client: MockClient((req) async {
        if (req.url.path == '/api') {
          return http.Response('{"current":"v3"}', 200);
        }
        body = req.bodyBytes.isEmpty ? null : jsonDecode(req.body) as Map;
        return http.Response('{}', 201);
      }),
    );
    await api.manualImport([
      {'path': '/a.mkv'},
    ], mode: 'copy');
    expect(body!['name'], 'ManualImport');
    expect(body!['importMode'], 'copy');
    expect((body!['files'] as List).length, 1);
  });
}
