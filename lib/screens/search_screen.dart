import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/scope.dart';
import '../widgets/carousel.dart';
import '../widgets/tv_field.dart';
import 'detail_screen.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final AppScope app;
  late final Future<Map<Kind, List<Item>>> _f;
  String _q = '';

  @override
  void initState() {
    super.initState();
    app = AppScope.of(context);
    _f = _load();
  }

  Future<Map<Kind, List<Item>>> _load() async {
    final st = app.store;
    return {
      if (st.get('show_live', true)) Kind.live: await app.repo.items(Kind.live),
      if (st.get('show_vod', true)) Kind.vod: await app.repo.items(Kind.vod),
      if (st.get('show_series', true)) Kind.series: await app.repo.items(Kind.series),
    };
  }

  static const _titles = {
    Kind.live: 'Chaînes',
    Kind.vod: 'Films',
    Kind.series: 'Séries',
  };

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TvField(
            label: 'Rechercher',
            hint: 'Film, série, chaîne…',
            value: _q,
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: FutureBuilder<Map<Kind, List<Item>>>(
            future: _f,
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) return Center(child: Text('${snap.error}'));
              final q = _q.trim().toLowerCase();
              if (q.length < 2) {
                return const Center(child: Text('Tape au moins 2 lettres'));
              }
              final rails = <Widget>[];
              var total = 0;
              for (final e in snap.data!.entries) {
                final m = e.value
                    .where((i) => i.name.toLowerCase().contains(q))
                    .take(40)
                    .toList();
                total += m.length;
                rails.add(Rail(
                  title: '${_titles[e.key]} (${m.length})',
                  items: m,
                  onTap: (i) => openItem(context, i, channels: m),
                ));
              }
              if (total == 0) return const Center(child: Text('Aucun résultat'));
              return ListView(children: rails);
            },
          ),
        ),
      ]);
}
