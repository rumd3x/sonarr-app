import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'settings.dart';

enum ManualSearchStatus { running, done, failed }

/// A manual (interactive) release search that runs in the background, so the
/// user can leave the screen and come back to the results later.
class ManualSearch {
  final Object key;
  final String label;
  ManualSearchStatus status = ManualSearchStatus.running;
  List<Json> releases = [];
  Object? error;
  ManualSearch(this.key, this.label);
}

class AppState extends ChangeNotifier {
  /// Keyed by episode id (int) or by [seasonSearchKey] (String).
  final Map<Object, ManualSearch> manualSearches = {};

  static String seasonSearchKey(int seriesId, int season) =>
      's$seriesId:$season';

  /// Starts (or returns the existing) manual search. For an episode [key] is
  /// the episode id; for a season pass [seasonSearchKey] plus [seriesId] and
  /// [seasonNumber].
  ManualSearch manualSearch(
    Object key,
    String label, {
    bool restart = false,
    int? seriesId,
    int? seasonNumber,
  }) {
    final existing = manualSearches[key];
    if (existing != null &&
        !restart &&
        existing.status != ManualSearchStatus.failed) {
      return existing;
    }
    final search = ManualSearch(key, label);
    manualSearches[key] = search;
    final client = api!;
    (seasonNumber != null
            ? client.seasonReleases(seriesId!, seasonNumber)
            : client.releases(key as int))
        .then((r) {
          search.releases = r;
          search.status = ManualSearchStatus.done;
        })
        .catchError((Object e) {
          search.error = e;
          search.status = ManualSearchStatus.failed;
        })
        .whenComplete(notifyListeners);
    notifyListeners();
    return search;
  }

  void clearManualSearch(Object key) {
    manualSearches.remove(key);
    notifyListeners();
  }

  int queueCount = 0;

  /// Refreshes the number of items in the download queue (Activity badge).
  Future<void> refreshQueueCount() async {
    final client = api;
    if (client == null) return;
    try {
      final n = await client.queueCount();
      if (n != queueCount && api == client) {
        queueCount = n;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<Map<int, List>>? _imagesIndex;

  /// Series id -> images, for episodes whose embedded series has no images
  /// (calendar, wanted). Loaded once from the series list.
  Future<Map<int, List>> seriesImages() => _imagesIndex ??= api!
      .series()
      .then(
        (list) => {
          for (final s in list)
            if (s['id'] is int && s['images'] is List)
              s['id'] as int: s['images'] as List,
        },
      )
      .catchError((Object _) {
        _imagesIndex = null;
        return <int, List>{};
      });

  final SettingsStore store;
  ServerConfig? config;
  SonarrApi? api;
  bool loaded = false;

  AppState(this.store);

  Future<void> init() async {
    config = await store.load();
    if (config != null) api = SonarrApi(config!);
    loaded = true;
    notifyListeners();
  }

  Future<void> setConfig(ServerConfig c) async {
    await store.save(c);
    _imagesIndex = null;
    config = await store.load();
    api?.dispose();
    api = config == null ? null : SonarrApi(config!);
    notifyListeners();
  }

  Future<void> reset() async {
    await store.clear();
    _imagesIndex = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_seriesCacheKey);
    manualSearches.clear();
    api?.dispose();
    api = null;
    config = null;
    notifyListeners();
  }

  // Local cache of the series list so the library opens instantly / offline.
  static const _seriesCacheKey = 'cache_series';

  Future<List<Json>?> cachedSeries() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_seriesCacheKey);
    if (s == null) return null;
    try {
      return (jsonDecode(s) as List).map((e) => Json.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheSeries(List<Json> list) async {
    final p = await SharedPreferences.getInstance();
    // Drop bulky fields not needed for the list view.
    final slim = list
        .map(
          (s) => {
            for (final k in [
              'id',
              'title',
              'year',
              'status',
              'network',
              'monitored',
              'images',
              'statistics',
              'seasonCount',
              'sortTitle',
              'added',
            ])
              if (s.containsKey(k)) k: s[k],
          },
        )
        .toList();
    await p.setString(_seriesCacheKey, jsonEncode(slim));
  }
}
