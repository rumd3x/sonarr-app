import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';
import '../screens/episode_detail_screen.dart';

String? imageUrl(SonarrApi api, Json item, [String type = 'poster']) {
  final images = item['images'];
  if (images is! List) return null;
  for (final i in images) {
    if (i is Map && i['coverType'] == type) {
      final remote = i['remoteUrl'] as String?;
      if (remote != null && remote.isNotEmpty) return remote;
      final url = i['url'] as String?;
      if (url != null && url.isNotEmpty) return api.assetUrl(url);
    }
  }
  return null;
}

class Poster extends StatelessWidget {
  final Json series;
  final String type;
  final double? width;
  final double? height;
  const Poster(
    this.series, {
    super.key,
    this.type = 'poster',
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppState>().api!;
    final url = imageUrl(api, series, type);
    final cs = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: width,
      height: height,
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.tv, color: cs.onSurfaceVariant),
    );
    if (api.isDemo) return _DemoPoster(series, width, height, type == 'poster');
    if (url == null) return placeholder;
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyView(this.icon, this.text, {super.key});

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      SizedBox(
        height: 360,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text),
          ],
        ),
      ),
    ],
  );
}

/// Loads data with pull-to-refresh, loading and error states.
class AsyncBody<T> extends StatefulWidget {
  final Future<T> Function(SonarrApi api) load;
  final Widget Function(BuildContext context, T data) builder;
  const AsyncBody({super.key, required this.load, required this.builder});

  @override
  State<AsyncBody<T>> createState() => AsyncBodyState<T>();
}

class AsyncBodyState<T> extends State<AsyncBody<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<T> _fetch() => widget.load(context.read<AppState>().api!);

  Future<void> reload() async {
    final f = _fetch();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _future,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snap.hasError) {
        return ErrorView(error: snap.error!, onRetry: reload);
      }
      return RefreshIndicator(
        onRefresh: reload,
        child: widget.builder(context, snap.data as T),
      );
    },
  );
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

String formatBytes(num bytes) {
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
}

void openEpisode(
  BuildContext context,
  Json episode,
  String seriesTitle, {
  int tab = 0,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => EpisodeDetailScreen(
        episode: episode,
        seriesTitle: seriesTitle,
        initialTab: tab,
      ),
    ),
  );
}

class ManualSearchButton extends StatelessWidget {
  final Json episode;
  final String seriesTitle;
  const ManualSearchButton({
    super.key,
    required this.episode,
    required this.seriesTitle,
  });

  @override
  Widget build(BuildContext context) {
    final search = context.watch<AppState>().manualSearches[episode['id']];
    final running = search?.status == ManualSearchStatus.running;
    final ready = search?.status == ManualSearchStatus.done;
    return IconButton(
      tooltip: 'Manual search',
      onPressed: () => openEpisode(context, episode, seriesTitle, tab: 2),
      icon: running
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Badge(
              isLabelVisible: ready,
              smallSize: 8,
              child: const Icon(Icons.manage_search, size: 22),
            ),
    );
  }
}

String episodeCode(Json e) {
  String two(Object? n) => '$n'.padLeft(2, '0');
  return 'S${two(e['seasonNumber'])}E${two(e['episodeNumber'])}';
}

/// Poster stand-in for demo mode, where there are no remote images.
class _DemoPoster extends StatelessWidget {
  final Json series;
  final double? width;
  final double? height;
  final bool showTitle;
  const _DemoPoster(this.series, this.width, this.height, this.showTitle);

  @override
  Widget build(BuildContext context) {
    final title = '${series['title'] ?? '?'}';
    final big = (height ?? 120) > 100;
    final hue = (title.codeUnits.fold<int>(0, (a, b) => a * 31 + b) % 360)
        .toDouble();
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.55, 0.38).toColor(),
            HSLColor.fromAHSL(1, (hue + 40) % 360, 0.6, 0.18).toColor(),
          ],
        ),
      ),
      child: !showTitle
          ? null
          : Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                big || title.isEmpty ? title : title[0],
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: big ? 18 : 22,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
    );
  }
}
