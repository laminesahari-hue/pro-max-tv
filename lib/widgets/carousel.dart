import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class Carousel extends StatelessWidget {
  final String title;
  final List items;
  final void Function(dynamic) onTap;
  const Carousel(
      {super.key, required this.title, required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          SizedBox(
            height: 190,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final it = items[i];
                final img = (it['stream_icon'] ?? it['cover'] ?? '').toString();
                final name = (it['name'] ?? '').toString();
                final fallback = Container(
                  color: Colors.grey.shade900,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(8),
                  child: Text(name, textAlign: TextAlign.center),
                );
                return InkWell(
                  onTap: () => onTap(it),
                  child: Container(
                    width: 120,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: img.isEmpty
                          ? fallback
                          : CachedNetworkImage(
                              imageUrl: img,
                              fit: BoxFit.cover,
                              memCacheWidth: 300,
                              errorWidget: (_, __, ___) => fallback,
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
}
