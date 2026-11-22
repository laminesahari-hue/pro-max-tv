import 'dart:convert';
import 'package:hive/hive.dart';
import '../services/xtream_service.dart';

enum Kind { live, vod, series }

class CatalogRepository {
  final XtreamService api;
  final Box box;
  CatalogRepository(this.api, this.box);

  Future<List<dynamic>> categories(Kind k, {bool refresh = false}) =>
      _cached('${k.name}_cat', refresh, () {
        switch (k) {
          case Kind.live:
            return api.getLiveCategories();
          case Kind.vod:
            return api.getVodCategories();
          case Kind.series:
            return api.getSeriesCategories();
        }
      });

  Future<List<dynamic>> items(Kind k, {bool refresh = false}) =>
      _cached('${k.name}_items', refresh, () {
        switch (k) {
          case Kind.live:
            return api.getLiveStreams();
          case Kind.vod:
            return api.getVodStreams();
          case Kind.series:
            return api.getSeries();
        }
      });

  Future<List<dynamic>> _cached(String key, bool refresh,
      Future<List<dynamic>> Function() fetch) async {
    final raw = box.get(key) as String?;
    final ts = box.get('${key}_ts') as int?;
    final now = DateTime.now().millisecondsSinceEpoch;
    final fresh = ts != null && now - ts < 6 * 3600 * 1000;

    if (raw != null && fresh && !refresh) return json.decode(raw);
    try {
      final data = await fetch();
      await box.put(key, json.encode(data));
      await box.put('${key}_ts', now);
      return data;
    } catch (_) {
      if (raw != null) return json.decode(raw); // repli hors-ligne
      rethrow;
    }
  }
}
