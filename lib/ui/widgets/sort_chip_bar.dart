import 'package:flutter/material.dart';

import '../../src/theme.dart';
import '../../services/sort_service.dart';

/// Horizontal scrollable row of [FilterChip] widgets, one per [SortType].
/// Tap a chip to change the active sort order — the parent rebuilds the
/// track list accordingly.
class SortChipBar extends StatelessWidget {
  final SortType currentSort;
  final ValueChanged<SortType> onSortChanged;

  const SortChipBar({
    super.key,
    required this.currentSort,
    required this.onSortChanged,
  });

  static const _types = SortType.values;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final t = _types[i];
          final selected = t == currentSort;
          return FilterChip(
            selected: selected,
            showCheckmark: false,
            label: Text(SortService.labelOf(t),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? Colors.black : PA.textSecondary)),
            backgroundColor: PA.card,
            selectedColor: PA.accent,
            side: BorderSide(
                color: selected ? PA.accent : PA.separator, width: 0.5),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            labelPadding: EdgeInsets.zero,
            onSelected: (_) => onSortChanged(t),
          );
        },
      ),
    );
  }
}
