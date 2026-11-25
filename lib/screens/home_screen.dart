import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/models.dart';
import '../core/scope.dart';
import '../widgets/banner.dart';
import '../widgets/carousel.dart';
import 'detail_screen.dart';
import 'player_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AppScope app;
  late Future<List<List<Item>>> _f;
  Item? _spotlight;

  @override
  void initState() {
    super.initState();
    app = AppScope.of(context);
    _f = _load();
  }

  Future<List<List<Item>>> _load({bool refresh = false}) async {
    final st = app.store;
    final vod = st.get('show_vod', true)
        ? await app.repo.items(Kind.vod, refresh: refresh)
        : <Item>[];
    final ser = st.get('show_series', true)
        ? await app.repo.items(Kind.series, refresh: refresh)
        : <Item>[];
    final live = st.get('show_live', true)
        ? await app.repo.items(Kind.live, refresh: refresh)
        : <Item>[];
    return [vod, ser, live];
  }

  List<Item> _recent(List<Item> l) =>
      ([...l]..sort((a, b) => b.added.compareTo(a.added))).take(25).toList();

  List<Item> _top(List<Item> l) => ([...l.where((i) => i.rating5 > 0)]
        ..sort((a, b) => b.rating5.compareTo(a.rating5)))
      .take(25)
      .toList();

  List<Item> _heroItems(List<Item> vod, List<Item> ser) {
    final all = [...vod, ...ser].where((i) => i.image.isNotEmpty).toList()
      ..sort((a, b) => b.added.compareTo(a.added));
    return all.take(12).toList();
  }

  @override
  Widget build(BuildContext context) {
    const neonGreen = Color(0xFF69F028);

    return FutureBuilder<List<List<Item>>>(
      future: _f,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: neonGreen),
          );
        }
        if (snap.hasError) {
          return ErrorView(
            message: '${snap.error}',
            onRetry: () => setState(() => _f = _load(refresh: true)),
          );
        }

        final vod = snap.data![0], ser = snap.data![1], live = snap.data![2];

        return RefreshIndicator(
          color: neonGreen,
          onRefresh: () async {
            setState(() => _f = _load(refresh: true));
            await _f;
          },
          child: ValueListenableBuilder(
            valueListenable: app.store.user.listenable(),
            builder: (_, __, ___) {
              final st = app.store;
              final cont = st.continueWatching();
              final byKey = {for (final e in cont) e.item.key: e};
              final favs = st.favorites();
              final favLive = favs.where((i) => i.kind == Kind.live).toList();
              final recentLive = st.recentLive();
              final featured = _heroItems(vod, ser);
              final activeItem = (_spotlight != null &&
                      featured.any((x) => x.key == _spotlight!.key))
                  ? _spotlight!
                  : (featured.isNotEmpty ? featured.first : null);

              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (activeItem != null)
                    _FullscreenShowcase(
                      active: activeItem,
                      items: featured,
                      accent: neonGreen,
                      onFocusItem: (item) {
                        if (_spotlight?.key != item.key) {
                          setState(() => _spotlight = item);
                        }
                      },
                      onTapItem: (item) => openItem(context, item),
                    )
                  else
                    const SizedBox(height: 80),
                  if (recentLive.isNotEmpty)
                    Rail(
                      title: 'Chaînes récentes',
                      items: recentLive,
                      onTap: (i) => openItem(context, i, channels: recentLive),
                    ),
                  if (cont.isNotEmpty)
                    Rail(
                      title: 'Reprendre la lecture',
                      items: [for (final e in cont) e.item],
                      progress: (i) => byKey[i.key]!.progress,
                      onTap: (i) {
                        final e = byKey[i.key]!;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PlayerScreen.vod(
                              url: e.url,
                              title: e.title,
                              item: e.item,
                            ),
                          ),
                        );
                      },
                    ),
                  if (favs.isNotEmpty)
                    Rail(
                      title: 'Mes favoris',
                      items: favs,
                      onTap: (i) => openItem(context, i, channels: favLive),
                    ),
                  if (!app.api.hasVod && live.isNotEmpty)
                    Rail(
                      title: 'Toutes les chaînes',
                      items: live.take(40).toList(),
                      onTap: (i) => openItem(context, i, channels: live),
                    ),
                  if (vod.isNotEmpty)
                    Rail(
                      title: 'Films récents',
                      items: _recent(vod),
                      onTap: (i) => openItem(context, i),
                    ),
                  if (ser.isNotEmpty)
                    Rail(
                      title: 'Séries récentes',
                      items: _recent(ser),
                      onTap: (i) => openItem(context, i),
                    ),
                  if (_top(vod).isNotEmpty)
                    Rail(
                      title: 'Films les mieux notés',
                      items: _top(vod),
                      onTap: (i) => openItem(context, i),
                    ),
                  if (_top(ser).isNotEmpty)
                    Rail(
                      title: 'Séries les mieux notées',
                      items: _top(ser),
                      onTap: (i) => openItem(context, i),
                    ),
                  const SizedBox(height: 32),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _FullscreenShowcase extends StatelessWidget {
  final Item active;
  final List<Item> items;
  final Color accent;
  final ValueChanged<Item> onFocusItem;
  final ValueChanged<Item> onTapItem;

  const _FullscreenShowcase({
    required this.active,
    required this.items,
    required this.accent,
    required this.onFocusItem,
    required this.onTapItem,
  });

  String _backdropOf(Item item) {
    final bg = item.raw['backdrop_path'];
    if (bg is List && bg.isNotEmpty && bg.first.toString().isNotEmpty) {
      return bg.first.toString();
    }
    if (bg is String && bg.isNotEmpty) return bg;
    return item.image;
  }

  String _plotOf(Item item) {
    final p = item.raw['plot'] ?? item.raw['description'] ?? '';
    return p.toString().trim();
  }

  String _yearOf(Item item) {
    final r = item.raw['releaseDate'] ??
        item.raw['releasedate'] ??
        item.raw['year'] ??
        '';
    final s = r.toString().trim();
    return s.length >= 4 ? s.substring(0, 4) : '';
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;
    final stageHeight = (h * 0.88).clamp(430.0, 740.0);
    final bgUrl = _backdropOf(active);
    final plot = _plotOf(active);
    final year = _yearOf(active);
    final kindLabel = active.kind == Kind.series ? 'Série' : 'Film';

    return SizedBox(
      height: stageHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            child: Image.network(
              bgUrl,
              key: ValueKey(bgUrl),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFF121722)),
            ),
          ),
          // Dégradé latéral gauche pour la lisibilité du texte
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: const [0.0, 0.45, 0.85, 1.0],
                colors: [
                  const Color(0xFF0A0D12).withOpacity(0.95),
                  const Color(0xFF0A0D12).withOpacity(0.72),
                  const Color(0xFF0A0D12).withOpacity(0.18),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Dégradé inférieur vers le fond sombre
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.55, 0.85, 1.0],
                colors: [
                  Colors.black.withOpacity(0.35),
                  Colors.transparent,
                  const Color(0xFF0A0D12).withOpacity(0.85),
                  const Color(0xFF0A0D12),
                ],
              ),
            ),
          ),
          // Bloc d'informations du film/série à gauche
          Positioned(
            left: w >= 720 ? 44 : 20,
            bottom: 185,
            right: w >= 720 ? w * 0.42 : 20,
            child: Column(
            
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: accent, width: 1),
                      ),
                      child: Text(
                        kindLabel.toUpperCase(),
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    if (year.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Text(
                        year,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (active.rating5 > 0) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.star_rounded, color: accent, size: 17),
                      const SizedBox(width: 3),
                      Text(
                        active.rating5.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  active.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: w >= 720 ? 34 : 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.12,
                    shadows: const [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 12,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                ),
                if (plot.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    plot,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Pro Max TV Originals',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            height: 145,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: w >= 720 ? 44 : 20),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, idx) {
                final item = items[idx];
                return _LandscapePosterCard(
                  item: item,
                  imageUrl: _backdropOf(item),
                  isActive: item.key == active.key,
                  accent: accent,
                  onFocus: () => onFocusItem(item),
                  onTap: () => onTapItem(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LandscapePosterCard extends StatefulWidget {
  final Item item;
  final String imageUrl;
  final bool isActive;
  final Color accent;
  final VoidCallback onFocus;
  final VoidCallback onTap;

  const _LandscapePosterCard({
    required this.item,
    required this.imageUrl,
    required this.isActive,
    required this.accent,
    required this.onFocus,
    required this.onTap,
  });

  @override
  State<_LandscapePosterCard> createState() => _LandscapePosterCardState();
}

class _LandscapePosterCardState extends State<_LandscapePosterCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = _focused || widget.isActive;

    return InkWell(
      onTap: widget.onTap,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) widget.onFocus();
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedScale(
        scale: _focused ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 170),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          width: 230,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlighted ? widget.accent : Colors.white12,
              width: _focused ? 3.0 : (widget.isActive ? 2.0 : 1.0),
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: widget.accent.withOpacity(0.45),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  widget.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFF1A202C),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      widget.item.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.45, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.85),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: widget.accent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      size: 14,
                      color: Colors.black,
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 8,
                  child: Text(
                    widget.item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      shadows: [
                        Shadow(color: Colors.black, blurRadius: 6),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
