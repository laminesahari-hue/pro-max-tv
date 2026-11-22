import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'models.dart';

class HistoryEntry {
  final Item item;
  final String url, title;
  final int pos, dur, ts;
  HistoryEntry(this.item, this.url, this.title, this.pos, this.dur, this.ts);

  double get progress => dur <= 0 ? 0 : (pos / dur).clamp(0.0, 1.0).toDouble();

  static HistoryEntry? parse(dynamic raw) {
    try {
      final m = json.decode(raw as String);
      return HistoryEntry(Item.decode(m['i']), '${m['url']}', '${m['title']}',
          (m['pos'] as num).toInt(), (m['dur'] as num).toInt(), (m['ts'] as num).toInt());
    } catch (_) {
      return null;
    }
  }
}

class Store {
  final Box settings, catalog, user;
  Store(this.settings, this.catalog, this.user);

  static Future<Store> open() async {
    await Hive.initFlutter();
    return Store(await Hive.openBox('settings'), await Hive.openBox('catalog'),
        await Hive.openBox('user'));
  }

  T get<T>(String k, T def) {
    final v = settings.get(k);
    return v is T ? v : def;
  }

  Future<void> set(String k, Object? v) => settings.put(k, v);

  // Favoris
  bool isFav(Item i) => user.containsKey('fav:${i.key}');
  Future<void> toggleFav(Item i) =>
      isFav(i) ? user.delete('fav:${i.key}') : user.put('fav:${i.key}', i.encode());

  List<Item> favorites({Kind? kind}) {
    final out = <Item>[];
    for (final k in user.keys) {
      if ('$k'.startsWith('fav:')) {
        try {
          final it = Item.decode(user.get(k));
          if (kind == null || it.kind == kind) out.add(it);
        } catch (_) {}
      }
    }
    return out;
  }

  // Historique / reprise
  Future<void> saveHistory(Item i, String url, String title, int pos, int dur) =>
      user.put(
          'hist:${i.key}',
          json.encode({
            'i': i.encode(),
            'url': url,
            'title': title,
            'pos': pos,
            'dur': dur,
            'ts': DateTime.now().millisecondsSinceEpoch,
          }));

  HistoryEntry? entryFor(Item i) => HistoryEntry.parse(user.get('hist:${i.key}'));

  List<HistoryEntry> history() {
    final l = <HistoryEntry>[];
    for (final k in user.keys) {
      if ('$k'.startsWith('hist:')) {
        final e = HistoryEntry.parse(user.get(k));
        if (e != null) l.add(e);
      }
    }
    l.sort((a, b) => b.ts.compareTo(a.ts));
    return l;
  }

  List<HistoryEntry> continueWatching() => history()
      .where((e) =>
          e.item.kind != Kind.live && e.dur > 0 && e.pos > 15000 && e.progress < 0.95)
      .take(20)
      .toList();

  List<Item> recentLive() => history()
      .where((e) => e.item.kind == Kind.live)
      .take(20)
      .map((e) => e.item)
      .toList();

  Future<void> clearPrefix(String p) =>
      user.deleteAll(user.keys.where((k) => '$k'.startsWith(p)).toList());
}
