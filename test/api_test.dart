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
