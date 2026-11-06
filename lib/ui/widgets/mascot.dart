import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/icon_schedule.dart';

/// The time-of-day mascot, gently bobbing and "breathing" in the header.
class AnimatedMascot extends StatefulWidget {
  const AnimatedMascot({super.key, required this.variant, this.size = 64, this.animate = true});
  final IconVariant variant;
  final double size;
  final bool animate;

  @override
  State<AnimatedMascot> createState() => _AnimatedMascotState();
}

class _AnimatedMascotState extends State<AnimatedMascot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(IconSchedule.asset(widget.variant),
        width: widget.size, height: widget.size, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final p = _c.value * 2 * math.pi;
        // Night mascot breathes slowly; daytime ones bob a bit more.
        final amp = widget.variant == IconVariant.night ? 1.5 : 4.0;
        final squash = 1 + 0.035 * math.sin(p * 2);
        return Transform.translate(
          offset: Offset(0, -amp * math.sin(p).abs()),
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.diagonal3Values(1 / squash, squash, 1),
            child: child,
          ),
        );
      },
      child: AnimatedSwitcher(duration: const Duration(milliseconds: 600), child: KeyedSubtree(key: ValueKey(widget.variant), child: img)),
    );
  }
}

/// Header sky gradient matching the launcher icon of the moment.
List<Color> skyFor(IconVariant v) => switch (v) {
      IconVariant.morning => const [Color(0xFFFFC28E), Color(0xFFFFECC6)],
      IconVariant.afternoon => const [Color(0xFF5AAAFA), Color(0xFFCBE6FF)],
      IconVariant.evening => const [Color(0xFF6E4CAA), Color(0xFFFF965F)],
      IconVariant.night => const [Color(0xFF14183C), Color(0xFF342C70)],
    };
