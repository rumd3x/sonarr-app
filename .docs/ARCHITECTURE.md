# Architecture

```
lib/
  main.dart                 App entry, theme, routes Setup vs Home based on AppState
  services/
    settings.dart           ServerConfig + SettingsStore (shared_preferences)
    api.dart                SonarrApi: HTTP client, failover, version detection, endpoints
    app_state.dart          AppState (ChangeNotifier via provider): config, api, series cache
  screens/                  One file per screen (see FEATURES.md); episode_detail_screen embeds ManualSearchView
  widgets/common.dart       Shared widgets and formatting helpers
test/api_test.dart          URL normalization, failover, 401 handling (MockClient)
```

- Data is handled as `Json` (`Map<String, dynamic>`) — no generated models. Updates send back the full object received from Sonarr, changing only the needed fields.
- State: `provider` for `AppState`; screens own their local state / `AsyncBody` futures. Long-running work (manual search) lives in `AppState` so it survives navigation.
- Dependencies: `http`, `shared_preferences`, `provider`, `cached_network_image`, `intl`.

## Commands
```
flutter pub get
flutter analyze
flutter test
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 flutter build apk --debug
```

## CI/CD (`Jenkinsfile`)
Same structure and Jenkins credentials as `rumd3x/machine-maintenance-android` (docker agent `ghcr.io/cirruslabs/flutter`, label `docker`). Parameters: release type (patch/minor/major), release notes, Play Store publish/track/status.
Stages: checkout → Android signing (keystore + `android/key.properties` from Jenkins credentials) → calculate version → `scripts/update_version.sh` (writes `version:` in `pubspec.yaml`) → `pub get` → `flutter analyze` + `flutter test` → release APK → AAB → Play Store (`./gradlew publishBundle`) → commit version bump → tag → push to Forgejo (`forgejo.rumd3x.com/rumd3x/sonarr-app`, branch `master`; Forgejo mirrors to GitHub on push) → Forgejo release (Gitea-compatible API) with APK attached → archive artifacts.
- Credential IDs: `forgejo-credentials` (secret text, Forgejo access token with repository write), `play-store-service-account`, `android-upload-keystore`, `android-keystore-password`.
- `android/app/build.gradle.kts` signs release builds with `android/key.properties` when present (falls back to the debug key locally) and configures the Gradle Play Publisher plugin (`com.github.triplet.play`) from the env vars `PLAY_STORE_CONFIG_JSON`, `PLAY_STORE_TRACK`, `PLAY_STORE_RELEASE_STATUS`.
