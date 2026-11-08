# Playbook: building an unofficial *arr companion app like this one

This repo is the reference implementation (Sonarr). The same recipe was designed to be repeated for **Radarr, Lidarr, Readarr, Prowlarr**, etc. A future agent should read `PREMISES.md`, `FEATURES.md` and `ARCHITECTURE.md` first, then follow this playbook step by step. Everything below was actually done and verified on this project.

## 0. What stays identical across apps

- Flutter, **Android only**, Material 3 dark theme, seed colour taken from the product logo.
- **No login, no registration, no database.** Only `shared_preferences` (settings + local cache).
- First launch asks for **primary URL, secondary (fallback) URL, API key** (`setup_screen.dart`). Failover to the secondary URL happens only on network/timeout errors.
- Auth via `X-Api-Key` header (the `apikey` query param only for image URLs).
- API version detected at runtime from `GET /api` → `current` (default `v3`). Sonarr/Radarr are `v3`, Lidarr/Readarr/Prowlarr are `v1`; detection makes the client generic.
- JSON handled as `Map<String, dynamic>` (`typedef Json`), no generated models. Updates `PUT` back the **full** object.
- State: `provider` with a single `AppState` (config, cached library, long-running manual search).
- Docs live in `.docs/`, with the two mandatory directives (read docs before acting, keep docs updated) repeated in `AGENTS.md` and `.github/copilot-instructions.md`.

## 1. What changes per app

| | Sonarr (this repo) | Radarr | Lidarr | Readarr | Prowlarr |
|---|---|---|---|---|---|
| Main entity | series → seasons → episodes | movies | artists → albums | authors → books | indexers / apps |
| API docs | https://sonarr.tv/docs/api/ | https://radarr.video/docs/api/ | https://lidarr.audio/docs/api/ | https://readarr.com/docs/api/ | https://prowlarr.com/docs/api/ |
| Manual search | `/release?episodeId=` | `/release?movieId=` | `/release?albumId=` | `/release?bookId=` | `/search` |
| Seed colour | `#35C5F4` | the product's brand colour | idem | idem | idem |

Rename screens/endpoints accordingly (e.g. `series_*` → `movie_*`; Radarr has no season/episode level, so the series-detail + episode-detail screens collapse into one movie-detail screen with Details / History / Search tabs).

## 2. Step-by-step recipe (order we followed)

1. **Scaffold**: `flutter create --platforms=android --org <org> --project-name <name> .` then add `http`, `shared_preferences`, `provider`, `cached_network_image`, `intl`. Manifest: `INTERNET` permission, `android:usesCleartextTraffic="true"` (users run on LAN over http), app label = product name.
2. **Services** (`lib/services/`): `settings.dart` (`ServerConfig`, `SettingsStore`; prefs keys `primary_url`, `secondary_url`, `api_key`), `api.dart` (`_send` with failover + version detection + per-call `timeout`, one method per endpoint), `app_state.dart`.
3. **Screens**: setup → home (bottom nav: library, calendar, activity [queue/history], wanted, more) → add (lookup + root folder + quality profile) → detail → item detail (details/history/manual search). Shared widgets in `lib/widgets/common.dart` (poster, error/empty, `AsyncBody`, toast, `openEpisode`-style navigation helper, manual-search button with spinner/badge).
4. **Manual (interactive) search** can take minutes: the request uses a 5-minute timeout (`releaseTimeout`) and runs inside `AppState` (not in the widget) so it survives navigation; the UI shows a spinner and a "results ready" badge. Don't make it synchronous in the screen.
5. **Branding**: the official logos are open-licensed and may be used. Sonarr's came from the repo's `Logo/` folder (`1024.png`, `Sonarr.svg`). Put them in `assets/branding/` (`logo.png`, `logo.svg`, `logo_foreground.png` = logo padded to ~66% for the adaptive icon). Icons are generated with `flutter_launcher_icons` (`flutter_launcher_icons.yaml`, adaptive background `#EDEDED`): `dart run flutter_launcher_icons`. Use the logo on the setup screen, the More screen and the README header.
6. **Tests**: `test/api_test.dart` covers URL normalisation, failover to the secondary URL with the API key header, manual-search list/grab and the 401 "invalid API key" error, using `http` mock clients. Keep `flutter analyze` clean and `flutter test` green.
7. **Docs**: `.docs/` (README index + PREMISES + FEATURES + ARCHITECTURE + this playbook), `AGENTS.md`, `.github/copilot-instructions.md`, then a GitHub-style `README.md` with badges, features table, screenshots, getting started, development.
8. **CI/CD**: see section 4.
9. **Store assets**: see section 5.

