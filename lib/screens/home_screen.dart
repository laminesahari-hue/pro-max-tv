import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/models.dart';
import '../core/scope.dart';
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
  Timer? _focusDebounce;
  Timer? _autoTimer;
  List<Item> _lastFeatured = [];

  @override
  void initState() {
    super.initState();
    app = AppScope.of(context);
    _f = _load();
    _startAutoRotate();
  }

  void _startAutoRotate() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _lastFeatured.length < 2) return;
      final idx = _spotlight == null
          ? 0
          : _lastFeatured.indexWhere((x) => x.key == _spotlight!.key);
      final nextIdx = (idx + 1) % _lastFeatured.length;
      setState(() => _spotlight = _lastFeatured[nextIdx]);
    });
  }

  @override
  void dispose() {
    _focusDebounce?.cancel();
    _autoTimer?.cancel();
    super.dispose();
  }  Future<List<List<Item>>> _load({bool refresh = false}) async {
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

  List<Item> _fewRecent(List<Item> l, int count) =>
      ([...l]..sort((a, b) => b.added.compareTo(a.added))).take(count).toList();
  
  List<Item> _heroItems(List<Item> vod, List<Item> ser) {
    final topVod = _fewRecent(vod.where((i) => i.image.isNotEmpty).toList(), 5);
    final topSer = _fewRecent(ser.where((i) => i.image.isNotEmpty).toList(), 5);
    return [...topVod, ...topSer];
  }

  void _onSpotlightFocus(Item item) {
    if (_spotlight?.key == item.key) return;
    _focusDebounce?.cancel();
    _focusDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) {
        setState(() => _spotlight = item);
        _startAutoRotate();
      }
    });
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

        final fewMovies = _fewRecent(vod, 12);
        final fewSeries = _fewRecent(ser, 12);

        return ValueListenableBuilder(
          valueListenable: app.store.user.listenable(),
          builder: (_, __, ___) {
            final st = app.store;
            final cont = st.continueWatching().take(8).toList();
            final byKey = {for (final e in cont) e.item.key: e};
            final recentLive = st.recentLive().take(8).toList();
            final featured = _heroItems(vod, ser);
            _lastFeatured = featured;
            
            
            final activeItem = (_spotlight != null &&
                    featured.any((x) => x.key == _spotlight!.key))
                ? _spotlight!
                : (featured.isNotEmpty ? featured.first : null);

            return ListView(
              padding: EdgeInsets.zero,
              cacheExtent: 600,
              children: [
                if (activeItem != null)
                  _FullscreenShowcase(
                    active: activeItem,
                    items: featured,
                    accent: neonGreen,
                    onFocusItem: _onSpotlightFocus,
                    onTapItem: (item) => openItem(context, item),
                  )
                else
                  const SizedBox(height: 84),
                if (cont.isNotEmpty)
                  _LandscapeRail(
                    title: 'Reprendre la lecture',
                    items: [for (final e in cont) e.item],
                    accent: neonGreen,
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
                if (recentLive.isNotEmpty)
                  _LandscapeRail(
                    title: 'Chaînes récentes',
                    items: recentLive,
                    accent: neonGreen,
                    onTap: (i) => openItem(context, i, channels: recentLive),
                  ),
                if (!app.api.hasVod && live.isNotEmpty)
                  _LandscapeRail(
                    title: 'Chaînes en direct',
                    items: live.take(12).toList(),
                    accent: neonGreen,
                    onTap: (i) => openItem(context, i, channels: live),
                  ),
                if (fewMovies.isNotEmpty)
                  _LandscapeRail(
                    title: 'Quelques films',
                    items: fewMovies,
                    accent: neonGreen,
                    onTap: (i) => openItem(context, i),
                  ),
                if (fewSeries.isNotEmpty)
                  _LandscapeRail(
                    title: 'Quelques séries',
                    items: fewSeries,
                    accent: neonGreen,
                    onTap: (i) => openItem(context, i),
                  ),
                const SizedBox(height: 36),
              ],
            );
          },
        );
      },
    );
  }
}

