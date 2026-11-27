# Project instructions

- Do not add co-author trailers to commits.
- **Always read the documentation in `.docs/` before acting** (start with `.docs/README.md` and `.docs/PREMISES.md`).
- **Always keep the documentation updated**: any change to behavior, features, architecture, premises, commands or dependencies must update the matching file in `.docs/` (and `README.md` when user-facing) in the same change.
- **Always implement features compatible with Sonarr API v3 and v5** (requests and response mapping). Compare both OpenAPI contracts before touching an endpoint, normalize in `SonarrApi`, and test both shapes. Specs: v5 https://raw.githubusercontent.com/Sonarr/Sonarr/develop/src/Sonarr.Api.V5/openapi.json · v3 https://raw.githubusercontent.com/Sonarr/Sonarr/main/src/Sonarr.Api.V3/openapi.json · docs UI https://sonarr.tv/docs/api/ (details in `.docs/PREMISES.md` and `.docs/ARCHITECTURE.md`).
- Respect the premises: no login/database, local cache only, primary + secondary URL with API key.
- **Always keep `PRIVACY_POLICY.txt` accurate**: if a change alters data stored on the device (e.g. new `shared_preferences` keys, caches), data sent over the network, permissions in `AndroidManifest.xml`, or adds a third-party SDK/analytics/ads/crash reporting, update the policy and its "Last updated" date in the same change (and mention it in `.docs/PREMISES.md` if a premise changes).
- **Keep at most eight screenshots** in `assets/images/screenshots/` for the README and the Google Play phone listing. Keep the images that best show the app's main workflows. Capture them manually, retake affected screenshots when the UI changes, and keep the README references in sync. See `.docs/PLAYBOOK.md` §5.
