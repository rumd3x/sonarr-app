import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api.dart';
import '../widgets/common.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _key = GlobalKey<AsyncBodyState<List<Json>>>();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Calendar'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _key.currentState?.reload(),
        ),
      ],
    ),
    body: AsyncBody<List<Json>>(
      key: _key,
      load: (api) {
        final today = DateTime.now();
        final start = DateTime(today.year, today.month, today.day);
        return api.calendar(
          start.subtract(const Duration(days: 3)),
          start.add(const Duration(days: 30)),
        );
      },
      builder: (context, list) {
        if (list.isEmpty) {
          return const EmptyView(
            Icons.calendar_month_outlined,
            'Nothing scheduled',
          );
        }
        final byDay = <DateTime, List<Json>>{};
        for (final e in list) {
          final d = DateTime.tryParse('${e['airDateUtc']}')?.toLocal();
          if (d == null) continue;
          byDay.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(e);
        }
        final days = byDay.keys.toList()..sort();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            for (final day in days) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  day == today
                      ? 'Today'
                      : DateFormat('EEEE, MMM d').format(day),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: day == today
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ),
              for (final e in byDay[day]!) EpisodeCard(e),
            ],
          ],
        );
      },
    ),
  );
}

/// Card for an episode that carries an embedded `series` object.
class EpisodeCard extends StatelessWidget {
  final Json episode;
  final Widget? trailing;
  final String? extra;
  const EpisodeCard(this.episode, {super.key, this.trailing, this.extra});

  @override
  Widget build(BuildContext context) {
    final series = Json.from((episode['series'] as Map?) ?? {});
    final air = DateTime.tryParse('${episode['airDateUtc']}')?.toLocal();
    final hasFile = episode['hasFile'] == true;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openEpisode(context, episode, '${series['title'] ?? ''}'),
        child: Row(
          children: [
            SizedBox(width: 52, height: 76, child: Poster(series)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${series['title'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${episodeCode(episode)} · ${episode['title'] ?? 'TBA'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (air != null)
                          DateFormat.yMMMd().add_jm().format(air),
                        ?extra,
                      ].join(' · '),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
            trailing ??
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    hasFile ? Icons.check_circle : Icons.schedule,
                    color: hasFile ? Colors.green : Colors.grey,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
