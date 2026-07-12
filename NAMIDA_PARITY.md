# Namida Feature Parity Roadmap

Papa Audio tracks feature parity with [Namida](https://github.com/namidaco/namida), an exceptionally
feature-rich music player. Namida is EULA-licensed, so **no Namida code is ever copied, ported, or
referenced during implementation** — every behavior below is re-implemented from scratch inside Papa
Audio's own architecture (Flutter, just_audio, MediaStore, and the Papa PC bridge). The UI always keeps
Papa Audio's Spotify-style look: we replicate *what* Namida can do, never how it looks or how it is coded.

Checked items are already shipped in Papa Audio (Wave 1). Every unchecked item carries a wave tag.

## Waves

- **Wave 1 — done.** All `[x]` items below: gesture miniplayer, core player, queue, library tabs,
  playlists, history/most-played, on-device + PC-bridge libraries, offline downloads, queue persistence.
- **Wave 2 `(W2)` — core playback & library depth.** Audio engine (crossfade, fades, replay gain, EQ),
  queue/insertion depth, resume memory, genres, multi-select, waveform seekbar, settings basics.
- **Wave 3 `(W3)` — lyrics, theming, tags, smart features.** Synced-lyrics suite, dynamic color behaviors,
  tag editor, M3U, smart playlists/mixes, history depth, YouTube depth (cache, SponsorBlock, offline search).
- **Wave 4 `(W4)` — ecosystem.** Video, YouTube account, downloads-manager depth, backup/sync,
  Android Auto, widgets, remote servers, onboarding, localization, platform integrations.

## Library

- [x] Library tabs — Tracks / Albums / Artists / Folders / Playlists / History / Most played as scrollable chip tabs
- [x] Track sorting — title / artist / album / date-added / duration with reverse toggle
- [x] Interactive draggable scrollbar on track lists; track/album count headers
- [x] Folders view — grouped by real parent folder with numeric-aware sorting ("Music 2" before "Music 12")
- [x] Artists view — grouped with track counts, opening per-artist track list screens
- [x] Track tile swipes — swipe right = play next, swipe left = add to queue (snap back with toast)
- [x] Track tile affordances — long-press + overflow context menu, playing-track highlight, duration label
- [x] Track context menu — play next / queue / favorite / add-to-playlist (incl. create) / download / info with listen count
- [x] Shuffle-all from library header; play & shuffle buttons on albums/artists/folders/playlists
- [x] On-phone MediaStore library — instant index, content:// playback, album-art channel, Android 13+ permission flow
- [x] PC bridge library — albums grid streamed lossless from the desktop bridge
- [x] Genres tab — group by genre tag with counts and per-genre track lists (Android 11+ tags)
- [ ] Genre collage artwork cards (W3)
- [x] Multi-select — long-press selects, tap toggles, bulk bar: play / play next / queue / add to playlist
- [ ] Multi-select extras — range selection, bulk tag-edit and delete (W2)
- [ ] Track deletion — delete file from device with confirm; keep a recently-deleted trail (W2)
- [ ] Grid density — per-tab column count (1–4 or auto by screen width), persisted (W2)
- [ ] Library tabs editor — reorder/enable/disable tabs (min 2), default startup tab auto or fixed (W2)
- [ ] Per-tab state — remembered scroll offset, per-tab filter field, re-tap active tab scrolls to top (W2)
- [x] Sorting depth — year, real date-added, most-played, first-listen sort keys
- [ ] Sorting extras — date-modified key, per-collection sort, ignore leading "The/A/An" (W2)
- [ ] Albums vs singles split; multi-disc albums render separated disc sections (W2)
- [ ] Collection long-press dialogs — album/artist/genre/folder summary with play/shuffle/queue/playlist actions (W2)
- [ ] Subpage headers — artwork, counts + duration, play/shuffle with advanced modes (random N subset, insert next/after) (W2)
- [ ] Subpage inline search — filter tracks inside album/artist/playlist pages (W2)
- [ ] Recently added page — full list by date added with age labels (W2)
- [ ] Folder tree mode — hierarchy navigation with breadcrumb, subfolder counts, default-folder bookmark, flat toggle (W2)
- [ ] Go-to album/artist/folder from track menu + animated jump-to-track pill; "add more from this X" (W2)
- [x] A–Z letter rail — drag or tap to jump alphabetically sorted track lists, with letter bubble
- [ ] Track info depth — every tag field tappable-to-copy, format block, isolated preview player that pauses main playback (W2)
- [ ] Library refresh — pull-to-refresh diff rescan, refresh-on-startup option, full re-index with live progress (W2)
- [ ] Home tab — feed of mixes, recent/top listens, lost memories, recently added, recent queues/albums/artists (W3)
- [ ] Track tile layout editor — configurable rows/fields (~30 fields), separator, sizes, inline heart (W3)
- [ ] Moods / Tags / Rating tabs backed by per-track stats (W3)
- [ ] Indexer config — folder include/exclude, min size/duration, extension blacklist, .nomedia, duplicate prevention (W4)
- [x] Artist & genre separators with never-split blacklist — configurable in settings, credits every split artist
- [ ] Feat.-artist extraction from track titles (W4)
- [ ] Album identifiers — choose which tag fields distinguish identically named albums (W4)
- [ ] FFmpeg tag-extraction fallback, lenient year parsing, post-load duration correction (W4)
- [ ] Missing-tracks page + path healing — bulk old-to-new directory rewrite preserving stats/playlists/history (W4)
- [ ] Remote sources — Subsonic, Jellyfin, WebDAV, SMB with auth, ping validation, stream caching (W4)
- [ ] Artwork cache controls — group-by-album, unique-hash dedup, resolution multiplier, image source priority (W4)

## Search

- [x] Multi-field search — title / artist / album / genre / filename via precomputed blobs, all-terms matching
- [x] Search cleanup — diacritic- and case-insensitive matching ("beyonce" finds "Beyoncé")
- [x] Debounced search built off the UI thread (blobs precomputed on a background isolate)
- [ ] Configurable search fields — toggle composer/comment/year/moods/lyrics matching (W2)
- [ ] Media-type filter chips in search results (W2)
- [ ] Global search overlay — morphing app-bar field, sectioned results (album/artist rows above track list) (W2)
- [ ] Smart-search rule filter — temporary rule-based filter over track results (W3)

## Playback

- [x] Smart previous — restart if more than 5s in, otherwise go to previous track
- [x] Playback speed 0.5–2.0x with presets sheet
- [x] Sleep timer — after N minutes or N tracks, gentle fade-out, cancellable, visible active state
- [x] Shuffle toggle; repeat off / all / one cycle
- [x] Background & lock-screen playback with media-notification artwork
- [x] Transition fades — configurable fade-out/fade-in (0–10s) around gapless track changes
- [ ] True overlapping crossfade — needs a custom audio_service handler with two players; the background plugin allows only one (W2)
- [x] Play/pause fade — volume ramps over a configurable duration (100–1000ms)
- [x] Skip silence
- [x] Pitch control — semitone display, link speed & pitch, one-tap 432Hz
- [x] Equalizer — device bands with enable switch + loudness boost slider
- [ ] Play/pause fade depth — independent play vs pause durations (W2)
- [ ] Gapless playback — pre-buffer the next item for seamless transitions (W2)
- [ ] Replay gain — normalization via volume multiplier from gain tags (W2)
- [ ] Per-track audio configs — persisted per-track speed/pitch/volume/EQ overrides with global override switch (W2)
- [ ] Equalizer presets (stock + user) and audio-session broadcast to external EQ apps (W3)
- [ ] Headset buttons — single/double/triple click mapped to play-pause / next / previous (W2)
- [ ] Interruption handling — per-event pause/duck/nothing, auto-resume threshold, pause on unplug (W2)
- [ ] Resume on device connect — separate wired and Bluetooth thresholds (W2)
- [ ] Pause at volume zero with timed auto-resume when volume returns (W2)
- [ ] Repeat N times — repeat current track N times before advancing, live adjustable remaining count (W2)
- [ ] Queue-end behavior — jump to first after finish; infinite wrap on next/previous (W2)
- [ ] Seek step config — fixed seconds or % of track; tap time labels to seek; hold to fast-forward/rewind (W2)
- [x] Track-tap play modes — whole list / single track / gentle insert-into-queue, in settings
- [ ] Tap-mode extras — build queue from album / artist / genre of the tapped track (W2)
- [ ] Play-error handling — cancellable 7s auto-skip countdown; rapid-skip debounce loads only the final target (W2)
- [ ] Per-collection resume — albums/artists/playlists/folders remember the last played item, resume FAB (W2)
- [ ] Restore last position for long tracks (configurable minimum duration) (W2)
- [ ] Play-on-skip toggle — whether next/previous auto-plays while paused (W2)
- [ ] Notification config — favorite and stop buttons, lockscreen-art toggle, configurable tap action (W2)
- [ ] Kill-service policy — never / if-not-playing / always when the app is swiped away (W2)
- [ ] Sleep-target marker — queue shows the track playback will sleep after (W2)
- [ ] Set as ringtone / notification / alarm sound (W4)

## Queue

- [x] Play next & add to queue; drag-to-reorder; swipe-to-remove; tap-to-jump; current-track highlight; live count
- [x] Queue survives edits — in-place just_audio operations without restarting the current track
- [x] Queue persistence — restores queue, index, and position (paused) across app restarts
- [x] Chained play-next — successive inserts land in A→B→C order after the current track
- [x] Queue undo — removed items restorable via snackbar at their original index
- [x] Bulk removal — duplicates / all previous / all next, with removed counts
- [ ] Insertion depth — play after N tracks, play after current group, remove all-except-current (W2)
- [x] Saved queues — auto-archived dated queues (Queues tab), replay, swipe-delete, same-set dedupe
- [ ] Same-set detection — replaying an identical track set restructures in place instead of rebuilding (W2)
- [ ] Shuffle behavior setting — shuffle whole queue vs only the items after the current one (W2)
- [x] Queue auto-scroll — opens at the current track, jump-to-current button
- [ ] Jump button icon that tracks scroll position (CD / up / down) (W2)
- [ ] Smart queue generators — more from album/artist/folder, random N, era/mood/rating/history-similarity picks (W3)
- [ ] Mixed local + YouTube queue with per-item playback dispatch (W3)

## Miniplayer & Now Playing

- [x] Drag-to-expand morph with spring/fling physics — finger-tracked, tap to expand, back button collapses
- [x] Morphing artwork mini-to-full; thin progress strip on the mini bar
- [x] Horizontal swipe on mini bar for next/previous with slide feedback
- [x] Full player — draggable seek bar with time labels, prev / play-pause / next, buffering spinner
- [x] Favorite heart on both mini bar and full player
- [x] Utility row — sleep timer, speed, more-menu
- [ ] Waveform seekbar — real audio waveform bars, drag-to-seek with drag-up-to-cancel, seek-delta bubble (W2)
- [ ] Seek display options — remaining-time toggle, absolute vs +/- delta while scrubbing (W2)
- [ ] Long-press transport — hold next for temporary speed-up, long-press previous restarts (W2)
- [ ] Queue slide-up layer — drag past the full player to reveal the queue sheet as a third snap state (W2)
- [ ] Swipe-down to dismiss — stops playback and clears the queue, optional setting with elastic headroom (W2)
- [ ] Audio info line — codec / bitrate / sample-rate readout in the expanded player (W2)
- [ ] Display artist before title toggle (W2)
- [ ] Artwork gestures — configurable tap/long-press actions, pinch-to-zoom, double-tap toggles lyrics (W3)
- [ ] Beat-reactive artwork pulse — waveform-driven scale with per-state intensity and inverse mode (W3)
- [ ] Party mode — beat-synced edge glow around the screen, optional multi-color palette swapping (W3)
- [ ] Music-reactive particle wallpaper behind the expanded player (W3)
- [ ] Idle dimming — dim the expanded player after N seconds, touch to wake, 0 = always dimmed (W3)
- [ ] Haptics — vibration mode picker, snap/queue haptic ticks, optional beat-wave haptics (W3)
- [ ] Immersive mode + wakelock while the player is expanded (W3)
- [ ] Widescreen docked player — permanently expanded side panel on wide/desktop layouts (W4)

## Playlists

- [x] Create, rename, delete; drag-reorder; swipe-remove; count + duration totals
- [x] Liked Songs favorites playlist
- [ ] Duplicate handling on add — add-anyway / skip prompts with undo snackbar (W2)
- [ ] Add-to-playlist dialog polish — containment checkmarks, remove-if-all-present, add-at-beginning toggle (W2)
- [ ] Remove-duplicates action with removed count (W2)
- [ ] Per-playlist sort field + reverse, plus a manual custom-order mode (W2)
- [ ] Default cards — History / Most played / Favourites / Queues cards with live counts atop the tab (W2)
- [ ] Playlist comments & mood labels (W3)
- [ ] Custom playlist artwork — pick an image, fetched candidates grid, delete (W3)
- [ ] Random playlist generator from a library sample (W3)
- [ ] Smart playlists — rule engine (text/number/date/boolean rules, nested Any/All groups), live-count editor (W3)
- [ ] Smart playlist export — snapshot to a normal playlist or an M3U file (W3)
- [ ] M3U interop — import files/folders, export with EXTINF and artwork URL, relative paths (W3)
- [ ] M3U sync — m3u file as source of truth, startup auto-scan, debounced write-back, backup before touching (W3)
- [ ] Empty-playlist helper — delete shortcut plus quick-add panel of random tracks (W3)

## History & Stats

- [x] Listen counting — 20s or half the track, skips don't count
- [x] Day-grouped history — per-day play button, swipe-to-delete entries, debounced persistence
- [x] Most played — ranked list with all / today / week / month / year ranges
- [x] Configurable listen threshold — N seconds (capped at half the track), adjustable in settings
- [ ] Percent-based listen threshold option (W2)
- [ ] Custom date range for most played with calendar picker constrained to days that have history (W2)
- [ ] Stats page — totals for tracks/albums/artists/genres, library duration, accumulated listen time (W2)
- [ ] Undo for history deletions (W2)
- [ ] Listen-based tile data — listen count, first/last listen dates as sort keys and tile badges (W2)
- [ ] Jump-to-day dialog + pinned year chips for fast history navigation (W3)
- [ ] Calendar heatmap — month view shaded by listen density, tap a day to jump into history (W3)
- [ ] Listens dialog — every timestamp listed, jump to the exact history entry, nearby most-played link (W3)
- [ ] Listen-order badges and first-listen marker on history entries (W3)
- [ ] History import — YouTube takeout and Last.fm with background parsing, progress, date filters (W3)
- [ ] Missing-entries resolver — map unmatched imports to real tracks or add placeholder entries (W3)
- [ ] Replace listens — transfer all history from one track to another (W3)
- [ ] Remove source from history — per-import-source deletion with date range and dedup (W3)
- [ ] Per-track stats store — rating, moods, tags, last position; survives file moves and renames (W3)

## Lyrics

- [x] LRC sourcing — LRCLIB fetch preferring duration-closest match, SQLite cache incl. negative caching
- [x] Synced karaoke view — active line centered/highlighted with neighbors dimmed, binary-searched per tick; plain-text fallback
- [x] Lyrics toggles — double-tap artwork or lyrics button swaps artwork for lyrics in place
- [ ] LRC sourcing extras — embedded tags and sibling .lrc files (W3)
- [ ] Full scrolling lyrics sheet — tap a line to seek, touch pauses auto-scroll (W3)
- [ ] Active-line styling — highlight pill, scale/dim neighbors, RTL and multi-language rendering (W3)
- [ ] Word-by-word karaoke sweep for word-synced lyrics (W3)
- [ ] Fullscreen lyrics — long-press artwork opens blurred-artwork fullscreen with transport controls (W3)
- [ ] Pinch-to-zoom font size, persisted separately for in-player and fullscreen views (W3)
- [ ] Lyrics management — provider search with editable query, paste/edit, offset, copy, delete (W3)
- [ ] Preferences — prioritize embedded, source restriction, speed-stretched timestamps, IGNORE marker (W3)
- [ ] Empty-line breathing — fade lyrics out during instrumental gaps to reveal the artwork (W3)

## YouTube

- [x] YouTube via PC bridge — search, stream-to-phone, download-to-PC
- [ ] Direct streaming — video/audio quality selection, audio-only mode, live-stream manifests (W3)
- [ ] Offline cache system — played media cached and playable offline, size limits, smart eviction scoring (W3)
- [ ] Cache priorities — per-item priority up to VIP so precious cache never auto-cleans (W3)
- [ ] Cache-first playback — play cached copies instantly, upgrade to fresh streams seamlessly (W3)
- [ ] SponsorBlock — per-category skip actions and colors, skip-button overlay, custom server (W3)
- [ ] Return YouTube Dislike — dislike counts plus vote submission (W3)
- [ ] Online search — suggestions, sectioned results, did-you-mean chip, infinite scroll (W3)
- [ ] Offline search — background index over all cached metadata with id/substring/fuzzy matching (W3)
- [ ] Data saver — separate WiFi and mobile quality modes (W3)
- [ ] Auto radio — append a mix/radio playlist when a single item is played (W3)
- [ ] Deleted-video resilience — offline metadata fallbacks keep dead/private videos usable (W3)
- [ ] Local YouTube watch history — day-bucketed with listens dialog and year jumps (W3)
- [ ] Shorts/mix visibility filters per surface (home, search, related, history) (W3)
- [ ] Chapters — chapter row, seekbar cutters, tappable description timestamps, most-replayed heatmap (W3)
- [ ] YouTube-style miniplayer — video-on-top sheet with description, related videos, comments below (W4)
- [ ] Account sign-in — cookie login, multi-account switching, anonymous mode (W4)
- [ ] Subscriptions — feed, subscribe/unsubscribe with notification bells, notifications page (W4)
- [ ] Channel pages — banner and tabs, load-all uploads since a date, bulk play/download actions (W4)
- [ ] Comments — read, sort, post, edit, delete, replies, like/dislike (W4)
- [ ] Watch Later & hosted playlists — save/remove account playlists, edit title/privacy (W4)
- [ ] Local YT playlists + takeout imports (subscriptions, playlists) (W4)
- [ ] Watch marking on account + PoToken / visitor-data configuration (W4)
- [ ] Clipboard link monitoring — copied YouTube links surface with a configurable open action (W4)

## Downloads

- [x] Download tracks/albums to phone for offline playback — progress, delete, local index
- [x] Soulseek search + PC download with transfers monitor (via bridge)
- [ ] Download manager — pause/resume/cancel/restart/rename, parallel limit, resume across sessions (W4)
- [ ] Download groups — folder-based groups with batch operations and persisted per-group configs (W4)
- [ ] Filename & tag templates — yt-dlp-style %(param)s builders for output names and metadata (W4)
- [ ] Pre-download tag editor + smart "Artist - Title" extraction, Topic-channel cleanup (W4)
- [ ] Playlist / bulk download page — select-all-except-downloaded, per-item config editing (W4)
- [ ] Progress notifications with live speed and per-file state (W4)
- [ ] Cache reuse — copy from the stream cache instead of re-downloading, and back into it after (W4)
- [ ] Post-download — embed thumbnail and tags, optional upload-date file dates, auto-add to library (W4)

## Video

- [ ] Local video library — index device videos as first-class playable items (W4)
- [ ] Track-video matching — by filename, title+artist, or embedded YouTube id; local video as visualizer (W4)
- [ ] Short-video looping when the clip is much shorter than the audio (W4)
- [ ] Video toggle — attach/detach the video track live without touching audio (W4)
- [ ] Fullscreen gestures — swipe volume/brightness, double-tap seek, pinch to enter/exit, hold for 2x (W4)
- [ ] Video quality preference list + playback source (auto / local / YouTube) (W4)
- [ ] Picture-in-picture for video playback (W4)

## Tag editor

- [ ] Single-track editor — all tag fields with configurable field set/order, changed markers, save lock (W3)
- [ ] Bulk editor — shared subset of fields across many tracks with progress and failed-files report (W3)
- [ ] Artwork replace from gallery with instant preview and embed on save (W3)
- [ ] Filename-to-tags extraction ("Artist - Title") (W3)
- [ ] Trim-whitespaces and keep-file-dates options (W3)
- [ ] Write pipeline — native tagger with FFmpeg fallback; refresh library, artwork, palette after save (W3)
- [ ] Set YouTube link — write a video URL into the comment tag with inline search helper (W3)
- [ ] Re-index selected tracks with live success/fail counters (W3)

## Theming & UI feel

Behaviors only — Papa Audio's Spotify-style visual identity is kept throughout.

- [x] Dynamic color — dominant artwork color (hue-bucket extraction, no deps) tints the expanded player; toggleable
- [ ] Light / dark / system modes plus a pitch-black AMOLED dark variant (W3)
- [ ] Wallpaper (Material You) accent option on Android 12+ (W3)
- [ ] Custom accent colors with a full picker; per-track palette editor (W3)
- [ ] Performance modes — presets that bulk-toggle expensive visual effects (W3)
- [ ] Animated theme transitions when colors change (W3)
- [ ] Micro-interactions — like-button burst, focused context menus, hero cross-fades, undo snackbars (W3)
- [ ] Feel polish — tuned bouncy scroll physics, hide-on-scroll chrome, custom pull-to-refresh (W3)
- [ ] Custom launcher icons (W4)

## Settings

- [x] Settings screen — playback / library / swipes / bridge sections, persisted
- [x] Track-tile swipe action config — left/right actions selectable (play next, queue, favorite, menu)
- [ ] FAB config — none / search / shuffle / play (W2)
- [ ] Default library tab + bottom-navigation toggle (W2)
- [ ] Settings search with jump-and-highlight of the matched tile (W3)
- [ ] Time & date formats — 12/24h toggle and custom date pattern (W3)
- [ ] Keep-screen-awake policy (never / player expanded / video playing) (W3)

## Backup & misc

- [ ] Cache management — image/audio/video cache size caps and per-item clearing with sizes (W3)
- [ ] Backup creation — per-category selection with computed sizes, zipped and timestamped (W4)
- [ ] Restore — automatic (newest backup) or manual pick, hot-reload without app restart (W4)
- [ ] Auto-backup — every N days with retention of the last 10 archives (W4)
- [ ] Cross-device sync — companion sync hook for backup and music folders (W4)
- [ ] Android Auto and wearables — MediaBrowserService + artwork ContentProvider, queue position metadata (W4)
- [ ] Home-screen widget — resizable, palette-tinted artwork widget with heart/prev/play-pause/next, wakes app (W4)
- [ ] Quick-settings tile — live play/pause state and label, wakes app when dead (W4)
- [ ] Share/open intents — register for audio/video files, m3u(8), YouTube links, default-music-player and voice search (W4)
- [ ] Desktop support — Windows/Linux builds with tray, single-instance arg forwarding, file associations, window-state persistence, drag-and-drop to play (W4)
- [ ] Desktop hotkeys — full shortcut map (space, seek, volume, favorite, tabs, ratings) with rebindable global keys (W4)
- [ ] High display refresh-rate request on startup for full-panel-speed scrolling (W4)
- [ ] Onboarding — first-run language/theme/permissions/folders flow with restore-backup offer (W4)
- [ ] Localization — compiled ARB translations with plural rules and per-language display names (W4)
- [ ] Update checker with in-app changelog and shareable logs (W4)
- [ ] Battery-optimization exemption prompt for long-running playback and downloads (W4)
