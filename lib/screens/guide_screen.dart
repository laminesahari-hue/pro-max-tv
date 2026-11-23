import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/scope.dart';
import '../data/catalog_repository.dart';
import '../widgets/carousel.dart';
import 'detail_screen.dart';

class _G {
  final List<Cat> cats;
  final List<Item> items;
  final Map<String, List<Item>> by;
  _G(this.cats, this.items, this.by);
}

class GuidePage extends StatefulWidget {
  const GuidePage({super.key});

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  late final AppScope app;
  late Future<_G> _f;
  String _cat = 'all';

  @override
  void initState() {
    super.initState();
    app = AppScope.of(context);
    _f = _load();
  }

  Future<_G> _load() async {
    final cats = await app.repo.categories(Kind.live);
    final items = await app.repo.items(Kind.live);
    final by = <String, List<Item>>{};
    for (final i in items) {
      by.putIfAbsent(i.cat, () => []).add(i);
    }
    return _G(cats.where((c) => by.containsKey(c.id)).toList(), items, by);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_G>(
        future: _f,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ErrorView(
                message: '${snap.error}',
                onRetry: () => setState(() => _f = _load()));
          }
          final d = snap.data!;
          final list = _cat == 'all'
              ? d.items
              : _cat == 'fav'
                  ? app.store.favorites(kind: Kind.live)
                  : (d.by[_cat] ?? <Item>[]);
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                Text('Guide TV',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                const Text('Maintenant et à suivre',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                      i == 0 ? 'Toutes' : i == 1 ? '★ Favoris' : d.cats[i - 2].name;
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
              child: list.isEmpty
                  ? const Center(child: Text('Aucune chaîne'))
                  : ListView.builder(
                      itemExtent: 76,
                      itemCount: list.length,
                      itemBuilder: (_, i) => _GuideRow(
                        key: ValueKey(list[i].key),
                        app: app,
                        ch: list[i],
                        onTap: () => openItem(context, list[i], channels: list),
                      ),
                    ),
            ),
          ]);
        },
      );
}

class _GuideRow extends StatefulWidget {
  final AppScope app;
  final Item ch;
  final VoidCallback onTap;
  const _GuideRow({super.key, required this.app, required this.ch, required this.onTap});

  @override
  State<_GuideRow> createState() => _GuideRowState();
}

class _GuideRowState extends State<_GuideRow> {
  late final Future<List<Programme>> _f =
      widget.app.epg.forChannel(widget.ch, limit: 8);

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _chip(Programme p) {
    final w = (p.end.difference(p.start).inMinutes * 3.2).clamp(110.0, 320.0).toDouble();
    final now = p.isNow;
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: w,
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: now
              ? Theme.of(context).colorScheme.primary.withOpacity(0.35)
              : Colors.white10,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${_hm(p.start)} – ${_hm(p.end)}',
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
            Text(p.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, fontWeight: now ? FontWeight.bold : FontWeight.normal)),
            if (now)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(value: p.progress, minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.ch;
    return Row(children: [
      SizedBox(
        width: 150,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              SizedBox(
                width: 36,
                height: 36,
                child: ch.image.isEmpty
                    ? const Icon(Icons.tv, size: 20)
                    : CachedNetworkImage(
                        imageUrl: ch.image,
                        fit: BoxFit.contain,
                        memCacheWidth: 100,
                        errorWidget: (_, __, ___) => const Icon(Icons.tv, size: 20)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(ch.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
              ),
            ]),
          ),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<Programme>>(
          future: _f,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) {
              return const Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final l = s.data ?? <Programme>[];
            if (l.isEmpty) {
              return const Align(
                alignment: Alignment.centerLeft,
                child: Text('Pas de programme',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              );
            }
            return ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: l.length,
              itemBuilder: (_, i) => _chip(l[i]),
            );
          },
        ),
      ),
    ]);
  }
}
