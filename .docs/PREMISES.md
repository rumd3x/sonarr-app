# Premises

- **Name:** Sonarr (unofficial). Flutter, Android only (`com.rumd3x.sonarr`).
- **Goal:** let Sonarr administrators manage their own Sonarr instance from a phone, with an elegant mobile UI.
- **No accounts:** no login, no registration, no backend of our own, no database.
- **Local storage only:** `shared_preferences` holds the connection settings and a small cache of the series list. Nothing else is persisted. "Disconnect" wipes it all.
- **First launch:** the app must ask for **primary URL**, **secondary URL** (optional fallback) and the **Sonarr API key**. The connection is verified (`GET /system/status`) before saving.
- **URL failover:** every request tries the last working URL first, then the other one. Only network failures trigger failover; HTTP errors (e.g. 401) do not.
- **Auth:** API key sent as `X-Api-Key` header; image URLs served by Sonarr use the `apikey` query parameter.
- **API version:** detected at runtime via `GET /api` (`current` field, e.g. `v3`, `v5`), defaulting to `v3`. API reference: https://sonarr.tv/docs/api/
- **Cleartext HTTP is allowed** (`usesCleartextTraffic`), because Sonarr is commonly reached over LAN.
- **Theme:** Material 3, dark by default, seed colour `#35C5F4`.
- **Not affiliated** with the Sonarr project; the app says so in the More screen.
- **Branding:** the official Sonarr logo (from the open-source Sonarr repo, `Logo/`) is used for the launcher icon, setup screen, More screen and README. Sources live in `assets/branding/` (`logo.png`, `logo.svg`, `logo_foreground.png` = logo padded to 66% for the adaptive icon; adaptive background `#EDEDED`). Regenerate launcher icons with `dart run flutter_launcher_icons` (config: `flutter_launcher_icons.yaml`).
- **Tooling note:** Gradle fails on JDK 25; build with JDK 17 (`JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64`).
