import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonarr_app/screens/manual_search_screen.dart';
import 'package:sonarr_app/services/api.dart';
import 'package:sonarr_app/services/app_state.dart';
import 'package:sonarr_app/services/settings.dart';

Future<void> showResults(WidgetTester tester, List<Json> releases) async {
  final state = AppState(SettingsStore());
  addTearDown(state.dispose);
  state.manualSearches[1] = ManualSearch(1, 'Episode')
    ..status = ManualSearchStatus.done
    ..releases = releases;
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(
        home: Scaffold(body: ManualSearchView(episodeId: 1, label: 'Episode')),
      ),
    ),
  );
}

void main() {
  testWidgets('sorts the visible releases and can restore Sonarr order', (
    tester,
  ) async {
    final releases = <Json>[
      {'title': 'First in Sonarr', 'seeders': 10},
      {'title': 'Most seeded', 'seeders': 40},
      {'title': 'Tied release', 'seeders': 40},
      {'title': 'Rejected release', 'seeders': 50, 'rejected': true},
    ];
    await showResults(tester, releases);

    double position(String title) => tester.getTopLeft(find.text(title)).dy;
    Finder orderOption(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate(
        (widget) => widget is CheckedPopupMenuItem,
      ),
    );
    expect(position('First in Sonarr'), lessThan(position('Most seeded')));

    await tester.tap(find.text('Order by'));
    await tester.pumpAndSettle();
    await tester.tap(orderOption('Most seeders'));
    await tester.pumpAndSettle();
    expect(position('Most seeded'), lessThan(position('Tied release')));
    expect(position('Tied release'), lessThan(position('First in Sonarr')));
    expect(find.text('Rejected release'), findsNothing);

    await tester.tap(find.byTooltip('Show rejected'));
    await tester.pumpAndSettle();
    expect(position('Rejected release'), lessThan(position('Most seeded')));

    await tester.tap(find.text('Order by'));
    await tester.pumpAndSettle();
    await tester.tap(orderOption('Sonarr order'));
    await tester.pumpAndSettle();
    expect(position('First in Sonarr'), lessThan(position('Most seeded')));
    expect(releases.first['title'], 'First in Sonarr');
  });

  testWidgets('opens only a valid release info URL in an external app', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    const url = 'https://example.com/release';
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return true;
    });
    await showResults(tester, [
      {'title': 'Linked release', 'infoUrl': url},
      {'title': 'Unlinked release'},
      {'title': 'Unsupported link', 'infoUrl': 'ftp://example.com/release'},
    ]);

    final button = find.byTooltip('Open release info in browser');
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(calls.single.method, 'launch');
    expect(calls.single.arguments['url'], url);
    expect(calls.single.arguments['useWebView'], false);
    expect(calls.single.arguments['headers'], isEmpty);
  });
}
