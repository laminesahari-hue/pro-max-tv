import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'models.dart';
import 'profile.dart';

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
  String pid = 'none';
  Store(this.settings, this.catalog, this.user);

  static Future<Store> open() async {
    await Hive.initFlutter();
    final s = Store(await Hive.openBox('settings'), await Hive.openBox('catalog'),
        await Hive.openBox('user'));
    await s._migrate();
    s.pid = s.active?.id ?? 'none';
    return s;
  }

  // ancien format (une seule source) -> profil
  Future<void> _migrate() async {
    if (profiles.isEmpty && settings.get('url') != null) {
      final p = Profile(
        id: 'legacy',
        name: 'Mon abonnement',
        type: 'xtream',
        url: '${settings.get('url')}',
        user: '${settings.get('user') ?? ''}',
        pass: '${settings.get('pass') ?? ''}',
      );
      await saveProfiles([p]);
      await settings.put('active', p.id);
      await settings.deleteAll(['url', 'user', 'pass']);
    }
  }

  T get<T>(String k, T def) {
    final v = settings.get(k);
    return v is T ? v : def;
  }

  Future<void> set(String k, Object? v) => settings.put(k, v);

  // ---- profils ----
  List<Profile> get profiles {
    final raw = settings.get('profiles');
    if (raw is! String) return [];
    try {
      return [
        for (final m in json.decode(raw) as List)
          Profile.fromJson(Map<String, dynamic>.from(m as Map))
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveProfiles(List<Profile> l) =>
      settings.put('profiles', json.encode([for (final p in l) p.toJson()]));

  String? get activeId => settings.get('active') as String?;
  Future<void> setActive(String id) {
    pid = id;
    return settings.put('active', id);
  }

  Profile? get active {
    final l = profiles;
    for (final p in l) {
      if (p.id == activeId) return p;
    }
    return l.isEmpty ? null : l.first;
  }

  // ---- sources EPG ----
  List<String> get epgUrls {
    final raw = settings.get('epg_urls');
    if (raw is! String) return [];
    try {
      return List<String>.from(json.decode(raw) as List);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveEpgUrls(List<String> l) => settings.put('epg_urls', json.encode(l));

  // ---- favoris ----
  String get _fp => 'fav:$pid:';
  String get _hp => 'hist:$pid:';

  bool isFav(Item i) => user.containsKey('$_fp${i.key}');
  Future<void> toggleFav(Item i) =>
      isFav(i) ? user.delete('$_fp${i.key}') : user.put('$_fp${i.key}', i.encode());

  List<Item> favorites({Kind? kind}) {
    final out = <Item>[];
    for (final k in user.keys) {
      if ('$k'.startsWith(_fp)) {
        try {
          final it = Item.decode(user.get(k));
          if (kind == null || it.kind == kind) out.add(it);
        } catch (_) {}
      }
    }
    return out;
  }

  // ---- historique / reprise ----
  Future<void> saveHistory(Item i, String url, String title, int pos, int dur) =>
      user.put(
          '$_hp${i.key}',
          json.encode({
            'i': i.encode(),
            'url': url,
            'title': title,
            'pos': pos,
            'dur': dur,
            'ts': DateTime.now().millisecondsSinceEpoch,
          }));

  HistoryEntry? entryFor(Item i) => HistoryEntry.parse(user.get('$_hp${i.key}'));

  List<HistoryEntry> history() {
    final l = <HistoryEntry>[];
    for (final k in user.keys) {
      if ('$k'.startsWith(_hp)) {
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

  Future<void> _deleteWhere(Box b, String prefix) =>
      b.deleteAll(b.keys.where((k) => '$k'.startsWith(prefix)).toList());

  Future<void> clearFavorites() => _deleteWhere(user, _fp);
  Future<void> clearHistory() => _deleteWhere(user, _hp);
  Future<void> clearCatalog() => _deleteWhere(catalog, '${pid}_');

  Future<void> removeProfileData(String id) async {
    await _deleteWhere(user, 'fav:$id:');
    await _deleteWhere(user, 'hist:$id:');
    await _deleteWhere(catalog, '${id}_');
  }
}
