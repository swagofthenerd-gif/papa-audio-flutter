# Namida-feel UI/UX punch list

Curated, prioritized UI/UX work left to make the app *feel* like Namida. Scope is
**visible look & interaction** — pure-backend items (indexer, remote sources,
tag-write pipeline, backup internals) live in `NAMIDA_PARITY.md`, not here.

Legend: **[S]** small/polish · **[M]** medium · **[L]** large. Ordered by
feel-per-effort within each section. Verify each on the emulator.

---

## 1. Quick wins — highest feel-per-effort, do first
- [x] **[S] Haptics everywhere** — light tick on long-press select, swipe-commit, drag-reorder, tab switch, snap of the player sheet. (home cards/chips, favorite, swipe-commit, reorder, tab switch, sheet snap done 2026-07-19; track-tile long-press select done 2026-07-20.)
- [x] **[S] Press-scale on cards** — `AnimatedScale` to ~0.96 on tap-down for shelf/album/track cards (shared `PressScale` in widgets.dart; home cards + YT shelf cards 2026-07-20).
- [x] **[S] Like-button burst** — heart scale-bounce + haptic on favorite toggle (player). TODO: extend to track-tile hearts.
- [x] **[S] AnimatedIcon play/pause** — player main button + expanded utility row now morph (`AnimatedIcons.play_pause`). TODO: mini-bar bottom strip if it has its own.
- [ ] **[S] Hero cross-fade** — `Hero` on artwork from card → album/player so it morphs instead of cutting.
- [x] **[S] Empty-state polish** — shared `EmptyState` (icon + title + hint + optional action) in widgets.dart; applied to library tabs (tracks/albums/artists/folders/genres), empty playlist, YT library. Search idle already shows the Explore feed; search no-results already iconified. (2026-07-20)
- [x] **[S] Undo snackbars** on every destructive action — added to playlist-track remove and saved-queue delete (2026-07-20); in-player queue remove and history-entry delete already had them. All swipe-to-remove flows now undoable.
- [x] **[S] Bouncy scroll physics** — app-wide `BouncingScrollPhysics` + stretch overscroll via `MaterialApp.scrollBehavior`.

## 2. Home & library feel
- [ ] **[M] Default cards atop Library** — History / Most-played / Favourites / Queues cards with **live counts** (Namida's signature library header).
- [ ] **[M] Library tabs editor** — reorder / enable-disable tabs (min 2), pick default startup tab.
- [ ] **[M] Per-tab state** — remembered scroll offset + per-tab filter field; re-tap the active tab scrolls to top.
- [ ] **[M] Subpage headers** — album/artist/playlist pages get artwork, "N songs · MM min", and Play/Shuffle with advanced modes (random N, insert next/after).
- [ ] **[M] Subpage inline search** — filter tracks within an album/artist/playlist page.
- [ ] **[M] Folder tree mode** — real hierarchy with breadcrumb + subfolder counts + flat toggle (currently flat groups only).
- [ ] **[S] Jump-to-track pill** — animated pill that appears while scrolling a long list, tapping jumps to the now-playing track; icon reflects scroll position (up/down/CD).
- [ ] **[M] Track-tile layout editor** — configurable rows/fields, sizes, inline heart (Namida lets users design the row).
- [x] **[S] Genre collage cards** (2026-07-19: shared MosaicArt on genre tiles)

## 3. Player feel (the expanded player is where Namida shines)
- [x] **[M] Queue slide-up layer** (2026-07-19: drag-up in-player panel)
- [ ] **[S] Audio-info line** — codec / bitrate / sample-rate readout in the expanded player.
- [~] **[S] Seek display options** (2026-07-19: remaining-time toggle done; delta bubble + drag-to-cancel pending) — remaining-time toggle; show +/- delta bubble while scrubbing the waveform; drag-up-to-cancel seek.
- [x] **[M] Beat-reactive artwork pulse** (2026-07-19: waveform-amplitude pulse on the carousel card, local tracks)
- [ ] **[M] Party mode** — beat-synced edge glow around the screen, optional multi-color palette swap.
- [ ] **[S] Idle dimming** — dim the expanded player after N seconds, touch to wake.
- [ ] **[S] Immersive mode + wakelock** while the player is expanded.
- [ ] **[S] Artwork gestures** — configurable tap / long-press / double-tap (double-tap already toggles lyrics — extend), pinch-to-zoom.
- [x] **[M] Player background** (2026-07-19: top gradient + art glow + animated cross-fade)
- [ ] **[S] Swipe-down to dismiss** — optional: stops playback + clears queue with elastic headroom.

## 4. Navigation, search & interactions
- [ ] **[M] Global search overlay** — morphing app-bar search field with sectioned results (album/artist rows above the track list) — the Namida search feel.
- [x] **[S] Media-type filter chips** in search results (All / Songs / Albums / Artists) — narrow the unified results by type, haptic on select. (2026-07-20)
- [ ] **[S] FAB config** — none / search / shuffle / play, per setting.
- [ ] **[S] Collection context menus** — ensure album/artist/genre/folder/playlist long-press menus all offer play-next/add-queue/shuffle/add-to-playlist/go-to consistently.
- [ ] **[M] Multi-select extras** — range selection, bulk actions bar polish.

## 5. Theming & motion
- [ ] **[M] Theme modes** — light / dark / system + a pitch-black **AMOLED** variant (app is dark-only now).
- [ ] **[S] Material You accent** — optional wallpaper-derived accent on Android 12+.
- [ ] **[S] Custom accent picker** + per-track palette.
- [ ] **[S] Animated theme transitions** when the art-derived colors change.
- [ ] **[S] Hide-on-scroll chrome** — app bar / nav hide as you scroll down, reappear on scroll up.
- [ ] **[S] Custom launcher icon** — needs a design asset (currently the default Flutter icon).

## 6. History & stats surfaces (Namida is stats-obsessed)
- [ ] **[M] Calendar heatmap** — month view shaded by listen density, tap a day → jump into history.
- [ ] **[S] Jump-to-day dialog** + pinned year chips for fast history navigation.
- [ ] **[S] Listens dialog** — every timestamp for a track, jump to the exact history entry.
- [ ] **[S] Listen-order badges** + first-listen marker on history entries.
- [ ] **[S] Custom date range** for most-played, calendar picker constrained to days that have history.

## 7. YouTube surfaces (finish the Namida-parity feel)
- [ ] **[M] Channel pages** — banner + tabs (songs / albums / singles / about), bulk play/download.
- [ ] **[M] Subscriptions feed** — dedicated view with subscribe/unsubscribe.
- [ ] **[S] Clipboard link monitoring** — a copied YouTube link surfaces a "play/open" chip.
- [ ] **[L] Comments** — read/sort (post/reply is a big lift; read-only is a good first cut).
- [ ] **[S] Mixed local + YouTube queue** visual clarity — per-item source badge in the queue.

## Already done (do NOT redo) — for the other session's awareness
Home revamp (date header, mixes, artist tiles, filter chips, art-color header gradient, skeletons, mosaic covers, hashed placeholder art), recommendation shelves, real M3 theme (fixes purple nav pill), WCAG-AA muted text, ripple + long-press menus on home cards, undo on queue-replace, YouTube Explore/library/import/download, audio-first video toggle, on-device YT download menu, home card overflow fix, Firefox-UA login. See git log on `claude/project-changes-review-zgqc3y`.
