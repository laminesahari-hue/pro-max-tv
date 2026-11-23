import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/models.dart';
import '../core/scope.dart';
import '../widgets/banner.dart';
import '../widgets/carousel.dart';
import 'detail_screen.dart';
import 'player_screen.dart';
import 'search_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AppScope app;
  late Future<List<List<Item>>> _f;

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
      ([...l]..sort((a, b) => b.added.compareTo(a.added))).take(30).toList();

  List<Item> _top(List<Item> l) => ([...l.where((i) => i.rating5 > 0)]
        ..sort((a, b) => b.rating5.compareTo(a.rating5)))
      .take(30)
      .toList();

  List<Item> _hero(List<Item> all) {
    final c = all.where((i) => i.image.isNotEmpty).toList()
      ..sort((a, b) => b.added.compareTo(a.added));
    final top = c.take(60).toList()..sort((a, b) => b.rating5.compareTo(a.rating5));
    return top.take(6).toList();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<List<Item>>>(
        future: _f,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ErrorView(
                message: '${snap.error}',
                onRetry: () => setState(() => _f = _load(refresh: true)));
          }
          final vod = snap.data![0], ser = snap.data![1], live = snap.data![2];
          return RefreshIndicator(
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
                final hero = st.get('show_hero', true)
                    ? _hero([...vod, ...ser])
                    : <Item>[];
                return ListView(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
                    child: Row(children: [
                      Text('PRO MAX TV',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: Theme.of(context).colorScheme.primary)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.search),
                        tooltip: 'Rechercher',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('Recherche')),
                              body: const SearchPage(),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  if (hero.isNotEmpty)
                    FeaturedBanner(items: hero, onTap: (i) => openItem(context, i)),
                  Rail(
                    title: 'Chaînes récentes',
                    items: recentLive,
                    onTap: (i) => openItem(context, i, channels: recentLive),
                  ),
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
                                  url: e.url, title: e.title, item: e.item)));
                    },
                  ),
                  Rail(
                    title: 'Mes favoris',
                    items: favs,
                    onTap: (i) => openItem(context, i, channels: favLive),
                  ),
                  if (!app.api.hasVod)
                    Rail(
                      title: 'Toutes les chaînes',
                      items: live.take(40).toList(),
                      onTap: (i) => openItem(context, i, channels: live),
                    ),
                  Rail(
                      title: 'Films récents',
                      items: _recent(vod),
                      onTap: (i) => openItem(context, i)),
                  Rail(
                      title: 'Séries récentes',
                      items: _recent(ser),
                      onTap: (i) => openItem(context, i)),
                  Rail(
                      title: 'Films les mieux notés',
                      items: _top(vod),
                      onTap: (i) => openItem(context, i)),
                  Rail(
                      title: 'Séries les mieux notées',
                      items: _top(ser),
                      onTap: (i) => openItem(context, i)),
                  const SizedBox(height: 24),
                ]);
              },
            ),
          );
        },
      );
}
