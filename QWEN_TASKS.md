# Qwen 3 32B — Work Order for Papa Audio (Wave F)

This file has two parts:

1. **The prompt** — paste Part 1 into Qwen as the first message of the session.
2. **The task list** — Part 2. Give Qwen **one task at a time**, in order. Do not
   paste the whole list at once; a 32B local model degrades badly when it has to
   hold ten unrelated tasks in context.

---

# PART 1 — Paste this first

You are working on **Papa Audio**, a Flutter Android music player at
`/path/to/papa-audio-flutter` (replace with the real path on this machine).
You are continuing an existing, working app. You are not starting a project.

## Absolute rules

1. **Never copy code from Namida** (github.com/namidaco/namida). It is
   EULA-licensed. You may replicate *behavior* described in the task, but every
   line you write must be your own, written against this codebase's own
   architecture. Do not fetch, read, or paste Namida source.
2. **One task at a time.** Do only the task you were given. Do not "also fix"
   unrelated things, do not reformat files, do not rename existing symbols, do
   not upgrade dependencies, do not touch `pubspec.yaml` or `pubspec.lock`.
3. **Read before you write.** Open every file listed in the task's "Files"
   section and read the surrounding code before editing. Match the existing
   style: same naming, same comment density, same widget patterns.
4. **Small diffs.** Most of these tasks are 20–120 lines. If your change is
   ballooning past ~200 lines, stop and say so instead of guessing.
5. **Never invent APIs.** If you need a method on `PlayerService`,
   `SettingsService`, `HistoryService`, or `PlaylistsService`, grep for it
   first. If it does not exist, add it in the service file, not inline in a
   widget.
6. **Do not change the visual language.** The app is Spotify-styled. New UI
   reuses existing widgets from `lib/src/ui/widgets.dart` and the current
   theme (`lib/src/theme.dart`). No new color constants.

## How to verify — required for every task

Run these three, in this order, and paste the real output in your report:

```
flutter analyze          # must be clean — zero errors, zero new warnings
flutter test             # 15 tests exist; all must stay green
flutter build apk --debug
```

If `flutter analyze` reports anything you introduced, fix it before reporting
done. Never report a task done on the strength of "the code looks right" —
in this project a change that passed analyze once shipped a completely broken
app. If a device/emulator is available, install the debug APK and actually
exercise the screen you changed.

## Definition of done for a task

- Code compiles, analyze clean, all tests green.
- The matching line in `NAMIDA_PARITY.md` is flipped from `- [ ]` to `- [x]`
  (edit only that one line).
- Any new user-facing toggle is surfaced in
  `lib/src/ui/settings_screen.dart` — this project's settings service has a
  hard rule that every persisted setting appears in the settings screen.
- One git commit, message format: `Wave F: <short description>`.
- You report: what you changed, which files, the analyze/test output, and
  anything you were unsure about.

## Codebase map — read this, do not re-derive it

`lib/src/` (services, all `ChangeNotifier` unless noted):

| File | What lives there |
|---|---|
| `db.dart` | SQLite v3. Tables: history, favorites, playlists(+tracks), queue_tracks, saved_queues, kv, lyrics, waveforms, collection_resume. **Schema changes go through `onUpgrade` with a version bump — never edit the create statements alone.** |
| `player_service.dart` | just_audio + just_audio_background. Queue ops, persistence, sleep timer, speed/pitch, EQ, transition fades, listen ticks, per-collection resume. **Only one `AudioPlayer` may ever exist** — the background plugin forbids a second one. |
| `settings.dart` | `SettingsService`: plain fields + `init()` reading SharedPreferences with `s.`-prefixed keys + setters that persist and `notifyListeners()`. Copy the existing pattern exactly when adding a setting. |
| `history.dart` | DB-backed listens, revision counter, counts / firstListen / lastListen maps, `rediscover()`. |
| `playlists.dart` | Playlist CRUD, `removeDuplicates`. |
| `queues_store.dart`, `local_library.dart`, `text_norm.dart` (`normText`/`blobMatches`/`TagSplitter`), `lyrics.dart`, `waveform.dart`, `art_color.dart`, `selection.dart`, `downloads.dart`, `bridge.dart` | as named |
| `app_state.dart` | wires the services together (providers) |
| `models.dart` | `Track` and friends |

