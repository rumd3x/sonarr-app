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
  static const _maxMonths = 12;
  late final DateTime _today = _dateOnly(DateTime.now());
  late DateTime _month = DateTime(_today.year, _today.month);
  late DateTime _selected = _today;
  int _dir = 1; // slide direction: 1 = forward (next month), -1 = backward

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  int get _offset =>
      (_month.year - _today.year) * 12 + _month.month - _today.month;

  void _goTo(int delta) {
    final off = _offset + delta;
    if (off.abs() > _maxMonths) return;
    _dir = delta >= 0 ? 1 : -1;
    setState(() {
      _month = DateTime(_today.year, _today.month + off);
      _selected = off == 0 ? _today : _month;
    });
  }

  void _goToday() {
    _dir = _offset > 0 ? -1 : 1;
    setState(() {
      _month = DateTime(_today.year, _today.month);
      _selected = _today;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Calendar'),
      actions: [
        if (_selected != _today)
          TextButton.icon(
            icon: const Icon(Icons.today),
            label: const Text('Today'),
            onPressed: _goToday,
          ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _key.currentState?.reload(),
        ),
      ],
    ),
    body: AsyncBody<List<Json>>(
      key: _key,
      load: (api) => api.calendar(
        DateTime(_today.year, _today.month - _maxMonths),
        DateTime(_today.year, _today.month + _maxMonths + 1),
      ),
      builder: (context, list) {
        final byDay = <DateTime, List<Json>>{};
        for (final e in list) {
          final d = DateTime.tryParse('${e['airDateUtc']}')?.toLocal();
          if (d == null) continue;
          byDay.putIfAbsent(_dateOnly(d), () => []).add(e);
        }
        final items = byDay[_selected] ?? const <Json>[];
        return Column(
          children: [
            _header(context),
            _grid(context, byDay),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _selected == _today
                      ? 'Today'
                      : DateFormat('EEEE, MMM d').format(_selected),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const EmptyView(
                      Icons.calendar_month_outlined,
                      'Nothing scheduled',
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [for (final e in items) EpisodeCard(e)],
                    ),
            ),
          ],
        );
      },
    ),
  );

  Widget _header(BuildContext context) => Row(
    children: [
      IconButton(
        icon: const Icon(Icons.chevron_left),
        onPressed: _offset > -_maxMonths ? () => _goTo(-1) : null,
      ),
      Expanded(
        child: Text(
          DateFormat('MMMM yyyy').format(_month),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      IconButton(
        icon: const Icon(Icons.chevron_right),
        onPressed: _offset < _maxMonths ? () => _goTo(1) : null,
      ),
    ],
  );

  Widget _grid(BuildContext context, Map<DateTime, List<Json>> byDay) {
    final scheme = Theme.of(context).colorScheme;
    final first = _month;
    final lead = first.weekday % 7; // weeks start on Sunday
    final count = DateUtils.getDaysInMonth(first.year, first.month);
    final rows = ((lead + count) / 7).ceil();
    const names = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) _goTo(1);
        if (v > 200) _goTo(-1);
      },
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) {
            final incoming = child.key == ValueKey(_month);
            final from = Offset((incoming ? 1.0 : -1.0) * _dir, 0);
            return SlideTransition(
              position: Tween(begin: from, end: Offset.zero).animate(anim),
              child: child,
            );
          },
          child: Padding(
            key: ValueKey(_month),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    for (final n in names)
                      Expanded(
                        child: Center(
                          child: Text(
                            n,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                  ],
                ),
                for (var r = 0; r < rows; r++)
                  Row(
                    children: [
                      for (var c = 0; c < 7; c++)
                        Expanded(
                          child: _cell(
                            context,
                            scheme,
                            r * 7 + c - lead + 1,
                            count,
                            byDay,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    ColorScheme scheme,
    int day,
    int count,
    Map<DateTime, List<Json>> byDay,
  ) {
    if (day < 1 || day > count) return const SizedBox(height: 44);
    final date = DateTime(_month.year, _month.month, day);
    final selected = date == _selected;
    final has = byDay.containsKey(date);
    final isToday = date == _today;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => setState(() => _selected = date),
      child: Container(
        height: 44,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? scheme.primary
              : has
              ? scheme.primaryContainer
              : null,
          border: isToday && !selected
              ? Border.all(color: scheme.primary)
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$day',
          style: TextStyle(
            fontWeight: has || selected ? FontWeight.bold : null,
            color: selected
                ? scheme.onPrimary
                : has
                ? scheme.onPrimaryContainer
                : null,
          ),
        ),
      ),
    );
  }
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
    series['id'] ??= episode['seriesId'];
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