## 3. Build & run environment gotchas

- **Use JDK 17** for Gradle (`JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64`); JDK 25 breaks the Android Gradle build.
- After builds run `(cd android && ./gradlew --stop)`. The Gradle daemon holds ~4.5 GB and made the emulator freeze ("Emulator not responding").
- Emulator: AVD `sonarr_pixel` (Pixel 7, `android-35;google_apis;x86_64`), KVM available, no sudo needed. Stable flags: `emulator -avd sonarr_pixel -gpu host -no-snapshot -no-boot-anim`, 2048 MB RAM, 3 cores, animation scales 0.5. adb: `~/Android/Sdk/platform-tools/adb`. From the emulator the host machine is **`10.0.2.2`**.
- **Kotlin DSL**: in `build.gradle.kts` use `import java.util.Properties` (a bare `java.util.Properties` fails with "Unresolved reference: util").
- `flutter_launcher_icons` is a dev dependency in `pubspec.yaml` (config in `flutter_launcher_icons.yaml`); the Play plugin is configured in Gradle. Nothing else is needed locally.

## 4. CI/CD (Jenkinsfile) – private Jenkins + Forgejo + Google Play

Pipeline (Docker agent `ghcr.io/cirruslabs/flutter:latest`, label `docker`): checkout → set up signing → compute version (`RELEASE_TYPE` patch/minor/major, build number +1) → `scripts/update_version.sh` (rewrites `version:` in `pubspec.yaml`) → `pub get` → `flutter analyze` + `flutter test` → release APK → AAB → publish to Play (`./gradlew publishBundle`) → commit version bump → tag `vX.Y.Z` → push to **Forgejo** → Forgejo release with APK attached → archive artifacts.

To clone it for another app change only: `APP_NAME`, `FORGEJO_REPO`, the `applicationId`/`namespace`, and the Play listing. Keep the Jenkins credential IDs (same private instance):

| Credential ID | Type | Used for |
|---|---|---|
| `forgejo-credentials` | secret text | Forgejo access token with repository write (push, tag, release, asset upload) |
| `play-store-service-account` | secret file | Play Developer API service-account JSON (`PLAY_STORE_CONFIG_JSON`) |
| `android-upload-keystore` | secret file | upload keystore → copied to `android/upload-keystore.jks` |
| `android-keystore-password` | secret text | used for store + key password in `android/key.properties` |

Notes:
- Forgejo mirrors every push to GitHub automatically; the pipeline never talks to GitHub. Releases use the Gitea-compatible API: `POST /api/v1/repos/{repo}/releases`, then `POST .../releases/{id}/assets?name=` (multipart `attachment=`), header `Authorization: token <T>`.
- Repo moves redirect with HTTP 301 and **git cannot follow a 301 on push**: always use the canonical URL (`git remote set-url origin ...`). This repo lives at `Arr/sonarr-app`.
- `android/app/build.gradle.kts` signs release builds with `android/key.properties` when it exists (gitignored; falls back to the debug key locally) and configures Gradle Play Publisher (`com.github.triplet.play` 3.12.1, declared in `android/settings.gradle.kts`) from env vars `PLAY_STORE_CONFIG_JSON`, `PLAY_STORE_TRACK`, `PLAY_STORE_RELEASE_STATUS`. Release notes are written to `android/app/src/main/play/release-notes/en-US/default.txt` by the pipeline.
- **The store listing is synced by the pipeline too** (`PUBLISH_STORE_LISTING`, default on): title/descriptions in `android/app/src/main/play/listings/en-US/`, icon + feature graphic generated by `scripts/generate_play_assets.py` from `assets/branding`, phone screenshots copied from `.docs/screenshots` (first 8). Details in `ARCHITECTURE.md` → "Play Store listing". For a new app, copy this layout and adjust the texts (use "(Unofficial)" in the title).
- **Not automatable via the Play API** (do in the Console once): content rating questionnaire, data safety form, target audience, ads declaration, app category, privacy policy URL if requested, countries/pricing, store contact email/website, and the very first manual upload.
- **Application ID** must equal the package created in Play Console (`com.rumd3x.sonarr` here). Set it in `namespace` + `applicationId` and move `MainActivity.kt` to the matching directory. The Dart package name (`sonarr_app`) is independent.

