import 'package:shared_preferences/shared_preferences.dart';

import 'demo_client.dart';

class ServerConfig {
  final String primaryUrl;
  final String secondaryUrl;
  final String apiKey;

  const ServerConfig({
    required this.primaryUrl,
    required this.secondaryUrl,
    required this.apiKey,
  });

  bool get isValid => primaryUrl.isNotEmpty && apiKey.isNotEmpty;

  /// Demo mode talks to a built-in fake server instead of a real Sonarr.
  static const demo = ServerConfig(
    primaryUrl: DemoServer.url,
    secondaryUrl: '',
    apiKey: 'demo',
  );

  bool get isDemo => primaryUrl == DemoServer.url;

  static String normalizeUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return '';
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }
}

class SettingsStore {
  static const _kPrimary = 'primary_url';
  static const _kSecondary = 'secondary_url';
  static const _kKey = 'api_key';

  Future<ServerConfig?> load() async {
    final p = await SharedPreferences.getInstance();
    final cfg = ServerConfig(
      primaryUrl: p.getString(_kPrimary) ?? '',
      secondaryUrl: p.getString(_kSecondary) ?? '',
      apiKey: p.getString(_kKey) ?? '',
    );
    return cfg.isValid ? cfg : null;
  }

  Future<void> save(ServerConfig c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrimary, ServerConfig.normalizeUrl(c.primaryUrl));
    await p.setString(_kSecondary, ServerConfig.normalizeUrl(c.secondaryUrl));
    await p.setString(_kKey, c.apiKey.trim());
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kPrimary);
    await p.remove(_kSecondary);
    await p.remove(_kKey);
  }
}
