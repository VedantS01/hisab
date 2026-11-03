/// Insight cards in a 0.9-viewport pager with dots. Three cards at most: the
/// strip is furniture, not a feed.
library;

import 'package:flutter/material.dart';

import 'hisab_design.dart';
import 'surface_card.dart';
import 'tokens.dart';

class InsightCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onTap;

  const InsightCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    return SurfaceCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: c.brandText),
              const SizedBox(width: HisabSpace.s8),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HisabType.title.copyWith(color: c.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: HisabSpace.s8),
          Flexible(
            child: Text(body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: HisabType.body.copyWith(color: c.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class InsightCarousel extends StatefulWidget {
  /// Only the first [maxCards] are shown.
  final List<Widget> cards;

  static const maxCards = 3;

  const InsightCarousel({super.key, required this.cards});

  @override
  State<InsightCarousel> createState() => _InsightCarouselState();
}

class _InsightCarouselState extends State<InsightCarousel> {
  final _controller = PageController(viewportFraction: 0.9);
  var _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards.take(InsightCarousel.maxCards).toList();
    if (cards.isEmpty) return const SizedBox.shrink();
    final c = context.hisab;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 124,
          child: PageView.builder(
            controller: _controller,
            itemCount: cards.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: HisabSpace.s4),
              child: cards[index],
            ),
          ),
        ),
        if (cards.length > 1) ...[
          const SizedBox(height: HisabSpace.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < cards.length; i++)
                AnimatedContainer(
                  duration: HisabMotion.medium,
                  curve: HisabMotion.curve,
                  margin: const EdgeInsets.symmetric(horizontal: HisabSpace.s2),
                  width: i == _page ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? c.brand : c.textTertiary,
                    borderRadius: BorderRadius.circular(HisabRadius.pill),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
