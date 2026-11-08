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
Stages: checkout → Android signing (keystore + `android/key.properties` from Jenkins credentials) → calculate version → `scripts/update_version.sh` (writes `version:` in `pubspec.yaml`) → `pub get` → `flutter analyze` + `flutter test` → release APK → AAB (archived immediately) → Play Store (`./gradlew publishListing` when `PUBLISH_STORE_LISTING`, then `./gradlew publishBundle`) → commit version bump → tag → push to Forgejo (`forgejo.rumd3x.com/Arr/sonarr-app`, branch `master`; Forgejo mirrors to GitHub on push) → Forgejo release (Gitea-compatible API) with APK attached → archive artifacts.
Play Store package (applicationId/namespace): `com.rumd3x.sonarr`; Kotlin `MainActivity` lives in `android/app/src/main/kotlin/com/rumd3x/sonarr/`.
- Credential IDs: `forgejo-credentials` (secret text, Forgejo access token with repository write), `play-store-service-account`, `android-upload-keystore`, `android-keystore-password`.
- `android/app/build.gradle.kts` signs release builds with `android/key.properties` when present (falls back to the debug key locally) and configures the Gradle Play Publisher plugin (`com.github.triplet.play`) from the env vars `PLAY_STORE_CONFIG_JSON`, `PLAY_STORE_TRACK`, `PLAY_STORE_RELEASE_STATUS`.

### Play Store listing (synced by the pipeline)
Source of truth lives in the repo and is pushed by `publishListing`:
- `android/app/src/main/play/default-language.txt` (`en-US`) and `listings/en-US/{title,short-description,full-description}.txt` (limits: 30 / 80 / 4000 chars).
- `listings/en-US/graphics/icon/icon.png` (512×512) and `graphics/feature-graphic/feature.png` (1024×500), generated from `assets/branding` by `python3 scripts/generate_play_assets.py` (needs Pillow). Re-run and commit after changing the branding.
- Phone screenshots are **not** duplicated: the pipeline copies the first 8 files of `.docs/screenshots/` (sorted by name) into `graphics/phone-screenshots/` (gitignored) right before `publishListing`. Keep them within Play limits (≤8, side ≥320, ≤2:1).
- Release notes: from the `RELEASE_NOTES` job parameter into `release-notes/en-US/default.txt` (gitignored).
- Jenkins defaults are safe for a brand-new app: track `internal`, status `draft`.
- Changing listing texts/graphics = edit the files above and run the job; update this section if the layout changes.