`lib/src/ui/`:

| File | What lives there |
|---|---|
| `library_tab.dart` (1111 lines) | chip tabs, `enum TrackSort { title, artist, album, year, dateAdded, duration, mostPlayed, firstListen, lastListen }`, memoized per-tab views, `TrackListScreen`, `PlayShuffleRow` |
| `player_sheet.dart` (1113 lines) | gesture morph player, waveform seekbar, lyrics panel, `TransportControls` |
| `home_tab.dart` | quick picks + shelves | 
| `playlists_ui.dart` | playlists tab and playlist screens |
| `dialogs.dart` | `showAddToPlaylistSheet(context, tracks)` and other sheets |
| `track_tile.dart` | configurable swipes, selection, `artistBeforeTitle` |
| `settings_screen.dart` | every setting toggle |
| `collection_menu.dart`, `recently_added.dart`, `stats_screen.dart`, `search_tab.dart`, `music_hub.dart`, `selection_bar.dart`, `equalizer_screen.dart`, `widgets.dart` | as named |

Performance is a hard requirement in this project: memoize by revision
counters, keep work off the UI isolate (`compute`, sqflite, the platform task
queue), lazy lists only, `RepaintBoundary` around high-frequency repaints.

Acknowledge that you have read this, then wait for the first task.

---

# PART 2 — The tasks

Ordered easiest → hardest. Hand them over one at a time.

### F1. Sort: ignore leading "The / A / An"

Add `settings.ignoreLeadingArticles` (default `false`, key `s.ignoreArticles`).
When on, title/artist/album sorting strips a leading `the `, `a `, `an `
(case-insensitive) from the sort key only — displayed text is unchanged.
Put the strip helper in `text_norm.dart` and unit-test it.

- Files: `lib/src/text_norm.dart`, `lib/src/settings.dart`,
  `lib/src/ui/library_tab.dart`, `lib/src/ui/settings_screen.dart`,
  `test/text_norm_test.dart`
- Parity line: "Sorting extras — … ignore leading "The/A/An" (W2)"

### F2. Seekbar: remaining-time toggle

Tapping the right-hand time label in the expanded player toggles between
total duration and remaining time (`-1:23`). Persist the choice as
`settings.showRemainingTime` (key `s.showRemaining`). No new layout — same
label, different text.

- Files: `lib/src/ui/player_sheet.dart`, `lib/src/settings.dart`,
  `lib/src/ui/settings_screen.dart`
- Parity line: "Seek display options — remaining-time toggle …"

### F3. Shuffle behavior setting

Add `settings.shuffleAfterCurrentOnly` (default `false`, key `s.shuffleAfter`).
When off, toggling shuffle behaves as today (whole queue re-rolled). When on,
shuffling only reorders the items *after* the current index; the current track
and everything already played keep their positions.

- Files: `lib/src/player_service.dart` (the shuffle toggle around line 433),
  `lib/src/settings.dart`, `lib/src/ui/settings_screen.dart`
- Note: `just_audio`'s `shuffle()` reshuffles everything, so the
  after-current mode needs an explicit in-place reorder of the queue items
  instead of calling `shuffle()`.
- Parity line: "Shuffle behavior setting — shuffle whole queue vs only the
  items after the current one (W2)"

### F4. Repeat N times

Extend the loop-mode cycle with a "repeat current track N times" state.
Long-press the loop button opens a small number picker (2–20). While active,
the button shows the remaining count and decrements on each repeat; at zero it
advances normally and returns to `LoopMode.off`. The remaining count must be
live-adjustable by long-pressing again.

- Files: `lib/src/player_service.dart`, `lib/src/ui/player_sheet.dart`
- Parity line: "Repeat N times — …"

