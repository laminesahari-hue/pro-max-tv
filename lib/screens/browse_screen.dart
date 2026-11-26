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

  static const _sortLabels = ['Par défaut', 'Récents', 'A → Z', 'Mieux notés'];

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
    _ck = null;
    _cl = null;
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
        break;
      case 2:
        c.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 3:
        c.sort((a, b) => b.rating5.compareTo(a.rating5));
        break;
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
    final nextProgs = _focusedEpg.length > 1
        ? _focusedEpg.skip(1).toList()
        : const <Programme>[];

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
                child: Text(
                  ch.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
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
