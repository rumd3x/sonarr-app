# Architecture

```
lib/
  main.dart                 App entry, theme, routes Setup vs Home based on AppState
  services/
    settings.dart           ServerConfig + SettingsStore (shared_preferences)
    demo_client.dart        DemoServer: in-memory fake Sonarr (MockClient) behind "Try demo"; ServerConfig.demo selects it
    api.dart                SonarrApi: HTTP client, failover, version detection, endpoints
    app_state.dart          AppState (ChangeNotifier via provider): config, api, series cache, manual searches, queue count (badge), series images index
  screens/                  One file per screen (see FEATURES.md); episode_detail_screen embeds ManualSearchView (episode); series_detail_screen opens SeasonSearchScreen (same view, per season); activity_screen opens manual_import_screen; home_screen polls the queue count; wanted_screen has Missing/Cutoff tabs
  widgets/common.dart       Shared widgets and formatting helpers
test/api_test.dart          URL normalization, failover, 401 handling, demo mode, ManualImport command, v3/v5 release and list normalization, season releases (MockClient)
```

- Data is handled as `Json` (`Map<String, dynamic>`) — no generated models. Updates send back the full object received from Sonarr, changing only the needed fields.
- State: `provider` for `AppState`; screens own their local state / `AsyncBody` futures. Long-running work (manual search) lives in `AppState` so it survives navigation.
- Queue badge: `HomeScreen` (bottom nav) polls `AppState.refreshQueueCount()` every 30 s while foregrounded (`WidgetsBindingObserver`) and the queue tab refreshes it after each load; polling pauses only on `paused` (not `inactive`) and restarts on `resumed`; the Activity icon uses `Badge`. `AsyncBodyState.reload(silent: true)` refreshes without a spinner (used by the queue tab, which `HomeScreen` tells when it is active).
- Embedded series without images: `Poster` falls back to `AppState.seriesImages()` (id → images from `GET /series`, loaded once, reset on config change/disconnect).
- Demo mode: `SonarrApi` builds its HTTP client from `DemoServer().client()` (an `http/testing.dart` `MockClient`, shipped in the `http` package) when `config.isDemo`. `DemoServer` implements the same paths as Sonarr (`/api`, `/system/status`, `/series`, `/episode`, `/calendar`, `/queue`, `/queue/status`, `/manualimport`, `/qualitydefinition`, `/language`, `/history`, `/wanted/missing`, `/wanted/cutoff`, `/release`, `/command`, …) with mutable in-memory state, so toggling monitoring, deleting, adding or grabbing works during a session. Dates are relative to now, so the calendar is never empty.
- Dependencies: `http`, `shared_preferences`, `provider`, `cached_network_image`, `intl`.

## Sonarr v3 / v5 compatibility
Always support both (see PREMISES.md for the spec links). Handled today in `SonarrApi`:
- `GET /release`: v5 nests each item as `release` / `decision` / `parsedInfo`; `_flattenRelease` flattens it (rejections become message strings). Season search uses `seriesId` + `seasonNumber` on both versions.
- List endpoints (`/queue`, `/history`, `/calendar`, `/episode`, `/wanted/*`): v5 only embeds `series`/`episode`/`episodes`/`episodeFile` when asked via `includeSubresources` (repeated query key); we send it together with the v3 `include*` flags. Query values that are `List`s are sent as repeated keys.
- `/queue`: v5 `sizeLeft`, `timeLeft`, `episodes[]` → normalized to `sizeleft`, `timeleft`, `episode`. `DELETE /queue/{id}` sends both flag sets (`removeFromClient`/`blocklist` and `removalMethod`/`blocklistMethod`).
- `mediaInfo`: v5 `audioStreams`/`subtitleStreams` → normalized to `audioCodec`/`audioChannels`/`subtitles`.
- `/manualimport`: sends `downloadId` (v3) and `downloadIds` (v5).
- Other v5 differences with no current impact: `languageProfileId` removed from series, `seasonType` required when adding a series, `releaseType` gained `multiSeasonPack`, `/qualitydefinition` lost `min/max/preferredSize`, `/system/status` lost `sqliteVersion`.
- Gotcha: hot reload keeps old generic types of long-lived objects (e.g. `AppState.manualSearches`); use a hot restart after changing them.

