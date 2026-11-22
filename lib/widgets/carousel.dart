import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/models.dart';

class PosterCard extends StatefulWidget {
  final Item item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double? progress;
  const PosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.progress,
  });

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focus = false;

  Widget _placeholder() => Container(
        color: const Color(0xFF1A1D26),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: Text(widget.item.name,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12)),
      );

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final live = it.kind == Kind.live;
    final image = it.image.isEmpty
        ? _placeholder()
        : Container(
            color: live ? const Color(0xFF1A1D26) : null,
            padding: live ? const EdgeInsets.all(14) : null,
            child: CachedNetworkImage(
              imageUrl: it.image,
              fit: live ? BoxFit.contain : BoxFit.cover,
              memCacheWidth: 300,
              placeholder: (_, __) => const ColoredBox(color: Color(0xFF1A1D26)),
              errorWidget: (_, __, ___) => _placeholder(),
            ),
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
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: _focus ? Colors.white : Colors.transparent, width: 2),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox.expand(
                  child: Stack(fit: StackFit.expand, children: [
                    image,
                    if (!live && it.rating5 > 0)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4)),
                          child: Text('★ ${it.rating5.toStringAsFixed(1)}',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.amber)),
                        ),
                      ),
                    if (widget.progress != null)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                            value: widget.progress, minHeight: 3),
                      ),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: Text(it.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      ),
    );
  }
}

class Rail extends StatelessWidget {
  final String title;
  final List<Item> items;
  final void Function(Item) onTap;
  final double Function(Item)? progress;
  final double width;

  const Rail({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    this.progress,
    this.width = 118,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      ),
      SizedBox(
        height: width * 1.5 + 40,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: items.length,
          itemBuilder: (_, i) => SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PosterCard(
                item: items[i],
                onTap: () => onTap(items[i]),
                progress: progress?.call(items[i]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          ]),
        ),
      );
}
