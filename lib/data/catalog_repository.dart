import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../services/source.dart';

dynamic _decode(String s) => json.decode(s);
String _encode(dynamic d) => json.encode(d);

class Cat {
  final String id, name;
  const Cat(this.id, this.name);
}

class CatalogRepository {
  final Source api;
  final Store store;
  final String pid;
  CatalogRepository(this.api, this.store, this.pid);

  final _mem = <String, List<dynamic>>{};
  final _itemMem = <String, List<Item>>{};
  final _session = <String>{};

  static final _adult =
      RegExp(r'adult|xxx|porn|18\+|\+18|erotic|for adults', caseSensitive: false);

  void clearMemory() {
    _mem.clear();
    _itemMem.clear();
    _session.clear();
  }

  Future<List<Cat>> categories(Kind k, {bool refresh = false}) async {
    if (k == Kind.vod && !api.hasVod) return [];
    if (k == Kind.series && !api.hasSeries) return [];
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
    if (k == Kind.vod && !api.hasVod) return [];
    if (k == Kind.series && !api.hasSeries) return [];
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
    final ck = '${pid}_$key';
    if (!refresh && _mem.containsKey(ck)) return _mem[ck]!;
    final raw = store.catalog.get(ck) as String?;
    final ts = store.catalog.get('${ck}_ts') as int?;
    final now = DateTime.now().millisecondsSinceEpoch;
    final mode = store.get<String>('update_mode', 'daily');
    final stale = ts == null ||
        (mode == 'start' && !_session.contains(ck)) ||
        (mode == 'daily' && now - ts > 24 * 3600 * 1000);

    if (raw != null && !stale && !refresh) {
      final d = await compute(_decode, raw) as List<dynamic>;
      _session.add(ck);
      return _mem[ck] = d;
    }
    try {
      final data = await fetch();
      _mem[ck] = data;
      _session.add(ck);
      await store.catalog.put(ck, await compute(_encode, data));
      await store.catalog.put('${ck}_ts', now);
      return data;
    } catch (_) {
      if (raw != null) {
        final d = await compute(_decode, raw) as List<dynamic>;
        return _mem[ck] = d; // repli hors-ligne
      }
      rethrow;
    }
  }
}
