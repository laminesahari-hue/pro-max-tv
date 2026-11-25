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
