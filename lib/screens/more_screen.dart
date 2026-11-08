import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'setup_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: AsyncBody<List<dynamic>>(
        load: (api) =>
            Future.wait([api.systemStatus(), api.health(), api.diskSpace()]),
        builder: (context, data) {
          final status = data[0] as Json;
          final health = data[1] as List<Json>;
          final disks = data[2] as List<Json>;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: ListTile(
                  leading: Image.asset('assets/branding/logo.png', width: 36),
                  title: Text('Sonarr ${status['version']}'),
                  subtitle: Text(
                    '${state.api?.activeBase ?? state.config?.primaryUrl}',
                  ),
                ),
              ),
              const _Header('Health'),
              if (health.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle, color: Colors.green),
                    title: Text('All good'),
                  ),
                )
              else
                for (final h in health)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        h['type'] == 'error'
                            ? Icons.error
                            : Icons.warning_amber,
                        color: h['type'] == 'error'
                            ? Colors.redAccent
                            : Colors.orange,
                      ),
                      title: Text('${h['message']}'),
                      subtitle: Text('${h['source']}'),
                    ),
                  ),
              const _Header('Disk space'),
              for (final d in disks) _DiskCard(d),
              const _Header('App'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.settings_ethernet),
                      title: const Text('Connection settings'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SetupScreen(editing: true),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Disconnect & clear data'),
                      onTap: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Disconnect?'),
                            content: const Text(
                              'Saved URLs, API key and cache will be removed.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Disconnect'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) state.reset();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Unofficial app — not affiliated with Sonarr',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _DiskCard extends StatelessWidget {
  final Json disk;
  const _DiskCard(this.disk);

  @override
  Widget build(BuildContext context) {
    final free = (disk['freeSpace'] as num?) ?? 0;
    final total = (disk['totalSpace'] as num?) ?? 0;
    final used = total > 0 ? (total - free) / total : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${disk['label']?.toString().isNotEmpty == true ? disk['label'] : disk['path']}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: used.toDouble(),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${formatBytes(free)} free of ${formatBytes(total)}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
