import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/models.dart';
import '../core/scope.dart';
import 'player_screen.dart';

void openItem(BuildContext context, Item it, {List<Item>? channels}) {
  if (it.kind == Kind.live) {
    final list = channels ?? [it];
    final idx = list.indexWhere((c) => c.id == it.id);
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                PlayerScreen.live(channels: list, index: idx < 0 ? 0 : idx)));
  } else {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => DetailPage(item: it)));
  }
}

String _s(dynamic v) => v == null ? '' : '$v';

class DetailPage extends StatefulWidget {
  final Item item;
  const DetailPage({super.key, required this.item});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late final AppScope app;
  late final Future<Map<String, dynamic>> _f;
  String? _season;

  Item get item => widget.item;
  bool get _series => item.kind == Kind.series;

  @override
  void initState() {
    super.initState();
    app = AppScope.of(context);
    _f = _series ? app.api.getSeriesInfo(item.id) : app.api.getVodInfo(item.id);
  }

  void _play(String url, String title) => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PlayerScreen.vod(url: url, title: title, item: item)),
      ).then((_) {
        if (mounted) setState(() {});
      });

  Widget _meta(String t, {Color? color}) =>
      Text(t, style: TextStyle(fontSize: 13, color: color ?? Colors.white70));

  @override
  Widget build(BuildContext context) => Scaffold(
        body: FutureBuilder<Map<String, dynamic>>(
          future: _f,
          builder: (ctx, snap) {
            final d = snap.data ?? <String, dynamic>{};
            final Map info = d['info'] is Map ? d['info'] as Map : {};
            final plot =
                _s(info['plot']).isNotEmpty ? _s(info['plot']) : _s(info['description']);
            var year = [info['releasedate'], info['releaseDate'], info['release_date'], info['year']]
                .map(_s)
                .firstWhere((x) => x.isNotEmpty, orElse: () => '');
            if (year.length >= 4) year = year.substring(0, 4);
            final duration = _s(info['duration']);
            final genre = _s(info['genre']);
            final cast = _s(info['cast']).isNotEmpty ? _s(info['cast']) : _s(info['actors']);
            final director = _s(info['director']);
            final bd = info['backdrop_path'];
            final back = bd is List && bd.isNotEmpty ? _s(bd.first) : (bd is String ? bd : '');
            final bgUrl = back.isNotEmpty ? back : item.image;

            // saisons / épisodes
            final raw = d['episodes'];
            final seasons = <String, List>{};
            if (raw is Map) {
              raw.forEach((k, v) {
                if (v is List) seasons['$k'] = v;
              });
            } else if (raw is List) {
              seasons['1'] = raw;
            }
            final keys = seasons.keys.toList()
              ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
            final sel = (_season != null && keys.contains(_season))
                ? _season!
                : (keys.isNotEmpty ? keys.first : '');
            final eps = seasons[sel] ?? [];

            final md = d['movie_data'];
            final ext = md is Map && _s(md['container_extension']).isNotEmpty
                ? _s(md['container_extension'])
                : item.ext;

            Widget bg = bgUrl.isEmpty
                ? const SizedBox()
                : CachedNetworkImage(
                    imageUrl: bgUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox());
            if (back.isEmpty && bgUrl.isNotEmpty) {
              bg = ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: bg);
            }

            return ListView(padding: EdgeInsets.zero, children: [
              SizedBox(
                height: 190,
                child: Stack(fit: StackFit.expand, children: [
                  bg,
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black45,
                          Theme.of(context).scaffoldBackgroundColor,
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 4,
                    child: SafeArea(
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 110,
                      height: 165,
                      child: item.image.isEmpty
                          ? const ColoredBox(color: Color(0xFF1A1D26))
                          : CachedNetworkImage(
                              imageUrl: item.image,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  const ColoredBox(color: Color(0xFF1A1D26))),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 12, children: [
                        if (year.isNotEmpty) _meta(year),
                        if (duration.isNotEmpty) _meta(duration),
                        if (item.rating5 > 0)
                          _meta('★ ${item.rating5.toStringAsFixed(1)}', color: Colors.amber),
                      ]),
                      if (genre.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _meta(genre),
                      ],
                    ]),
                  ),
                ]),
              ),
              if (snap.connectionState != ConnectionState.done)
                const Padding(
                    padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ValueListenableBuilder(
                  valueListenable: app.store.user.listenable(),
                  builder: (_, __, ___) {
                    final e = app.store.entryFor(item);
                    final resume = e != null && e.pos > 15000 && e.progress < 0.95;
                    final fav = app.store.isFav(item);
                    final canPlay = !_series || resume || eps.isNotEmpty;
                    return Wrap(spacing: 12, runSpacing: 8, children: [
                      FilledButton.icon(
                        autofocus: true,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(resume ? 'Reprendre' : 'Lecture'),
                        onPressed: !canPlay
                            ? null
                            : () {
                                if (resume) {
                                  _play(e.url, e.title);
                                } else if (_series) {
                                  final ep = eps.first;
                                  _play(
                                      app.api.episodeUrl(
                                          int.tryParse(_s(ep['id'])) ?? 0,
                                          _s(ep['container_extension']).isEmpty
                                              ? 'mp4'
                                              : _s(ep['container_extension'])),
                                      '${item.name} · S$sel E${_s(ep['episode_num'])}');
                                } else {
                                  _play(app.api.vodUrl(item.id, ext), item.name);
                                }
                              },
                      ),
                      OutlinedButton.icon(
                        icon: Icon(fav ? Icons.favorite : Icons.favorite_border),
                        label: Text(fav ? 'Dans mes favoris' : 'Ajouter aux favoris'),
                        onPressed: () => app.store.toggleFav(item),
                      ),
                    ]);
                  },
                ),
              ),
              if (plot.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(plot, style: const TextStyle(height: 1.4)),
                ),
              if (cast.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: _meta('Distribution : $cast'),
                ),
              if (director.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: _meta('Réalisateur : $director'),
                ),
              if (snap.hasError)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Infos indisponibles : ${snap.error}',
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              if (_series && keys.isNotEmpty) ...[
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final k in keys)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                          child: ChoiceChip(
                            label: Text('Saison $k'),
                            selected: k == sel,
                            onSelected: (_) => setState(() => _season = k),
                          ),
                        ),
                    ],
                  ),
                ),
                for (final ep in eps)
                  Builder(builder: (_) {
                    final Map ei = ep['info'] is Map ? ep['info'] as Map : {};
                    final thumb = _s(ei['movie_image']);
                    return ListTile(
                      leading: SizedBox(
                        width: 90,
                        height: 52,
                        child: thumb.isEmpty
                            ? const Icon(Icons.play_circle_outline)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: CachedNetworkImage(
                                  imageUrl: thumb,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 200,
                                  errorWidget: (_, __, ___) =>
                                      const Icon(Icons.play_circle_outline),
                                ),
                              ),
                      ),
                      title: Text('${_s(ep['episode_num'])}. ${_s(ep['title'])}',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: _s(ei['duration']).isEmpty ? null : Text(_s(ei['duration'])),
                      onTap: () => _play(
                        app.api.episodeUrl(
                            int.tryParse(_s(ep['id'])) ?? 0,
                            _s(ep['container_extension']).isEmpty
                                ? 'mp4'
                                : _s(ep['container_extension'])),
                        '${item.name} · S$sel E${_s(ep['episode_num'])}',
                      ),
                    );
                  }),
              ],
              const SizedBox(height: 32),
            ]);
          },
        ),
      );
}
