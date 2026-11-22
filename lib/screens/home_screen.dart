import 'package:flutter/material.dart';
import '../data/catalog_repository.dart';
import '../services/xtream_service.dart';
import '../widgets/carousel.dart';
import 'player_screen.dart';
import 'series_screen.dart';

class HomeScreen extends StatelessWidget {
  final XtreamService api;
  final CatalogRepository repo;
  final VoidCallback onLogout;
  const HomeScreen(
      {super.key, required this.api, required this.repo, required this.onLogout});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('PRO MAX TV',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            actions: [
              IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Déconnexion',
                  onPressed: onLogout),
            ],
            bottom: const TabBar(tabs: [
              Tab(text: 'Live'),
              Tab(text: 'Films'),
              Tab(text: 'Séries'),
            ]),
          ),
          body: TabBarView(children: [
            for (final k in Kind.values) CatalogTab(kind: k, api: api, repo: repo),
          ]),
        ),
      );
}

class CatalogTab extends StatefulWidget {
  final Kind kind;
  final XtreamService api;
  final CatalogRepository repo;
  const CatalogTab(
      {super.key, required this.kind, required this.api, required this.repo});

  @override
  State<CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<CatalogTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<List<dynamic>>> _future = _load();

  @override
  bool get wantKeepAlive => true;

  Future<List<List<dynamic>>> _load({bool refresh = false}) => Future.wait([
        widget.repo.categories(widget.kind, refresh: refresh),
        widget.repo.items(widget.kind, refresh: refresh),
      ]);

  void _open(dynamic it) {
    final api = widget.api;
    final name = '${it['name'] ?? ''}';
    switch (widget.kind) {
      case Kind.live:
        final id = int.tryParse('${it['stream_id']}') ?? 0;
        _play(api.liveUrl(id), name);
      case Kind.vod:
        final id = int.tryParse('${it['stream_id']}') ?? 0;
        _play(api.vodUrl(id, '${it['container_extension'] ?? 'mp4'}'), name);
      case Kind.series:
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => SeriesScreen(api: api, series: it)));
    }
  }

  void _play(String url, String title) => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PlayerScreen(streamUrl: url, title: title)),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<List<dynamic>>>(
      future: _future,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${snap.error}'),
              TextButton(
                  onPressed: () => setState(() => _future = _load(refresh: true)),
                  child: const Text('Réessayer')),
            ]),
          );
        }
        final cats = snap.data![0];
        final byCat = <String, List>{};
        for (final it in snap.data![1]) {
          byCat.putIfAbsent('${it['category_id']}', () => []).add(it);
        }
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _future = _load(refresh: true));
            await _future;
          },
          child: ListView(children: [
            for (final c in cats)
              if (byCat['${c['category_id']}'] != null)
                Carousel(
                  title: '${c['category_name']}',
                  items: byCat['${c['category_id']}']!.take(30).toList(),
                  onTap: _open,
                ),
          ]),
        );
      },
    );
  }
}
