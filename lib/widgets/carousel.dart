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
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: items.length,
              itemBuilder: (_, i) =>
                  _Card(item: items[i], onTap: () => onTap(items[i])),
            ),
          ),
        ],
      );
}

class _Card extends StatefulWidget {
  final dynamic item;
  final VoidCallback onTap;
  const _Card({required this.item, required this.onTap});

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final img = (it['stream_icon'] ?? it['cover'] ?? '').toString();
    final name = (it['name'] ?? '').toString();
    final fallback = Container(
      color: Colors.grey.shade900,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(name, textAlign: TextAlign.center),
    );

    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      onFocusChange: (f) {
        if (f) {
          Scrollable.ensureVisible(context,
              alignment: 0.5, duration: const Duration(milliseconds: 150));
        }
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        }),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 120,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: _focus ? Colors.white : Colors.transparent, width: 3),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
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
      ),
    );
  }
}
