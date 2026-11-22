import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../services/xtream_service.dart';

dynamic _decode(String s) => json.decode(s);
String _encode(dynamic d) => json.encode(d);

class Cat {
  final String id, name;
  const Cat(this.id, this.name);
}

class CatalogRepository {
  final XtreamService api;
  final Store store;
  CatalogRepository(this.api, this.store);

  final _mem = <String, List<dynamic>>{};
  final _itemMem = <String, List<Item>>{};

  static final _adult =
      RegExp(r'adult|xxx|porn|18\+|\+18|erotic|for adults', caseSensitive: false);

  void clearMemory() {
    _mem.clear();
    _itemMem.clear();
  }

  Future<List<Cat>> categories(Kind k, {bool refresh = false}) async {
    final raw = await _cached('${k.name}_cat', refresh, () {
      switch (k) {
        case Kind.live:
          return api.getLiveCategories();
        case Kind.vod:
          return api.getVodCategories();
        case Kind.series:
          return api.getSeriesCategories();
      }
    });
    final hide = store.get('hide_adult', true);
    return [
      for (final c in raw)
        if (c is Map) Cat('${c['category_id']}', '${c['category_name']}')
    ].where((c) => !hide || !_adult.hasMatch(c.name)).toList();
  }

  Future<List<Item>> items(Kind k, {bool refresh = false}) async {
    final hide = store.get('hide_adult', true);
    final mk = '${k.name}$hide';
    if (!refresh && _itemMem.containsKey(mk)) return _itemMem[mk]!;
    final raw = await _cached('${k.name}_items', refresh, () {
      switch (k) {
        case Kind.live:
          return api.getLiveStreams();
        case Kind.vod:
          return api.getVodStreams();
        case Kind.series:
          return api.getSeries();
      }
    });
    var list = [
      for (final m in raw)
        if (m is Map) Item(k, m)
    ];
    if (hide) {
      final ok = (await categories(k)).map((c) => c.id).toSet();
      list = list.where((i) => i.cat.isEmpty || ok.contains(i.cat)).toList();
    }
    return _itemMem[mk] = list;
  }

  Future<List<dynamic>> _cached(String key, bool refresh,
      Future<List<dynamic>> Function() fetch) async {
    if (!refresh && _mem.containsKey(key)) return _mem[key]!;
    final raw = store.catalog.get(key) as String?;
    final ts = store.catalog.get('${key}_ts') as int?;
    final now = DateTime.now().millisecondsSinceEpoch;
    final ttl = store.get<int>('ttl_h', 6) * 3600 * 1000;
    final fresh = ts != null && now - ts < ttl;

    if (raw != null && fresh && !refresh) {
      final d = await compute(_decode, raw) as List<dynamic>;
      return _mem[key] = d;
    }
    try {
      final data = await fetch();
      _mem[key] = data;
      await store.catalog.put(key, await compute(_encode, data));
      await store.catalog.put('${key}_ts', now);
      return data;
    } catch (_) {
      if (raw != null) {
        final d = await compute(_decode, raw) as List<dynamic>;
        return _mem[key] = d; // repli hors-ligne
      }
      rethrow;
    }
  }
}