## Commands
```
flutter pub get
flutter analyze
flutter test
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 flutter build apk --debug
# run on the emulator (AVD sonarr_pixel); if Gradle fails with "problem starting process flutter": (cd android && ./gradlew --stop)
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 flutter run -d emulator-5554 --debug --no-resident
```

## CI/CD (central `release.groovy` in the `jenkins-app-release` repo)
Same structure and Jenkins credentials as `rumd3x/machine-maintenance-android` (docker agent `ghcr.io/cirruslabs/flutter`, label `docker`). Parameters: release type (patch/minor/major), release notes, Play Store publish/track/status.
Stages: checkout → Android signing (keystore + `android/key.properties` from Jenkins credentials) → calculate version → `./gradlew updateVersion` (`android/build.gradle.kts`) (writes `version:` in `pubspec.yaml`) → `pub get` → `flutter analyze` + `flutter test` → release APK → AAB (`archiveArtifacts` runs right after the build, so the `.aab` is downloadable from the build page even if the publish stage fails) → Play Store (`./gradlew publishListing` when `PUBLISH_STORE_LISTING`, then `./gradlew publishBundle`) → commit version bump → tag → push to Forgejo (`forgejo.rumd3x.com/Arr/sonarr-app`, branch `master`; Forgejo mirrors to GitHub on push) → Forgejo release (Gitea-compatible API) with APK attached → archive artifacts.
Play Store package (applicationId/namespace): `com.rumd3x.sonarr`; Kotlin `MainActivity` lives in `android/app/src/main/kotlin/com/rumd3x/sonarr/`.
- Credential IDs: `forgejo-credentials` (secret text, Forgejo access token with repository write), `play-store-service-account`, `android-upload-keystore`, `android-keystore-password`.
- `android/app/build.gradle.kts` signs release builds with `android/key.properties` when present (falls back to the debug key locally) and configures the Gradle Play Publisher plugin (`com.github.triplet.play`) from the env vars `PLAY_STORE_CONFIG_JSON`, `PLAY_STORE_TRACK`, `PLAY_STORE_RELEASE_STATUS`.

### Play Store listing (synced by the pipeline)
Source of truth lives in the repo and is pushed by `publishListing`:
- `android/app/src/main/play/default-language.txt` (`en-US`) and `listings/en-US/{title,short-description,full-description}.txt` (limits: 30 / 80 / 4000 chars).
- `listings/en-US/graphics/icon/icon.png` (512×512) and `graphics/feature-graphic/feature.png` (1024×500), generated from `assets/branding` by `python3 scripts/generate_play_assets.py` (needs Pillow). Re-run and commit after changing the branding.
- Phone screenshots are **not** duplicated: the pipeline copies the first 8 files of `assets/images/screenshots/` (sorted by name) into `graphics/phone-screenshots/` (gitignored) right before `publishListing`. Keep them within Play limits (≤8, side ≥320, ≤2:1).
- Release notes: from the `RELEASE_NOTES` job parameter into `release-notes/en-US/default.txt` (gitignored).
- Jenkins defaults are safe for a brand-new app: track `internal`, status `draft`.
- Changing listing texts/graphics = edit the files above and run the job; update this section if the layout changes.
- The full description mentions the demo mode ("TRY IT WITHOUT A SERVER").

### Play Console declarations that cannot be automated
- **App access** (login details): the app has no accounts, but it needs a server, so Google asks for access instructions. Declare restricted access and use the "Any other information needed to access the app" field (limit 500 chars) with:
  `No accounts or login. On first launch, tap "Try demo" on the Setup screen to explore all features with built-in sample data. No server or credentials needed.`
  Leave username/password empty. The reviewed build must already contain the **Try demo** button, so publish a new version before resubmitting.
- In the current Console UI this lives under **Publishing overview** (Visão geral da publicação) → app content / "Set up your app" tasks → App access; the old "Policy and programs → App content" menu may not exist. The global search box ("App access") also finds it.
- Store listing texts/graphics are synced by the pipeline (see above); everything else (content rating, data safety, target audience, ads, category, contact details) is manual.
