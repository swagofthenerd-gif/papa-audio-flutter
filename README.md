# Papa Audio (Flutter)

A native Flutter rebuild of Papa Audio — a music app that streams from a
personal **PC bridge server** and adds Soulseek + YouTube. This is a
**from-scratch, original** rewrite of the earlier React Native app
(`papa-audio-android`), chosen for Flutter's native rendering (no JS bridge =
much smoother lists/playback).

> It is *not* a copy of any other app. It talks to the same PC bridge the RN app
> used, so all the "special" features are HTTP calls to that server.

## Status

**Implemented (first slice):**
- Connect to the PC bridge (setup screen, saved with `shared_preferences`)
- Browse the PC library (album grid) → album screen → play
- **Native playback** via `just_audio` + `just_audio_background` (lock screen /
  background / gapless)
- Mini player
- **Soulseek**: search + queue download (runs on the PC), via bridge endpoints

**Implemented (second slice):**
- **On-phone local library** via a custom MediaStore platform channel
  (`MainActivity.kt` + `src/local_library.dart`) — instant library, no file
  scanning, plays `content://` URIs so scoped storage is a non-issue. Art comes
  over the channel as bytes (`localart://` convention in `TrackArt`).
- **Full now-playing screen** — big art, seek bar, prev/play/next,
  shuffle/repeat, queue sheet (tap to jump). Mini player opens it and shows a
  thin progress strip.
- **YouTube** — Search tab is segmented Soulseek | YouTube; tap a result to
  stream via `/api/youtube/stream?id=`, download button POSTs
  `/api/youtube/download` (downloads to PC library).
- **Downloads tab** — download any PC track/album to the phone (raw lossless
  via `/stream?raw=1` into app documents + JSON index), play fully offline,
  delete; plus live Soulseek transfer progress polled from the PC.

> **Note:** the `/api/youtube/*` request/response shapes were written
> defensively (multiple field-name fallbacks) but not verified against
> server.js — if search/stream misbehaves, diff against the server code.

**Implemented (third slice — Namida parity, wave 1):** see `NAMIDA_PARITY.md`
for the full matrix. Highlights:
- **Gesture miniplayer** — drag the mini bar up into the full player (one
  finger-tracking morph with spring physics), swipe it sideways to change
  track, swipe down / back button to collapse. Morphing artwork ties the two
  states together.
- **Library tabs** — Tracks / Albums / Artists / Folders / Playlists / History /
  Most played, with live search, sort menu (+reverse), counts, draggable
  scrollbar, numeric-aware folder sorting.
- **Queue system** — play next, add to queue, drag-reorder, swipe-remove,
  tap-to-jump; queue + position persist across restarts (restored paused).
- **Playlists & favorites** — Liked Songs, create/rename/delete/reorder,
  add-to-playlist from any track menu.
- **History & stats** — real listen counting (20s / half-track rule), history
  by day, most played with time ranges.
- **Playback extras** — sleep timer (minutes or tracks, fades out), speed
  control, smart previous, shuffle-all; track tiles swipe right = play next,
  swipe left = queue.

**TODO (next passes):**
1. Namida parity waves 2–4 — see `NAMIDA_PARITY.md`.
2. Playlists / liked / play-counts sync with the bridge (`/api/settings/*`).
3. In-app update banner (bridge `/api/app-update` + `/app-update/apk`).

## Architecture (`lib/`)

- `src/theme.dart` — Papa Audio palette (dark + `#1DB954` green) and `ThemeData`.
- `src/models.dart` — `Track`, `Album`, `SlskFolder`, `YtResult` (+ `fromJson`).
  `Track.sourceUri`/`artUri` let one type cover PC, local, downloaded and
  YouTube tracks.
- `src/bridge.dart` — HTTP client for the PC bridge. All server calls live here.
- `src/local_library.dart` — MediaStore channel client, album grouping, art cache.
- `src/downloads.dart` — download-to-phone manager (files + index.json, progress).
- `src/player_service.dart` — `just_audio` wrapper (queue, seek, shuffle/repeat).
- `src/app_state.dart` — `ChangeNotifier` app state (bridge, library, player).
- `src/ui/` — `now_playing.dart`, `search_tab.dart` (Soulseek+YouTube),
  `library_tab.dart` (on-phone), `downloads_tab.dart`, `widgets.dart`
  (`TrackArt` renders http/file/MediaStore art uniformly).
- `main.dart` — setup, shell (4 tabs), home grid, album screen, mini player.

State is `provider` + `ChangeNotifier`, deliberately small.

## The PC bridge (source: `~/flac-player/bridge-server/server.js`)

Default `http://<PC-IP>:8765`. Endpoints this app uses:
- `GET /api/health` — reachability
- `GET /api/library` — `{ albums: [...] }`
- `GET /stream?path=<filePath>&raw=1` — audio stream (raw = original lossless)
- `GET /art?path=<artPath>&w=<width>` — artwork
- `GET /api/slsk/status` · `GET /api/slsk/search?query=` · `POST /api/slsk/download`
  · `GET /api/slsk/transfers`

Other endpoints available for the TODO list: `/api/youtube/*`,
`/api/settings/*` (liked, playlists, play-counts, playback-state, history),
`/api/fetch-album-art`, `/api/library/scan`, `/events` (SSE).

## Build / run

Needs Flutter (stable) + Android SDK + a JDK.

```sh
flutter pub get
flutter run                     # on a connected device/emulator
flutter build apk --release     # release APK (android/ uses debug signing)
```

- Package: `com.shaharyar.papa_audio` (deliberately different from the RN app's
  `com.shaharyar.papaudio`, so both can be installed side by side).
- Android config: `android/app/src/main/AndroidManifest.xml` declares the
  `audio_service` foreground service + `usesCleartextTraffic` (for LAN HTTP).

## Notes for the next agent

- To reach the PC from off-LAN, the bridge is also on Tailscale (enter the PC's
  `100.x` Tailscale IP on the connect screen).
- Keep everything original — do **not** import code from other apps.
