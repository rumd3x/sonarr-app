# Premises

- **Name:** Sonarr (unofficial). Flutter, Android only (`com.rumd3x.sonarr`).
- **Goal:** let Sonarr administrators manage their own Sonarr instance from a phone, with an elegant mobile UI.
- **No accounts:** no login, no registration, no backend of our own, no database.
- **Local storage only:** `shared_preferences` holds the connection settings and a small cache of the series list. Nothing else is persisted (demo mode only stores the demo config marker). "Disconnect" wipes it all.
- **First launch:** the app must ask for **primary URL**, **secondary URL** (optional fallback) and the **Sonarr API key**. The connection is verified (`GET /system/status`) before saving. A **Try demo** button skips this and uses built-in sample data (see Demo mode).
- **Demo mode:** the Setup screen has a **Try demo** button that stores `ServerConfig.demo` (URL `http://demo.sonarr.local`) and serves every request from an in-memory fake server (`lib/services/demo_client.dart`). It exists because Google Play reviewers need a way into an app that otherwise requires a self-hosted server. It must keep working with every screen/endpoint the app uses; when you add an API call, add it to `DemoServer`. No data leaves the device in demo mode.
- **URL failover:** every request tries the last working URL first, then the other one. Only network failures trigger failover; HTTP errors (e.g. 401) do not.
- **Auth:** API key sent as `X-Api-Key` header; image URLs served by Sonarr use the `apikey` query parameter.
- **API version:** detected at runtime via `GET /api` (`current` field, e.g. `v3`, `v5`), defaulting to `v3`. API reference: https://sonarr.tv/docs/api/
- **Sonarr v3 and v5 compatibility (mandatory directive):** every feature must work on **both** API versions, in the requests **and** in the response mapping. Before adding or changing an endpoint, compare its contract in both specs and make the code accept both shapes (normalize in `SonarrApi`, keeping the UI on one flat shape; add tests for both; keep `DemoServer` working). Known v3→v5 differences are listed in [ARCHITECTURE.md](ARCHITECTURE.md#sonarr-v3--v5-compatibility). Contracts (OpenAPI):
  - Docs UI (v5 default, v3 selectable): https://sonarr.tv/docs/api/ (`#v5`, `#v3`)
  - v5 spec: https://raw.githubusercontent.com/Sonarr/Sonarr/develop/src/Sonarr.Api.V5/openapi.json
  - v3 spec: https://raw.githubusercontent.com/Sonarr/Sonarr/main/src/Sonarr.Api.V3/openapi.json
- **Cleartext HTTP is allowed** (`usesCleartextTraffic`), because Sonarr is commonly reached over LAN.
- **Theme:** Material 3, dark by default, seed colour `#35C5F4`.
- **Not affiliated** with the Sonarr project; the app says so in the More screen.
- **Branding:** the official Sonarr logo (from the open-source Sonarr repo, `Logo/`) is used for the launcher icon, setup screen, More screen and README. Sources live in `assets/branding/` (`logo.png`, `logo.svg`, `logo_foreground.png` = logo padded to 66% for the adaptive icon; adaptive background `#EDEDED`). Regenerate launcher icons with `dart run flutter_launcher_icons` (config: `flutter_launcher_icons.yaml`).
- **Tooling note:** Gradle fails on JDK 25; build with JDK 17 (`JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64`).