String _itemBackdrop(Item item) {
  final bg = item.raw['backdrop_path'];
  if (bg is List && bg.isNotEmpty && bg.first.toString().isNotEmpty) {
    return bg.first.toString();
  }
  if (bg is String && bg.isNotEmpty) return bg;
  return item.image;
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
    // Vitrine plus haute pour bien laisser voir l'arrière-plan
    final stageHeight = (h * 0.94).clamp(460.0, 820.0);
    final bgUrl = _itemBackdrop(active);
    final plot = _plotOf(active);
    final year = _yearOf(active);
    final kindLabel = active.kind == Kind.series ? 'Série' : 'Film';

    // Calcul exact pour afficher 4 vignettes côte à côte dans la bannière
    final sidePad = w >= 720 ? 44.0 : 20.0;
    const gap = 16.0;
    final cardW = ((w - (sidePad * 2) - (gap * 3)) / 4).clamp(170.0, 320.0);

    return SizedBox(
      height: stageHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            bgUrl,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            cacheWidth: 1280,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                Container(color: const Color(0xFF121722)),
          ),
          // Dégradé gauche léger pour préserver la visibilité de l'image à droite et en haut
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: const [0.0, 0.38, 0.75, 1.0],
                colors: [
                  const Color(0xFF0A0D12).withOpacity(0.88),
                  const Color(0xFF0A0D12).withOpacity(0.45),
                  Colors.transparent,
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Dégradé bas descendu pour dégager la moitié haute de l'arrière-plan
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.62, 0.88, 1.0],
                colors: [
                  Colors.black.withOpacity(0.25),
                  Colors.transparent,
                  const Color(0xFF0A0D12).withOpacity(0.82),
                  const Color(0xFF0A0D12),
                ],
              ),
            ),
          ),
          // Infos descendues juste au-dessus des 4 vignettes
          Positioned(
            left: sidePad,
            bottom: 138,
            right: w >= 720 ? w * 0.44 : 20,
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
                const SizedBox(height: 8),
                Text(
                  active.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: w >= 720 ? 32 : 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.12,
                  ),
                ),
                if (plot.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    plot,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13.5,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Pro Max TV Originals',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          // 4 vignettes horizontales descendues tout en bas de la vitrine
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            height: 116,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: sidePad),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: gap),
              itemBuilder: (context, idx) {
                final item = items[idx];
                return _LandscapePosterCard(
                  item: item,
                  width: cardW,
                  imageUrl: _itemBackdrop(item),
                  isActive: item.key == active.key,
                  accent: accent,
                  showBadge: true,
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

// --- RANGÉE HORIZONTALE À 4 AFFICHES (POUR QUELQUES FILMS, QUELQUES SÉRIES, ETC.) ---
class _LandscapeRail extends StatelessWidget {
  final String title;
  final List<Item> items;
  final Color accent;
  final ValueChanged<Item> onTap;
  final double Function(Item)? progress;

  const _LandscapeRail({
    required this.title,
    required this.items,
    required this.accent,
    required this.onTap,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final sidePad = w >= 720 ? 44.0 : 20.0;
    const gap = 16.0;
    // Largeur calculée pour afficher exactement 4 cartes horizontales à l'écran
    final cardW = ((w - (sidePad * 2) - (gap * 3)) / 4).clamp(170.0, 340.0);
    final cardH = (cardW * 0.56).clamp(108.0, 185.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(sidePad, 18, sidePad, 10),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          height: cardH,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: sidePad),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: gap),
            itemBuilder: (_, i) {
              final item = items[i];
              return _LandscapePosterCard(
                item: item,
                width: cardW,
                imageUrl: _itemBackdrop(item),
                isActive: false,
                accent: accent,
                showBadge: false,
                progressValue: progress != null ? progress!(item) : null,
                onFocus: () {},
                onTap: () => onTap(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LandscapePosterCard extends StatefulWidget {
  final Item item;
  final double width;
  final String imageUrl;
  final bool isActive;
  final Color accent;
  final bool showBadge;
  final double? progressValue;
  final VoidCallback onFocus;
  final VoidCallback onTap;

  const _LandscapePosterCard({
    required this.item,
    required this.width,
    required this.imageUrl,
    required this.isActive,
    required this.accent,
    this.showBadge = false,
    this.progressValue,
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
        if (_focused != f) setState(() => _focused = f);
        if (f) widget.onFocus();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: highlighted ? widget.accent : Colors.white12,
            width: _focused ? 3.0 : (widget.isActive ? 2.0 : 1.0),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                widget.imageUrl,
                fit: BoxFit.cover,
                cacheWidth: 500,
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
                    stops: const [0.42, 1.0],
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.88),
                    ],
                  ),
                ),
              ),
              if (widget.showBadge)
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
                )
              else if (widget.item.rating5 > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, color: widget.accent, size: 13),
                        const SizedBox(width: 2),
                                                  Text(
                            widget.item.rating5.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: widget.progressValue != null ? 10 : 8,
                  child: Text(
                    widget.item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (widget.progressValue != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: widget.progressValue!.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(widget.accent),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
  }
}


