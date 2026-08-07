import 'package:flutter/material.dart';
import '../theme/papa_theme.dart';
import 'accent_color_picker.dart';
import '../../services/lastfm_service.dart';

/// Comprehensive settings page covering all Namida settings categories.
class FullSettingsPage extends StatefulWidget {
  const FullSettingsPage({super.key});

  @override
  State<FullSettingsPage> createState() => _FullSettingsPageState();
}

class _FullSettingsPageState extends State<FullSettingsPage> {
  // Audio
  bool _crossfade = true;
  double _crossfadeDuration = 5.0;
  bool _skipSilence = false;
  bool _replayGain = true;
  bool _speedPitchLinked = true;
  double _defaultSpeed = 1.0;
  double _defaultPitch = 0.0;
  bool _playOnSkip = true;
  int _holdSeekSeconds = 5;
  String _tapMode = 'list';
  bool _queueEndRestart = false;

  // Player UI
  bool _dynamicArtworkColors = true;
  double _playPauseFadeDuration = 0.08;
  bool _artistBeforeTitle = false;
  int _gridColumns = 2;
  String _swipeLeftAction = 'play_next';
  String _swipeRightAction = 'add_to_queue';
  int _listenThreshold = 50;
  bool _preferSyncedLyrics = true;
  bool _waveformSeekbar = true;
  bool _elapsedTimeFirst = true;

  // Library
  String _tagSeparatorArtist = '; ';
  String _tagSeparatorGenre = '; ';
  bool _showAlbumArtist = true;
  bool _multiDiscSections = true;
  String _defaultSort = 'album';
  bool _naturalSortFolders = true;

  // Home
  bool _showGreeting = true;
  bool _showQuickPicks = true;
  bool _showRecentlyPlayed = true;
  bool _showMostPlayed = true;
  bool _showRediscover = true;
  bool _showRecentlyAdded = true;
  bool _showSmartMixes = true;
  bool _showPlaylistsShelf = true;
  bool _showPcLibraryShelf = true;

  // PC Bridge
  String _bridgeIp = '192.168.29.156';
  int _bridgePort = 8765;
  bool _autoConnect = true;

  // Advanced
  bool _oledMode = false;
  bool _highRefreshRate = true;
  bool _hapticFeedback = true;
  String _downloadPath = '/storage/emulated/0/PapaAudio';

