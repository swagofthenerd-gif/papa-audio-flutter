import 'package:flutter/material.dart';

/// Skeleton placeholder boxes with a left-to-right shimmer animation.
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  const ShimmerBox(
      {super.key,
      this.width = double.infinity,
      this.height = 16,
      this.borderRadius = 6});

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();
  late final Animation<double> _a = Tween(begin: -2.0, end: 2.0)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOutSine));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(_a.value - 1, 0),
            end: Alignment(_a.value, 0),
            colors: const [
              Color(0xFF1A1A1A),
              Color(0xFF2A2A2A),
              Color(0xFF1A1A1A)
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Grid of shimmer album-card placeholders.
class ShimmerGrid extends StatelessWidget {
  final int columns;
  final int count;
  final double childAspectRatio;
  const ShimmerGrid(
      {super.key,
      this.columns = 2,
      this.count = 6,
      this.childAspectRatio = 0.78});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: count,
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(child: ShimmerBox(borderRadius: 8)),
          const SizedBox(height: 6),
          const ShimmerBox(width: double.infinity, height: 14),
          const SizedBox(height: 4),
          const ShimmerBox(width: 80, height: 12),
        ],
      ),
    );
  }
}

/// Horizontal row of shimmer card placeholders (for "shelf" loading).
class ShimmerRow extends StatelessWidget {
  final int count;
  const ShimmerRow({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 192,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => SizedBox(
          width: 138,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ShimmerBox(width: 138, height: 138, borderRadius: 8),
              const SizedBox(height: 6),
              const ShimmerBox(width: 120, height: 14),
              const SizedBox(height: 4),
              const ShimmerBox(width: 80, height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen shimmer loading for tabs — a stack of shelf-like skeletons.
class ShimmerTab extends StatelessWidget {
  final int shelves;
  const ShimmerTab({super.key, this.shelves = 4});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          for (var i = 0; i < shelves; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const ShimmerBox(width: 140, height: 18),
            ),
            const SizedBox(height: 8),
            const ShimmerRow(),
          ],
        ],
      ),
    );
  }
}
