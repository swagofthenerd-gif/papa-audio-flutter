import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../src/app_state.dart';
import '../../src/models.dart';
import '../../src/theme.dart';
import '../../services/mixes_service.dart';

/// "Smart Mixes" section: a 2×2 grid of gradient cards, each generating and
/// playing a curated mix when tapped. Sits on the Home tab.
class MixesSection extends StatefulWidget {
  const MixesSection({super.key});

  @override
  State<MixesSection> createState() => _MixesSectionState();
}

class _MixesSectionState extends State<MixesSection> {
  MixesService? _service;
  String? _generating; // which mix is currently being generated

  MixesService _ensureService(AppState s) {
    if (_service != null) return _service!;
    _service = MixesService(
      history: s.history,
      playlists: s.playlists,
      allTracks: () =>
          s.localLibrary.albums.expand((a) => a.tracks).toList(),
    );
    return _service!;
  }

  void _playMix(AppState s, String label,
      List<Track> Function(MixesService svc) generate) {
    if (_generating != null) return;
    setState(() => _generating = label);
    final svc = _ensureService(s);
    // Generate synchronously (it's all in-memory math), then play.
    final tracks = generate(svc);
    setState(() => _generating = null);
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('No tracks available for $label'),
            backgroundColor: PA.surfaceElevated),
      );
      return;
    }
    s.playerService.playShuffled(tracks);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final mixes = [
      _MixDef(
        label: 'Discover',
        subtitle: 'Fresh picks for you',
        icon: Icons.explore,
        gradient: [const Color(0xFF4A148C), const Color(0xFF7B1FA2)],
        generate: (svc) => svc.generateDiscoverMix(),
      ),
      _MixDef(
        label: 'Favorites',
        subtitle: 'Your loved tracks',
        icon: Icons.favorite,
        gradient: [const Color(0xFFB71C1C), const Color(0xFFE53935)],
        generate: (svc) => svc.generateFavoritesMix(),
      ),
      _MixDef(
        label: 'Rediscover',
        subtitle: 'Hidden gems',
        icon: Icons.history,
        gradient: [const Color(0xFF0D47A1), const Color(0xFF1E88E5)],
        generate: (svc) => svc.generateRediscoverMix(),
      ),
      _MixDef(
        label: 'Random Mix',
        subtitle: 'Anything goes',
        icon: Icons.shuffle,
        gradient: [const Color(0xFF1B5E20), const Color(0xFF43A047)],
        generate: (svc) => svc.generateRandomMix(),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
            child: Text('Smart Mixes',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.6,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              for (final m in mixes)
                _MixCard(
                  def: m,
                  loading: _generating == m.label,
                  onTap: () => _playMix(s, m.label, m.generate),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MixDef {
  final String label;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final List<Track> Function(MixesService) generate;
  const _MixDef({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.generate,
  });
}

class _MixCard extends StatelessWidget {
  final _MixDef def;
  final bool loading;
  final VoidCallback onTap;

  const _MixCard({
    required this.def,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: loading ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: def.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(def.label,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    const SizedBox(height: 3),
                    Text(def.subtitle,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white70))
              else
                Icon(def.icon, color: Colors.white70, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