### Google Play prerequisites (do once per new app)
1. Create the app in Play Console with the exact package name.
2. Enrol in **Play App Signing**. The key used to sign the **first uploaded bundle becomes the upload key**, so the first bundle must be signed with the Jenkins `android-upload-keystore`.
3. **Upload the first release manually** in the Console (the Play API cannot create the first release; before that it answers "package not found").
4. Invite the service account (Users and permissions) and grant it this app with release permissions.
5. While the app has never been published, releases through the API must use status **draft** (`PLAY_STORE_RELEASE_STATUS=draft`); the Jenkins parameters default to track `internal` + status `draft`.
6. Finish the Console tasks (store listing, content rating, data safety, target audience…) before promoting to production. New personal accounts may need closed testing before production.
7. `versionCode` comes from `pubspec.yaml` (`version: x.y.z+N`); every upload needs a higher `N` (the pipeline increments it).

## 5. Screenshots for the store / README

Real servers are not needed: run a throw-away mock of the API on the host (`0.0.0.0:8989`, Python `http.server` + Pillow for generated gradient posters/fanart with fictional titles) and point the app to `http://10.0.2.2:8989`. Endpoints the app calls on its screens: `/api`, `/system/status`, `/health`, `/diskspace`, `/series` (+`/{id}`), `/episode`, `/calendar`, `/queue`, `/history`, `/wanted/missing`, `/release`, `/rootfolder`, `/qualityprofile`. Posters/fanart come from `images[].remoteUrl`.

Tips that saved time:
- **Don't type into the setup form with `adb input text`** (it drops characters). Seed the saved config instead: push an XML named `FlutterSharedPreferences.xml` with `flutter.primary_url`, `flutter.secondary_url`, `flutter.api_key` and copy it with `run-as <package> cp … shared_prefs/`, then relaunch.
- `adb exec-out screencap -p > file.png` (1080×2400). Tap coordinates are in device pixels.
- **Google Play needs aspect ratio ≤ 2:1.** 1080×2400 is rejected, so crop the emulator border (4 px) and pad the sides with the app's background colour to 1196×2392 (Pillow).
- Output goes to `.docs/screenshots/NN-name.png` (01 setup, 02 series, 03 series detail, 04 episode, 05 manual search, 06 calendar, 07 activity, 08 wanted, 09 more) and is referenced from `README.md`. Retake them when the UI changes.
- Delete the mock server and temp files afterwards.

## 6. Definition of done for a new app

- [ ] `flutter analyze` clean, `flutter test` passes, release APK builds (JDK 17).
- [ ] Setup → library → detail → manual search → queue verified on the emulator against a mock (or real) server.
- [ ] Official logo, adaptive icon and in-app logo in place; "unofficial / not affiliated" notice present.
- [ ] `.docs/` and `README.md` updated, screenshots added.
- [ ] `applicationId` matches Play Console; Jenkinsfile `APP_NAME` / `FORGEJO_REPO` updated; credentials exist in Jenkins.
- [ ] Committed with the `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>` trailer and pushed to Forgejo.
