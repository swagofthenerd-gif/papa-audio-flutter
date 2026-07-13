# Session Handoff — continue from here

For the next agent session. Read this + `NAMIDA_PARITY.md` and continue the
wave grind. The user's standing instruction: **"do multiple waves
continuously"** — implement parity waves back-to-back, verify each on the
emulator, build + push + drop the APK on the Desktop, then start the next.

## Ground rules (non-negotiable, established with the user)

1. **Original code only.** Namida (github.com/namidaco/namida) is EULA-licensed
   (read `LICENSE` in the clone — §3 forbids using code outside Namida itself).
   We replicate *behavior*, never code. The user pushed back on this twice;
   the position stands. A behavior-reference clone lives at the session
   scratchpad but re-clone if needed — for READING behavior only.
2. **Verify on a device before shipping.** `flutter analyze` alone shipped a
   totally broken app once (audio never played until the AudioServiceActivity
   fix). Every wave: install debug on the emulator, drive it with adb taps,
   screenshot, and check state (dumpsys media_session / sqlite3 via run-as).
3. **Ship every wave**: release APK → `C:\Users\LENOVO\Desktop\PapaAudio-latest.apk`,
   commit (as user "shaharyar" <swagofthenerd@gmail.com>), push to master.
   Push works (this PC's account `awigul8188-svg` is a collaborator).
4. Keep NAMIDA_PARITY.md checkboxes in sync with what actually ships.
5. The user cares intensely about **smoothness/perf**: memoize by revision
   counters, keep work off the UI isolate (compute/sqflite/task-queue channel),
   lazy lists only, RepaintBoundary on high-frequency repaints.

## Environment (this machine)

- Flutter 3.44.6: `C:\Users\LENOVO\dev\flutter` · JDK 21: `C:\Users\LENOVO\dev\jdk`
  · Android SDK 36: `C:\Users\LENOVO\dev\android-sdk` — none on PATH; prepend
  `C:\Users\LENOVO\dev\jdk\bin;C:\Users\LENOVO\dev\flutter\bin` and set
  JAVA_HOME/ANDROID_HOME per shell.
- Emulator AVD `papa_test` (API 35, Pixel 7). Start:
  `emulator -avd papa_test -no-snapshot -no-boot-anim -gpu swiftshader_indirect -memory 2048`
  (detached via Start-Process; NEVER pipe emulator output through
  `Select-Object -First N` — it kills the process). It is slow/software-rendered;
  screenshots via `adb exec-out screencap -p`. Test music already on it:
  /sdcard/Music/TestAlbum/{AlphaSong,BetaSong}.mp3 + /sdcard/Music/ZuluTrack.mp3.
  Grant perms: `adb shell pm grant com.shaharyar.papa_audio android.permission.READ_MEDIA_AUDIO`.
  App DB inspection: `adb shell 'run-as com.shaharyar.papa_audio sqlite3 databases/papa_audio.db "..."'`.
- Dev harness: `flutter run -t lib/dev_preview.dart` boots the shell without a
  bridge and queues 3 remote test tracks.

## Architecture map (lib/src)

- `db.dart` — SQLite (v3): history, favorites, playlists(+tracks), queue_tracks,
  saved_queues, kv, lyrics, waveforms, collection_resume. One-time JSON
  migration. Version bumps go through onUpgrade.
- `player_service.dart` — just_audio + just_audio_background (MainActivity MUST
  stay `AudioServiceActivity`). Queue ops (in-place), persistence, sleep timer,
  speed/pitch, EQ pipeline objects, transition fades, listen ticks,
  per-collection resume (`resumeFor`/`currentCollectionId`), `encodeTracksJson`
  isolate helper. ONLY ONE AudioPlayer may ever exist (plugin limit) — true
  crossfade needs an audio_service rewrite (open W2 item).
- `history.dart` — DB-backed listens; revision counter; counts/firstListen maps.
- `playlists.dart`, `queues_store.dart`, `settings.dart` (incl. TagSplitter
  config + revision), `local_library.dart` (MediaStore channel, search blobs,
  compute-built), `text_norm.dart` (normText/blobMatches/TagSplitter),
  `lyrics.dart` (LRCLIB + cache), `waveform.dart`, `art_color.dart`,
  `selection.dart`, `downloads.dart`, `bridge.dart` (PC server client).
- `ui/`: player_sheet (gesture morph player, waveform SeekBar, lyrics panel),
  library_tab (chip tabs + memoized views + TrackListScreen + PlayShuffleRow),
  home_tab (quick picks + shelves, memoized), playlists_ui, downloads_tab,
  search_tab, music_hub (go-to-artist/album hub: YouTube→PC→local), dialogs,
  track_tile (configurable swipes, selection), selection_bar, settings_screen,
  equalizer_screen, collection_menu (NEW), recently_added (NEW), widgets.
- Android: `MainActivity.kt` — MediaStore channel on a background task queue
  (replies off main thread), art executor (2 threads), waveform executor (1),
  high-refresh-rate request. Channel: queryTracks/getArt/getWaveform/
  hasPermission/requestPermission (requestPermission must hop to main handler).

## State at handoff (commit `3c191c5`, all pushed, APK on Desktop)

~83/242 parity items done. Waves A–E all shipped and device-verified
(2026-07-13 session):

- **Wave A** (`13db88a`): collection long-press menus wired everywhere
  (local album cards, artist/genre/folder tiles, PC AlbumCard, playlist +
  Liked Songs tiles), disc-section headers in LocalAlbumScreen,
  settings.gridColumns (2/3) applied in _AlbumsView, Recently-added screen
  routed from Home quick-pick + shelf See-all.
- **Wave B** (`91b7341`): settings.queueEndRestart (completed+LoopMode.off →
  seek index 0, paused — listener in PlayerService ctor), hold prev/next
  scrubs ±holdSeekSec per 250ms (TransportControls now stateful),
  removeAllExceptCurrent in queue-sheet overflow.
- **Wave C** (`721c865`): history.lastListen map (MAX(at) init + updates),
  history.rediscover() → Home "Rediscover" shelf (>30d, count desc, hidden
  when empty), StatsScreen at settings → Statistics.
- **Wave D** (`e9b1680`): settings.playOnSkip (skip while paused plays),
  settings.holdSeekSec dropdown (5/10/15/30s), percent-based listen
  threshold (settings.listenPercentMode + listenPercent, wired via
  history.thresholdProvider in app_state), settings.artistBeforeTitle
  (TrackTile swaps title/artist lines).
- **Wave E** (`3c191c5`): PlaylistsService.removeDuplicates (+ overflow
  menu item with count snackbar), history swipe-delete Undo
  (HistoryService.restoreEntry), TrackSort.lastListen. Dedupe + undo
  device-verified; lastListen sort analyzer/tests-only (emulator kept
  crashing — see below). **Next session: spot-check the "Last listen"
  sort menu option on-device first.**
- Next: continue down NAMIDA_PARITY.md unchecked W2 items (folder tree
  mode, per-tab state, global search overlay, track deletion, interruption
  handling, shuffle-behavior setting…), then W3 (tag editor, M3U, smart
  playlists, history calendar, lyrics fullscreen…).

Emulator quirks seen this session: it silently dies mid-session (adb
"device offline"/"error: closed" → no devices) — happened 4+ times, more
frequent late in the session; restart with the Start-Process recipe above
(data persists, no re-granting needed). A stray Android "Try out your
stylus" system dialog once swallowed taps — dismiss via its Cancel button.
`adb shell input keyevent 4` (back) exits the app from its root screen;
prefer `am start -n com.shaharyar.papa_audio/.MainActivity` to relaunch
(monkey sometimes races the shade).

## Verification recipe per wave

1. `flutter analyze` + `flutter test` (15 tests must stay green).
2. Debug build → `adb install -r` → drive the changed screens via adb taps →
   screenshots → DB checks where relevant.
3. `flutter build apk --release` → copy to Desktop → commit + push.

Known quirks: first sqlite3 query after app start races init (retry);
emulator occasionally ANRs System UI (tap Wait); `.metadata`/`pubspec.lock`
sometimes get touched by flutter tools — `git checkout` them before commit.
