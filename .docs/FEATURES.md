# Features

Navigation: bottom bar with **Series · Calendar · Activity · Wanted · More**. The Activity item shows a badge with the number of queue items (hidden when 0); it refreshes every 30 s while the app is in the foreground, on resume, and whenever the queue is loaded (`AppState.refreshQueueCount()`, `GET /queue/status` → `totalCount`).

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
- Posters: series embedded in calendar/wanted episodes come with only an `id` (no `images`), so `Poster` looks the images up by id in the series list (`AppState.seriesImages()`, loaded once). `/MediaCover` can't be used directly: servers with authentication redirect it to the login page even with `apikey`; the `remoteUrl` from the series images is used instead.
- `GET /calendar?includeSeries=true`

## Activity (`activity_screen.dart`)
- **Queue:** progress, status, size, time left, download client; remove with optional blocklist.
- **Manual import button:** a queue item waiting for user action shows a `person_search` button immediately left of the "X" (`needsManualImport()` in `manual_import_screen.dart`): it has a `downloadId` and `trackedDownloadState` is `importBlocked`, or `importPending`/`importFailed` with `trackedDownloadStatus` `warning`. It opens the manual import screen and reloads the queue when the import was started.
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
- Posters: series embedded in calendar/wanted episodes come with only an `id` (no `images`), so `Poster` looks the images up by id in the series list (`AppState.seriesImages()`, loaded once). `/MediaCover` can't be used directly: servers with authentication redirect it to the login page even with `apikey`; the `remoteUrl` from the series images is used instead.
- `GET /calendar?includeSeries=true`

## Activity (`activity_screen.dart`)
- **Queue:** progress, status, size, time left, download client; remove with optional blocklist.
- **Manual import:** a queue item at 100% waiting for user action (`trackedDownloadState` `importBlocked`, or `importPending`/`importFailed` with `trackedDownloadStatus` `warning`, and a `downloadId`) shows a button left of the "X" that opens `manual_import_screen.dart`, the mobile version of the web UI's Interactive Import. It lists the files found (each with the queue item's `statusMessages` for that file, matched by file name; the file's raw `rejections` are only a fallback), lets you pick series (pre-filled when Sonarr didn't match it: from the queue item's `series`, else its `seriesId`, else `GET /parse?title=`), episodes (listed with their air date), quality and languages (multi-select) per file, and import the selected files. The import mode is always `auto` (no selector). Files with no series/episodes yet can't be selected until completed.
- **History:** last 50 events with icon per event type.
- `GET /queue`, `DELETE /queue/{id}`, `GET /queue/status` (badge), `GET /history`

## Manual import (`manual_import_screen.dart`)
Mobile version of the web UI's "Interactive Import", opened from a queue item (see Activity).
- **Loading** (`SonarrApi.manualImportCandidates`): `GET /manualimport?downloadId=<id>&filterExistingFiles=false` first, so Sonarr itself matches the series/episodes like the web UI does. If it errors (`Parameter 'path'` = the download client reported no output path) or returns nothing, retry with `folder=<queue item outputPath>` (this fallback can't match the series). Also loads `GET /qualitydefinition` (each `.quality` = choices) and `GET /language` (entries with id < 0, e.g. "Any", are hidden).
- **One card per file:** relative path, size, and chips to edit **series**, **episodes**, **quality** and **languages** (multi-select, bottom sheet with checkboxes + Done). A checkbox selects it for import; it is disabled until the file has a series, at least one episode and a quality. Files that already come fully matched are pre-selected.
- **Series pre-fill:** for files Sonarr returned without a series, use the queue item's `series`, else look up its `seriesId` in `GET /series`, else `GET /parse?title=<queue title>` (`series`). The user can still change it; changing the series clears the episodes and opens the episode picker.
- **Episode picker:** bottom sheet, grouped by season (`GET /episode?seriesId=`), multi-select, each row shows number, title and **air date** (`airDate`, else the date part of `airDateUtc`).
- **Errors:** no errors at the top of the screen. Each card shows the queue item's `statusMessages` for that file (matched by file name against the message `title`; if none match and there are as many messages as files, matched by position). Only if there are none, the file's raw `rejections[].reason` (e.g. `unknownSeries`) are shown. Errors are red with a warning icon.
- **Import:** bottom button "Import (n)". Sends `POST /command` `{name: "ManualImport", importMode: "auto", files: [...]}` where each file is `path`, `seriesId`, `episodeIds`, `quality` (object returned by Sonarr, with the chosen `quality`), `languages`, `releaseGroup`, `downloadId`, plus `indexerFlags`/`releaseType` when present. The import mode is always `auto` (no selector in the UI). On success it toasts and pops with `true`.
- **Demo mode:** one queue item (`id` 502, `importBlocked`, 100%) with one unmatched file, endpoints `/manualimport`, `/qualitydefinition`, `/language`; the `ManualImport` command removes the queue item.

## Wanted (`wanted_screen.dart`)
- Wanted/Calendar episode cards (`EpisodeCard`) show the series poster; see the Calendar poster note.
- Two tabs: **Missing** (monitored episodes without a file) and **Cutoff unmet** (monitored episodes whose file quality is below the profile cutoff).
- Search one episode (automatic or manual), or all of the current tab from the app bar (`MissingEpisodeSearch` / `CutoffUnmetEpisodeSearch`).
- `GET /wanted/missing`, `GET /wanted/cutoff`, `POST /command` (`EpisodeSearch`, `MissingEpisodeSearch`, `CutoffUnmetEpisodeSearch`)

## More (`more_screen.dart`)
- Sonarr logo card with version and active URL, health warnings/errors, disk space bars.
- In demo mode the card shows "Demo mode · sample data" instead of the URL.
- Connection settings, Disconnect & clear data.
- `GET /system/status`, `GET /health`, `GET /diskspace`

## Cross-cutting
- Shared widgets in `widgets/common.dart`: poster with cached images (in demo mode a generated gradient with the title/initial, since there are no remote images), loading/error/empty states, pull-to-refresh loader, toasts.
- Errors are surfaced as readable messages (invalid API key, unreachable server, Sonarr validation messages).
