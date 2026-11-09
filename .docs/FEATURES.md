# Features

Navigation: bottom bar with **Series · Calendar · Activity · Wanted · More**.

## Setup / Connection (`setup_screen.dart`)
- Official Sonarr logo header, primary URL, secondary URL (fallback), API key (hidden, toggle visibility).
- URLs are normalized (adds `http://`, strips trailing `/`) and validated.
- **Try demo** button: runs the whole app against a built-in fake Sonarr (`services/demo_client.dart`) with sample series, queue, calendar, history and releases. No network or credentials; edits are kept in memory only. "Disconnect & clear data" leaves demo mode.
- Connection test before saving. Same screen is reused (editing mode) from More → Connection settings.

## Series (`series_list_screen.dart`)
- Library as poster grid or list (toggle); episode progress bar per series (green = complete/ended, blue = complete/continuing, red = missing monitored, grey = unmonitored).
- Text filter, status filter (All / Monitored / Continuing / Ended), pull-to-refresh.
- Cache-first: cached list shows instantly, then refreshes from the server.
- `GET /series`

## Series detail (`series_detail_screen.dart`)
- Fanart header, chips (year, network, status, runtime, episodes, size on disk), overview, path.
- Monitor/unmonitor series, per-season and per-episode.
- Search: whole series, a season, or a single episode (automatic). Refresh & scan. Delete (optionally with files).
- **Manual search** per episode, and **episode detail** (tap an episode name): see below. Also reachable from Wanted and Calendar.
- Episode rows show file status, air date and quality.
- `GET/PUT/DELETE /series/{id}`, `GET /episode?seriesId=&includeEpisodeFile=true`, `PUT /episode/{id}`, `POST /command` (`SeriesSearch`, `SeasonSearch`, `EpisodeSearch`, `RefreshSeries`)

## Add series (`add_series_screen.dart`)
- Lookup by name or `tvdb:ID`; already-added results are marked.
- Bottom sheet: root folder, quality profile, monitor mode, season folders, search for missing on add.
- `GET /series/lookup`, `GET /rootfolder`, `GET /qualityprofile`, `POST /series`

## Episode detail (`episode_detail_screen.dart`)
Opened by tapping an episode (series detail, Calendar, Wanted); the manual-search icon opens it directly on the Search tab. Three tabs:
- **Details:** code, air date, runtime, finale type, overview; monitor toggle, auto search; file card (path, quality, size, release group, languages, video/audio/subtitle info, date added) with delete file.
- **History:** grab/import/failure/delete/rename events for the episode, with release title, quality, indexer and download client.
- **Search:** manual search (below), embedded as `ManualSearchView`.
- `GET /episode/{id}?includeEpisodeFile=true`, `GET /history?episodeId=`, `DELETE /episodefile/{id}`

## Manual search (`manual_search_screen.dart`)
- Starts only when the user taps "Search indexers" (never automatically, to avoid needless indexer queries).
- Interactive release search for an episode: lists releases from all indexers with quality, size, age, indexer, seeders/leechers (torrent) or usenet, languages, custom-format score, and rejection reasons.
- Rejected releases are hidden by default (toggle); grabbing a rejected one asks for confirmation. Grab sends it to the download client.
- **Long-running by design:** indexer queries can take minutes. The request uses a 5-minute timeout (`SonarrApi.releaseTimeout`) and runs inside `AppState.manualSearch`, not in the screen, so the user can leave and come back. The episode's search button shows a spinner while running and a badge when results are ready. Results are kept in memory until restart/disconnect; "Search again" re-runs.
- `GET /release?episodeId=`, `POST /release` (`guid`, `indexerId`)

## Calendar (`calendar_screen.dart`)
- Episodes from 3 days ago to 30 days ahead, grouped by day ("Today" highlighted).
- `GET /calendar?includeSeries=true`

## Activity (`activity_screen.dart`)
- **Queue:** progress, status, size, time left, download client; remove with optional blocklist.
- **History:** last 50 events with icon per event type.
- `GET /queue`, `DELETE /queue/{id}`, `GET /history`

## Wanted (`wanted_screen.dart`)
- Monitored missing episodes; search one episode, or all missing from the app bar.
- `GET /wanted/missing`, `POST /command` (`EpisodeSearch`, `MissingEpisodeSearch`)

## More (`more_screen.dart`)
- Sonarr logo card with version and active URL, health warnings/errors, disk space bars.
- In demo mode the card shows "Demo mode · sample data" instead of the URL.
- Connection settings, Disconnect & clear data.
- `GET /system/status`, `GET /health`, `GET /diskspace`

## Cross-cutting
- Shared widgets in `widgets/common.dart`: poster with cached images (in demo mode a generated gradient with the title/initial, since there are no remote images), loading/error/empty states, pull-to-refresh loader, toasts.
- Errors are surfaced as readable messages (invalid API key, unreachable server, Sonarr validation messages).
