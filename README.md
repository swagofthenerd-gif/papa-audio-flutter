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

**TODO (next passes), to reach parity with the RN app:**
1. **On-phone local library** via native MediaStore (`on_audio_query` or a
   MediaStore platform channel). This is the big one — MediaStore indexing is
   why native players show the local library instantly and avoids the
   scoped-storage `file://` ENOENT problems the RN app fought.
2. Full now-playing screen (seek, queue, shuffle/repeat, lyrics).
3. YouTube search/stream/download (bridge `/api/youtube/*` — check server.js).
4. Downloads UI + offline playback of downloaded tracks.
5. Playlists / liked / play-counts sync with the bridge (`/api/settings/*`).
6. In-app update banner (bridge `/api/app-update` + `/app-update/apk`).

## Architecture (`lib/`)

- `src/theme.dart` — Papa Audio palette (dark + `#1DB954` green) and `ThemeData`.
- `src/models.dart` — `Track`, `Album`, `SlskFolder` (+ `fromJson`).
- `src/bridge.dart` — HTTP client for the PC bridge. All server calls live here.
- `src/player_service.dart` — `just_audio` wrapper (queue, play, seek, next).
- `src/app_state.dart` — `ChangeNotifier` app state (bridge, library, player).
- `main.dart` — UI: setup, shell (bottom nav), home grid, album, search, mini
  player.

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
