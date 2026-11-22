import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/models.dart';

class FeaturedBanner extends StatefulWidget {
  final List<Item> items;
  final void Function(Item) onTap;
  const FeaturedBanner({super.key, required this.items, required this.onTap});

  @override
  State<FeaturedBanner> createState() => _FeaturedBannerState();
}

class _FeaturedBannerState extends State<FeaturedBanner> {
  final _c = PageController();
  Timer? _t;
  int _p = 0;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_c.hasClients) return;
      _c.animateToPage((_p + 1) % widget.items.length,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  Widget _slide(Item it) {
    final img = CachedNetworkImage(
      imageUrl: it.image,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => const SizedBox(),
    );
    return Stack(fit: StackFit.expand, children: [
      ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22), child: img),
      Container(color: Colors.black54),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Row(children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.kind == Kind.series ? 'SÉRIE' : 'FILM',
                    style: const TextStyle(
                        fontSize: 11, letterSpacing: 2, color: Colors.white70)),
                const SizedBox(height: 6),
                Text(it.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
                if (it.rating5 > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('★ ${it.rating5.toStringAsFixed(1)} / 5',
                        style: const TextStyle(color: Colors.amber)),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => widget.onTap(it),
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Détails'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: 120, height: double.infinity, child: img),
          ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 250,
        child: Stack(children: [
          PageView.builder(
            controller: _c,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _p = i),
            itemBuilder: (_, i) => _slide(widget.items[i]),
          ),
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < widget.items.length; i++)
                Container(
                  width: i == _p ? 16 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _p ? Colors.white : Colors.white38,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ]),
          ),
        ]),
      );
}