  @override
  void initState() {
    super.initState();
    _oledMode = PapaTheme.isOledMode;
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    // Load all settings from SharedPreferences
    // In production, each toggle reads/writes its own key
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PapaTheme.getBackground(),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: PapaTheme.getBackground(),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // ── AUDIO ──
          _sectionHeader('Audio'),
          SwitchListTile(
            title: const Text('Crossfade'),
            subtitle: const Text('Smooth transitions between tracks'),
            value: _crossfade,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _crossfade = v),
          ),
          if (_crossfade)
            ListTile(
              title: const Text('Crossfade Duration'),
              subtitle: Text('${_crossfadeDuration.round()} seconds'),
              trailing: SizedBox(
                width: 200,
                child: Slider(
                  value: _crossfadeDuration,
                  min: 1,
                  max: 20,
                  divisions: 19,
                  activeColor: PapaTheme.accentColor,
                  label: '${_crossfadeDuration.round()}s',
                  onChanged: (v) => setState(() => _crossfadeDuration = v),
                ),
              ),
            ),
          SwitchListTile(
            title: const Text('Skip Silence'),
            subtitle: const Text('Automatically skip silent parts'),
            value: _skipSilence,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _skipSilence = v),
          ),
          SwitchListTile(
            title: const Text('Replay Gain'),
            subtitle: const Text('Normalize volume across tracks'),
            value: _replayGain,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _replayGain = v),
          ),
          const Divider(height: 1),

          // ── SPEED & PITCH ──
          _sectionHeader('Speed & Pitch'),
          SwitchListTile(
            title: const Text('Link Speed & Pitch'),
            value: _speedPitchLinked,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _speedPitchLinked = v),
          ),
          ListTile(
            title: const Text('Default Speed'),
            subtitle: Text('${_defaultSpeed.toStringAsFixed(2)}x'),
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: _defaultSpeed,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                activeColor: PapaTheme.accentColor,
                label: '${_defaultSpeed.toStringAsFixed(2)}x',
                onChanged: (v) => setState(() => _defaultSpeed = v),
              ),
            ),
          ),
          ListTile(
            title: const Text('Default Pitch'),
            subtitle: Text('${_defaultPitch.toStringAsFixed(1)} semitones'),
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: _defaultPitch,
                min: -12,
                max: 12,
                divisions: 24,
                activeColor: PapaTheme.accentColor,
                label: '${_defaultPitch.toStringAsFixed(1)}st',
                onChanged: (v) => setState(() => _defaultPitch = v),
              ),
            ),
          ),
          const Divider(height: 1),

          // ── PLAYBACK BEHAVIOR ──
          _sectionHeader('Playback Behavior'),
          SwitchListTile(
            title: const Text('Play on Skip'),
            subtitle: const Text('Auto-play when skipping while paused'),
            value: _playOnSkip,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _playOnSkip = v),
          ),
          ListTile(
            title: const Text('Hold Seek Duration'),
            subtitle: Text('$_holdSeekSeconds seconds'),
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: _holdSeekSeconds.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                activeColor: PapaTheme.accentColor,
                label: '${_holdSeekSeconds}s',
                onChanged: (v) => setState(() => _holdSeekSeconds = v.round()),
              ),
            ),
          ),
          ListTile(
            title: const Text('Tap Mode'),
            subtitle: Text(_tapMode == 'list' ? 'List: tap adds to queue' : _tapMode == 'single' ? 'Single: tap plays immediately' : 'Gentle: double-tap to play'),
            trailing: DropdownButton<String>(
              value: _tapMode,
              dropdownColor: PapaTheme.getSurfaceElevated(),
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'list', child: Text('List')),
                DropdownMenuItem(value: 'single', child: Text('Single')),
                DropdownMenuItem(value: 'gentle', child: Text('Gentle')),
              ],
              onChanged: (v) => setState(() => _tapMode = v!),
            ),
          ),
          SwitchListTile(
            title: const Text('Queue End Restart'),
            subtitle: const Text('Return to queue top when finished'),
            value: _queueEndRestart,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _queueEndRestart = v),
          ),
          const Divider(height: 1),

          // ── PLAYER UI ──
          _sectionHeader('Player Interface'),
          SwitchListTile(
            title: const Text('Dynamic Artwork Colors'),
            subtitle: const Text('Tint background from album art'),
            value: _dynamicArtworkColors,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _dynamicArtworkColors = v),
          ),
          SwitchListTile(
            title: const Text('Artist Before Title'),
            subtitle: const Text('Show artist name first in track lists'),
            value: _artistBeforeTitle,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _artistBeforeTitle = v),
          ),
          SwitchListTile(
            title: const Text('Waveform Seekbar'),
            subtitle: const Text('Visual waveform on progress bar'),
            value: _waveformSeekbar,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _waveformSeekbar = v),
          ),
          SwitchListTile(
            title: const Text('Elapsed / Remaining Toggle'),
            subtitle: const Text('Tap time display to switch'),
            value: _elapsedTimeFirst,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _elapsedTimeFirst = v),
          ),
          ListTile(
            title: const Text('Swipe Left Action'),
            subtitle: Text(_swipeLeftAction == 'play_next' ? 'Play Next' : _swipeLeftAction == 'add_to_queue' ? 'Add to Queue' : 'Toggle Favorite'),
            trailing: DropdownButton<String>(
              value: _swipeLeftAction,
              dropdownColor: PapaTheme.getSurfaceElevated(),
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'play_next', child: Text('Play Next')),
                DropdownMenuItem(value: 'add_to_queue', child: Text('Add to Queue')),
                DropdownMenuItem(value: 'toggle_favorite', child: Text('Toggle Favorite')),
              ],
              onChanged: (v) => setState(() => _swipeLeftAction = v!),
            ),
          ),
          ListTile(
            title: const Text('Swipe Right Action'),
            subtitle: Text(_swipeRightAction == 'play_next' ? 'Play Next' : _swipeRightAction == 'add_to_queue' ? 'Add to Queue' : 'Toggle Favorite'),
            trailing: DropdownButton<String>(
              value: _swipeRightAction,
              dropdownColor: PapaTheme.getSurfaceElevated(),
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'play_next', child: Text('Play Next')),
                DropdownMenuItem(value: 'add_to_queue', child: Text('Add to Queue')),
                DropdownMenuItem(value: 'toggle_favorite', child: Text('Toggle Favorite')),
              ],
              onChanged: (v) => setState(() => _swipeRightAction = v!),
            ),
          ),
          ListTile(
            title: const Text('Grid Columns'),
            subtitle: Text('$_gridColumns columns'),
            trailing: DropdownButton<int>(
              value: _gridColumns,
              dropdownColor: PapaTheme.getSurfaceElevated(),
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 2, child: Text('2')),
                DropdownMenuItem(value: 3, child: Text('3')),
              ],
              onChanged: (v) => setState(() => _gridColumns = v!),
            ),
          ),
          ListTile(
            title: const Text('Listen Threshold'),
            subtitle: Text('$_listenThreshold% of track to count as listened'),
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: _listenThreshold.toDouble(),
                min: 10,
                max: 100,
                divisions: 18,
                activeColor: PapaTheme.accentColor,
                label: '$_listenThreshold%',
                onChanged: (v) => setState(() => _listenThreshold = v.round()),
              ),
            ),
          ),
          const Divider(height: 1),

          // ── LIBRARY ──
          _sectionHeader('Library'),
          SwitchListTile(
            title: const Text('Show Album Artist'),
            value: _showAlbumArtist,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _showAlbumArtist = v),
          ),
          SwitchListTile(
            title: const Text('Multi-Disc Sections'),
            subtitle: const Text('Group tracks by disc number'),
            value: _multiDiscSections,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _multiDiscSections = v),
          ),
          SwitchListTile(
            title: const Text('Natural Sort Folders'),
            subtitle: const Text('"Music 2" before "Music 12"'),
            value: _naturalSortFolders,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _naturalSortFolders = v),
          ),
          ListTile(
            title: const Text('Artist Tag Separator'),
            subtitle: Text('Current: "$_tagSeparatorArtist"'),
            trailing: const Icon(Icons.edit, color: PapaTheme.textSecondary),
            onTap: () => _editText('Artist Tag Separator', _tagSeparatorArtist, (v) => setState(() => _tagSeparatorArtist = v)),
          ),
          ListTile(
            title: const Text('Genre Tag Separator'),
            subtitle: Text('Current: "$_tagSeparatorGenre"'),
            trailing: const Icon(Icons.edit, color: PapaTheme.textSecondary),
            onTap: () => _editText('Genre Tag Separator', _tagSeparatorGenre, (v) => setState(() => _tagSeparatorGenre = v)),
          ),
          const Divider(height: 1),

          // ── HOME PAGE ──
          _sectionHeader('Home Page'),
          SwitchListTile(
            title: const Text('Greeting Header'),
            value: _showGreeting,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _showGreeting = v),
          ),
          SwitchListTile(
            title: const Text('Quick Picks Grid'),
            value: _showQuickPicks,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _showQuickPicks = v),
          ),
          SwitchListTile(
            title: const Text('Recently Played Shelf'),
            value: _showRecentlyPlayed,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _showRecentlyPlayed = v),
          ),
          SwitchListTile(
            title: const Text('Most Played Shelf'),
            value: _showMostPlayed,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _showMostPlayed = v),
          ),
          SwitchListTile(
            title: const Text('Rediscover Shelf'),
            value: _showRediscover,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _showRediscover = v),
          ),
          SwitchListTile(
            title: const Text('Smart Mixes'),
            value: _showSmartMixes,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _showSmartMixes = v),
          ),
          const Divider(height: 1),

          // ── PC BRIDGE ──
          _sectionHeader('PC Bridge'),
          ListTile(
            title: const Text('Server IP'),
            subtitle: Text(_bridgeIp),
            trailing: const Icon(Icons.edit, color: PapaTheme.textSecondary),
            onTap: () => _editText('Server IP', _bridgeIp, (v) => setState(() => _bridgeIp = v)),
          ),
          ListTile(
            title: const Text('Port'),
            subtitle: Text('$_bridgePort'),
            trailing: const Icon(Icons.edit, color: PapaTheme.textSecondary),
            onTap: () => _editNumber('Port', _bridgePort, (v) => setState(() => _bridgePort = v)),
          ),
          SwitchListTile(
            title: const Text('Auto-Connect'),
            subtitle: const Text('Connect on app launch'),
            value: _autoConnect,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _autoConnect = v),
          ),
          const Divider(height: 1),

          // ── THEME ──
          _sectionHeader('Theme'),
          const Padding(
            padding: EdgeInsets.all(16),
            child: AccentColorPicker(),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: OledThemeToggle(),
          ),
          const Divider(height: 1),

          // ── LAST.FM ──
          _sectionHeader('Last.fm Scrobbling'),
          SwitchListTile(
            title: const Text('Enable Scrobbling'),
            subtitle: Text(LastFmService.instance.isEnabled ? 'Logged in as ${LastFmService.instance.username ?? "..."}' : 'Track your listening history'),
            value: LastFmService.instance.isEnabled,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) async {
              if (v) {
                await LastFmService.instance.authenticate();
              } else {
                await LastFmService.instance.logout();
              }
              setState(() {});
            },
          ),
          const Divider(height: 1),

          // ── ADVANCED ──
          _sectionHeader('Advanced'),
          SwitchListTile(
            title: const Text('High Refresh Rate'),
            subtitle: const Text('Use 90/120Hz display if available'),
            value: _highRefreshRate,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _highRefreshRate = v),
          ),
          SwitchListTile(
            title: const Text('Haptic Feedback'),
            subtitle: const Text('Vibrate on interactions'),
            value: _hapticFeedback,
            activeColor: PapaTheme.accentColor,
            onChanged: (v) => setState(() => _hapticFeedback = v),
          ),
          ListTile(
            title: const Text('Download Path'),
            subtitle: Text(_downloadPath),
            trailing: const Icon(Icons.folder, color: PapaTheme.textSecondary),
            onTap: () {},
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: PapaTheme.accentColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  void _editText(String title, String current, Function(String) onSave) {
    final controller = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PapaTheme.getSurfaceElevated(),
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: PapaTheme.getBackground(),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              onSave(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _editNumber(String title, int current, Function(int) onSave) {
    final controller = TextEditingController(text: current.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PapaTheme.getSurfaceElevated(),
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: PapaTheme.getBackground(),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              onSave(int.tryParse(controller.text) ?? current);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