### F5. Add-to-playlist dialog: containment + duplicate handling

In `showAddToPlaylistSheet`:
- show a checkmark next to each playlist that already contains **all** of the
  passed tracks;
- tapping such a playlist removes them instead of adding (label the action);
- when adding tracks that are already present, show an "Add anyway / Skip
  duplicates" prompt, then a snackbar with an Undo that reverses the exact
  operation.

- Files: `lib/src/ui/dialogs.dart`, `lib/src/playlists.dart`
- Parity lines: "Duplicate handling on add — …" and "Add-to-playlist dialog
  polish — containment checkmarks, remove-if-all-present …" (leave the
  "add-at-beginning toggle" half unchecked unless you also implement it)

### F6. Subpage inline search

Album / artist / genre / folder / playlist screens get a search icon in the
app bar that expands into an inline filter field over that screen's track list
only. Reuse `blobMatches` from `text_norm.dart`. Clearing or collapsing the
field restores the full list. Do not add a new screen.

- Files: `lib/src/ui/library_tab.dart` (`TrackListScreen`),
  `lib/src/ui/playlists_ui.dart`
- Parity line: "Subpage inline search — …"

### F7. Per-tab state in the library

Each library chip tab remembers its own scroll offset and its own filter text
across tab switches. Re-tapping the already-active chip animates that tab's
list back to the top.

- Files: `lib/src/ui/library_tab.dart`
- Note: keep the existing memoization intact — hold a
  `Map<tab, ScrollController>` (and filter strings) in the state object and
  dispose them properly. Do not rebuild the whole tab body on scroll.
- Parity line: "Per-tab state — remembered scroll offset, per-tab filter
  field, re-tap active tab scrolls to top (W2)"

### F8. Playlists tab default cards

Above the playlist list, a row of four cards — History, Most played,
Favourites, Queues — each with a live count, each routing to the screen that
already exists for it. Counts come from the existing services' revision
counters; do not run a query on every rebuild.

- Files: `lib/src/ui/playlists_ui.dart`, read counts from `history.dart` /
  `playlists.dart` / `queues_store.dart`
- Parity line: "Default cards — History / Most played / Favourites / Queues
  cards with live counts atop the tab (W2)"

### F9. Insertion depth: "play after N tracks"

Track and collection context menus get "Play after…" which asks for N and
inserts the selection N positions after the current index (clamped to the
queue length).

- Files: `lib/src/player_service.dart` (queue insert ops),
  `lib/src/ui/dialogs.dart`, `lib/src/ui/collection_menu.dart`
- Parity line: "Insertion depth — play after N tracks, … (W2)" — the
  "remove all-except-current" half is already shipped, so keep the line's
  wording and just check it once "play after N" lands.

### F10. Play-error handling

When a track fails to load, show an in-player banner with a cancellable 7s
countdown, then auto-skip to the next track. Rapid successive skips must
debounce so only the final target is actually loaded.

- Files: `lib/src/player_service.dart`, `lib/src/ui/player_sheet.dart`
- Parity line: "Play-error handling — cancellable 7s auto-skip countdown;
  rapid-skip debounce loads only the final target (W2)"

### Stretch (only if F1–F10 are all green)

- **Track deletion** — delete the file from the device with a confirm dialog
  plus a recently-deleted trail. This touches the filesystem and MediaStore;
  it needs device verification, so do not attempt it without an emulator or
  phone attached.
- **Global search overlay** — morphing app-bar field with sectioned results
  (album/artist rows above the track list).

---

## Handing a task to Qwen

Paste this wrapper around each task:

> Task **F<n>** from the work order. Read the files listed, make the change,
> then run `flutter analyze`, `flutter test`, and `flutter build apk --debug`
> and paste the output. Flip the parity line, commit as
> `Wave F: <description>`. Do not start any other task.
>
> <paste the task block here>

If Qwen returns a change that does not compile, do not let it iterate blindly
more than twice on the same error — paste the exact compiler message back and
tell it which file and line to look at.
