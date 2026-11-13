# Documentation index

> **Directives (mandatory for every contributor and AI agent)**
> 1. **Read this documentation before acting.** Start with `PREMISES.md`, then the doc relevant to your task.
> 2. **Always keep the documentation updated.** Any change to behavior, features, architecture, premises, commands or dependencies must update the matching doc in the same change.
> 3. **Keep `PRIVACY_POLICY.txt` accurate.** Any change to what is stored on the device, what is sent over the network, permissions (`AndroidManifest.xml`) or third-party SDKs/services must update the policy and its "Last updated" date in the same change.

| File | Contents |
|---|---|
| [PREMISES.md](PREMISES.md) | What the app is, constraints and decisions that must hold |
| [FEATURES.md](FEATURES.md) | Complete feature list, per screen, with the Sonarr endpoints used |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Code layout, data flow, build/test commands |
| [PLAYBOOK.md](PLAYBOOK.md) | Step-by-step recipe to build the same app for Radarr, Lidarr, Readarr, Prowlarr…: env gotchas, CI/CD, Google Play prerequisites, screenshot workflow |
| [../PRIVACY_POLICY.txt](../PRIVACY_POLICY.txt) | Plain-text privacy policy (Play Console requires a URL). **Update it (and its "Last updated" date) if the app starts storing/sending new data, adds a third-party SDK/service, or requests new permissions.** |
| [../assets/images/screenshots/](../assets/images/screenshots/) | Store/README screenshots (01–09, 1196×2392, ≤2:1 as Google Play requires). Captured on the emulator against a mock Sonarr with fictional data (the in-app demo mode can be used for retakes). **Retake them when the UI changes.** |
