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

  // Mode Live TV : true = Classique (3 colonnes style décodeur avec EPG), false = Normal
  bool _classicDecoderMode = true;
  Item? _focusedChannel;
  List<Programme> _focusedEpg = const <Programme>[];
  final Map<String, List<Programme>> _epgCache = <String, List<Programme>>{};

  static const _titles = {
    Kind.live: 'Live TV',
    Kind.vod: 'Films',
    Kind.series: 'Séries',
  };

  
    bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      app = AppScope.of(context);
      _classicDecoderMode = app.store.get<bool>('live_classic_mode', true);
      _f = _load();
    }
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

    void _selectChannelForEpg(Item ch) {
    if (_focusedChannel?.id == ch.id) return;
    setState(() {
      _focusedChannel = ch;
      _focusedEpg = _epgCache[ch.id.toString()] ?? const <Programme>[];
    });
    if (_epgCache.containsKey(ch.id.toString())) return;
    app.epg.forChannel(ch, limit: 5).then((list) {
      _epgCache[ch.id.toString()] = list;
      if (mounted && _focusedChannel?.id == ch.id) {
        setState(() => _focusedEpg = list);
      }
    }).catchError((_) {});
  }


  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _logo(Item it, {double size = 44}) => SizedBox(
        width: size,
        height: size,
        child: it.image.isEmpty
            ? Icon(Icons.tv_rounded, size: size * 0.65, color: Colors.white54)
            : CachedNetworkImage(
                imageUrl: it.image,
                fit: BoxFit.contain,
                memCacheWidth: 120,
                errorWidget: (_, __, ___) => Icon(Icons.tv_rounded,
                    size: size * 0.65, color: Colors.white54),
              ),
      );

  // --- COLONNE GAUCHE : DOSSIERS / CATÉGORIES ---
  Widget _buildLeftCategories(_Data d, Color accent, {bool compact = false}) {
    final favCount = app.store.favorites(kind: widget.kind).length;
    return Container(
      width: compact ? 185 : 230,
      decoration: BoxDecoration(
        color: const Color(0xFF10131C),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              'DOSSIERS',
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: d.cats.length + 2,
              itemBuilder: (_, i) {
                final id = i == 0 ? 'all' : i == 1 ? 'fav' : d.cats[i - 2].id;
                final label = i == 0
                    ? 'Toutes les chaînes'
                    : i == 1
                        ? '★ Favoris'
                        : d.cats[i - 2].name;
                final count = i == 0
                    ? d.items.length
                    : i == 1
                        ? favCount
                        : (d.by[id]?.length ?? 0);
                final selected = _cat == id;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    onTap: () => setState(() => _cat = id),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? accent.withValues(alpha: 0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? accent.withValues(alpha: 0.7)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected ? Colors.white : Colors.white70,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$count',
                            style: TextStyle(
                              color: selected ? accent : Colors.white38,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- COLONNE DROITE (MODE CLASSIQUE DÉCODEUR) : FICHE EPG DE LA CHAÎNE ---
  Widget _buildDecoderEpgPanel(List<Item> list, Color accent) {
    final ch = _focusedChannel ?? (list.isNotEmpty ? list.first : null);
    if (ch == null) return const SizedBox.shrink();
    final nowProg = _focusedEpg.isNotEmpty ? _focusedEpg.first : null;
    final nextProgs =
        _focusedEpg.length > 1 ? _focusedEpg.skip(1).toList() : const <Programme>[];

    double progress = 0.0;
    if (nowProg != null) {
      final total = nowProg.end.difference(nowProg.start).inSeconds;
      final elapsed = DateTime.now().difference(nowProg.start).inSeconds;
      if (total > 0) progress = (elapsed / total).clamp(0.0, 1.0);
    }

    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10131C),
        border: Border(
          left: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _logo(ch, size: 52),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ch.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                                          ],
                    ),
                  ),
                ],
              ),

                              const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.black,
              ),
              onPressed: () => openItem(context, ch, channels: list),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Regarder en direct',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const Divider(height: 28, color: Colors.white12),
          Text(
            'EN CE MOMENT',
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          if (nowProg == null)
            const Text(
              'Aucune information EPG disponible pour cette chaîne.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            )
          else ...[
            Text(
              nowProg.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_hm(nowProg.start)} - ${_hm(nowProg.end)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ],
          if (nextProgs.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'À SUIVRE',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: nextProgs.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                itemBuilder: (_, idx) {
                  final p = nextProgs[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_hm(p.start)} - ${_hm(p.end)}',
                          style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveChannelList(List<Item> list, Color accent,
      {required bool classic}) {
    if (list.isEmpty) {
      return const Center(child: Text('Aucune chaîne dans ce dossier'));
    }
    if (_focusedChannel == null || !list.any((x) => x.id == _focusedChannel!.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _selectChannelForEpg(list.first);
      });
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final it = list[i];
        final fav = app.store.isFav(it);
        final isSelected = _focusedChannel?.id == it.id;
                final cachedProgs = _epgCache[it.id.toString()];

        final curProg =
            (cachedProgs != null && cachedProgs.isNotEmpty) ? cachedProgs.first : null;

                return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: InkWell(
            autofocus: i == 0,
            onTap: () => openItem(context, it, channels: list),
            onLongPress: () => app.store.toggleFav(it),
            onFocusChange: (hasFocus) {
              if (hasFocus) _selectChannelForEpg(it);
            },
            onHover: (hovering) {
              if (hovering) _selectChannelForEpg(it);
            },
            borderRadius: BorderRadius.circular(10),
            child: Builder(
              builder: (ctx) {
                final hasFocus = Focus.of(ctx).hasFocus;
                final highlight = hasFocus || isSelected;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  padding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: classic ? 8 : 11),
                  decoration: BoxDecoration(
                    color: hasFocus
                        ? accent.withValues(alpha: 0.30)
                        : (isSelected
                            ? accent.withValues(alpha: 0.14)
                            : const Color(0xFF141824)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: hasFocus
                          ? accent
                          : (isSelected
                              ? accent.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.05)),
                      width: hasFocus ? 2.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: highlight ? accent : Colors.white54,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      _logo(it, size: classic ? 38 : 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: classic ? 14 : 15,
                              ),
                            ),
                            if (curProg != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${_hm(curProg.start)} · ${curProg.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: accent, fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                      ExcludeFocus(
                        child: IconButton(
                          icon: Icon(
                            fav ? Icons.favorite : Icons.favorite_border,
                            color: fav ? Colors.redAccent : Colors.white38,
                            size: 20,
                          ),
                          onPressed: () => app.store.toggleFav(it),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );

      },
    );
  }

  Widget _vodGrid(List<Item> list) {
    if (list.isEmpty) {
      return const Center(child: Text('Aucun contenu'));
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
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final isWide = MediaQuery.of(context).size.width >= 780;

    return FutureBuilder<_Data>(
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

        if (widget.kind == Kind.live) {
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E1118),
                  border: Border(
                    bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'Live TV',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                                        SegmentedButton<bool>(
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        textStyle: WidgetStateProperty.all(
                            const TextStyle(fontSize: 12)),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.view_column_rounded, size: 16),
                          label: Text('Classique EPG'),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.view_list_rounded, size: 16),
                          label: Text('Normal'),
                        ),
                      ],
                      selected: {_classicDecoderMode},
                      onSelectionChanged: (s) {
                        setState(() => _classicDecoderMode = s.first);
                        app.store.set('live_classic_mode', s.first);
                      },
                    ),
                            if (widget.kind == Kind.live) {
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E1118),
                  border: Border(
                    bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'Live TV',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SegmentedButton<bool>(
                                style: ButtonStyle(
                                  visualDensity: VisualDensity.compact,
                                  textStyle: WidgetStateProperty.all(
                                      const TextStyle(fontSize: 12)),
                                ),
                                segments: const [
                                  ButtonSegment(
                                    value: true,
                                    icon: Icon(Icons.view_column_rounded,
                                        size: 16),
                                    label: Text('Classique EPG'),
                                  ),
                                  ButtonSegment(
                                    value: false,
                                    icon: Icon(Icons.view_list_rounded,
                                        size: 16),
                                    label: Text('Normal'),
                                  ),
                                ],
                                selected: {_classicDecoderMode},
                                onSelectionChanged: (s) {
                                  setState(
                                      () => _classicDecoderMode = s.first);
                                  app.store.set('live_classic_mode', s.first);
                                },
                              ),
                              const SizedBox(width: 8),
                              PopupMenuButton<int>(
                                icon: const Icon(Icons.sort, size: 20),
                                tooltip: 'Trier',
                                onSelected: (v) => setState(() => _sort = v),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 0,
                                      child: Text('Ordre du serveur')),
                                  PopupMenuItem(
                                      value: 1, child: Text('Plus récents')),
                                  PopupMenuItem(value: 2, child: Text('A → Z')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: app.store.user.listenable(),
                  builder: (_, __, ___) {
                    final list = _list(d);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildLeftCategories(d, accent, compact: !isWide),
                        Expanded(
                          child: _buildLiveChannelList(
                            list,
                            accent,
                            classic: _classicDecoderMode,
                          ),
                        ),
                        if (_classicDecoderMode && isWide)
                          SizedBox(
                            width: 280,
                            child: _buildDecoderEpgPanel(list, accent),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        }


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
                builder: (_, __, ___) => _vodGrid(_list(d)),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
