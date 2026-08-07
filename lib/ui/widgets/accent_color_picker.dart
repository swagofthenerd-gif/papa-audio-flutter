import 'package:flutter/material.dart';
import '../theme/papa_theme.dart';

/// Accent color picker — grid of preset colors with live preview.
class AccentColorPicker extends StatefulWidget {
  const AccentColorPicker({super.key});

  @override
  State<AccentColorPicker> createState() => _AccentColorPickerState();
}

class _AccentColorPickerState extends State<AccentColorPicker> {
  late Color _selected;

  @override
  void initState() {
    super.initState();
    _selected = PapaTheme.accentColor;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Live preview
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: PapaTheme.getBackground(),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PapaTheme.getCard()),
          ),
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _selected,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(Icons.music_note, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                'Preview',
                style: TextStyle(color: _selected, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'This is how your accent will look',
                style: TextStyle(color: PapaTheme.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Choose Accent Color',
          style: TextStyle(
            color: PapaTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        // Color grid
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: PapaTheme.presetAccents.map((color) {
            final isSelected = _selected.value == color.value;
            return GestureDetector(
              onTap: () {
                setState(() => _selected = color);
                PapaTheme.setAccentColor(color);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 3)
                      : null,
                  boxShadow: isSelected
                      ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12)]
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 22)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// OLED pure-black theme toggle card
class OledThemeToggle extends StatelessWidget {
  const OledThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: PapaTheme.isOledMode ? PapaTheme.accentColor : PapaTheme.getCard(),
          width: PapaTheme.isOledMode ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF080808),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF333333)),
            ),
            child: const Icon(Icons.dark_mode, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pure Black OLED',
                  style: TextStyle(
                    color: PapaTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'True black on OLED displays. Saves battery.',
                  style: TextStyle(color: PapaTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          Switch(
            value: PapaTheme.isOledMode,
            activeColor: PapaTheme.accentColor,
            onChanged: (value) {
              PapaTheme.setOledMode(value);
              // Force rebuild by going to home
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const _DummyHome()),
                (_) => false,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DummyHome extends StatelessWidget {
  const _DummyHome();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
