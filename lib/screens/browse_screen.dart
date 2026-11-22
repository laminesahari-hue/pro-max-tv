import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/models.dart';
import '../core/scope.dart';
import '../data/catalog_repository.dart';
import '../widgets/carousel.dart';
import 'detail_screen.dart';

class _Data {
  final List<Cat> cats;
  final List<Item> items;
  final Map<String, List<Item>> by;
  _Data(this.cats, this.items, this.by);
}

class BrowsePage extends StatefulWidget {
  final Kind kind;
  const BrowsePage({super.key, required this.kind});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  late final AppScope app;
  late Future<_Data> _f;
  String _cat = 'all';
  int _sort = 0;
  String? _ck;
  List<Item>? _cl;

  static const _titles = {
    Kind.live: 'Live TV',
    Kind.vod: 'Films',
    Kind.series: 'Séries',
  };

  @override
  void initState() {
    super.initState();
    app = AppScope.of(context);
    _f = _load();
  }

  Future<_Data> _load({bool refresh = false}) async {
    final cats = await app.repo.categories(widget.kind, refresh: refresh);
    final items = await app.repo.items(widget.kind, refresh: refresh);
    final by = <String, List<Item>>{};
    for (final i in items) {
      by.putIfAbsent(i.cat, () => []).add(i);
    }
    return _Data(cats.where((c) => by.containsKey(c.id)).toList(), items, by);
  }

  List<Item> _list(_Data d) {
    final key = '$_cat|$_sort';
    if (_cat != 'fav' && key == _ck && _cl != null) return _cl!;
    final base = _cat == 'all'
        ? d.items
        : _cat == 'fav'
            ? app.store.favorites(kind: widget.kind)
            : (d.by[_cat] ?? <Item>[]);
    final c = [...base];
    switch (_sort) {
      case 1:
        c.sort((a, b) => b.added.compareTo(a.added));
      case 2:
        c.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case 3:
        c.sort((a, b) => b.rating5.compareTo(a.rating5));
    }
    _ck = key;
    _cl = c;
    return c;
  }

  Widget _logo(Item it) => SizedBox(
        width: 52,
        height: 52,
        child: it.image.isEmpty
            ? const Icon(Icons.tv)
            : CachedNetworkImage(
                imageUrl: it.image,
                fit: BoxFit.contain,
                memCacheWidth: 120,
                errorWidget: (_, __, ___) => const Icon(Icons.tv),
              ),
      );

  Widget _content(List<Item> list) {
    if (list.isEmpty) {
      return const Center(child: Text('Aucun contenu'));
    }
    if (widget.kind == Kind.live) {
      return ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) {
          final it = list[i];
          final fav = app.store.isFav(it);
          return ListTile(
            leading: _logo(it),
            title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: Icon(fav ? Icons.favorite : Icons.favorite_border,
                  color: fav ? Colors.redAccent : null),
              onPressed: () => app.store.toggleFav(it),
            ),
            onTap: () => openItem(context, it, channels: list),
            onLongPress: () => app.store.toggleFav(it),
          );
        },
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) =>
          PosterCard(item: list[i], onTap: () => openItem(context, list[i])),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_Data>(
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
          final d = snap.data!;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(children: [
                Text(_titles[widget.kind]!,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                PopupMenuButton<int>(
                  icon: const Icon(Icons.sort),
                  tooltip: 'Trier',
                  onSelected: (v) => setState(() => _sort = v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 0, child: Text('Ordre du serveur')),
                    PopupMenuItem(value: 1, child: Text('Plus récents')),
                    PopupMenuItem(value: 2, child: Text('A → Z')),
                    PopupMenuItem(value: 3, child: Text('Mieux notés')),
                  ],
                ),
              ]),
            ),
            SizedBox(
              height: 52,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: d.cats.length + 2,
                itemBuilder: (_, i) {
                  final id = i == 0 ? 'all' : i == 1 ? 'fav' : d.cats[i - 2].id;
                  final label =
                      i == 0 ? 'Tous' : i == 1 ? '★ Favoris' : d.cats[i - 2].name;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _cat == id,
                      onSelected: (_) => setState(() => _cat = id),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  setState(() => _f = _load(refresh: true));
                  await _f;
                },
                child: ValueListenableBuilder(
                  valueListenable: app.store.user.listenable(),
                  builder: (_, __, ___) => _content(_list(d)),
                ),
              ),
            ),
          ]);
        },
      );
}
