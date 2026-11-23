import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/models.dart';
import '../core/store.dart';
import '../services/source.dart';

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _unesc(String s) {
  var t = s.trim();
  if (t.startsWith('<![CDATA[')) {
    t = t.replaceAll('<![CDATA[', '').replaceAll(']]>', '');
  }
  return t
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
}

int? _xmlMs(String s) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{4})?')
      .firstMatch(s.trim());
  if (m == null) return null;
  var t = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!),
          int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6] ?? '0'))
      .millisecondsSinceEpoch;
  final off = m[7];
  if (off != null) {
    final sign = off[0] == '-' ? -1 : 1;
    final mins = int.parse(off.substring(1, 3)) * 60 + int.parse(off.substring(3, 5));
    t -= sign * mins * 60000;
  }
  return t;
}

Map<String, dynamic> _parseXmltv(List<dynamic> args) {
  var data = args[0] as Uint8List;
  final nowMs = args[1] as int;
  if (data.length > 2 && data[0] == 0x1f && data[1] == 0x8b) {
    data = Uint8List.fromList(gzip.decode(data));
  }
  final text = utf8.decode(data, allowMalformed: true);
  final from = nowMs - 2 * 3600000, to = nowMs + 36 * 3600000;

  final names = <String, String>{};
  final chRe = RegExp(r'<channel\s+id="([^"]*)"[^>]*>(.*?)</channel>', dotAll: true);
  final dnRe = RegExp(r'<display-name[^>]*>(.*?)</display-name>', dotAll: true);
  for (final m in chRe.allMatches(text)) {
    for (final n in dnRe.allMatches(m[2]!)) {
      names[_norm(_unesc(n[1]!))] = _unesc(m[1]!).toLowerCase();
    }
  }

  final progs = <String, List<List<dynamic>>>{};
  final pRe = RegExp(r'<programme\s+([^>]*)>(.*?)</programme>', dotAll: true);
  final aRe = RegExp(r'(\w+)="([^"]*)"');
  final tRe = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true);
  for (final m in pRe.allMatches(text)) {
    String? start, stop, ch;
    for (final x in aRe.allMatches(m[1]!)) {
      final k = x[1];
      if (k == 'start') {
        start = x[2];
      } else if (k == 'stop') {
        stop = x[2];
      } else if (k == 'channel') {
        ch = x[2];
      }
    }
    if (start == null || stop == null || ch == null) continue;
    final s = _xmlMs(start), e = _xmlMs(stop);
    if (s == null || e == null || e < from || s > to) continue;
    final title = tRe.firstMatch(m[2]!)?[1];
    if (title == null) continue;
    progs.putIfAbsent(ch.toLowerCase(), () => []).add([s, e, _unesc(title)]);
  }
  return {'p': progs, 'n': names};
}

dynamic _decodeJson(String s) => json.decode(s);
String _encodeJson(dynamic d) => json.encode(d);

class _Cached {
  final DateTime t;
  final List<Programme> l;
  _Cached(this.t, this.l);
}

class EpgService {
  final Store store;
  final Source api;
  EpgService(this.store, this.api);

  Map<String, List<Programme>> _byId = {};
  Map<String, String> _names = {};
  final _srv = <String, _Cached>{};

  void _load(Map data) {
    final by = <String, List<Programme>>{};
    (data['p'] as Map).forEach((k, v) {
      final l = <Programme>[
        for (final e in v as List)
          Programme('${e[2]}', DateTime.fromMillisecondsSinceEpoch((e[0] as num).toInt()),
              DateTime.fromMillisecondsSinceEpoch((e[1] as num).toInt()))
      ]..sort((a, b) => a.start.compareTo(b.start));
      by['$k'.toLowerCase()] = l;
    });
    _byId = by;
    _names = {for (final e in (data['n'] as Map).entries) '${e.key}': '${e.value}'};
  }

  Future<void> init() async {
    final raw = store.catalog.get('epg_xml') as String?;
    if (raw != null) {
      try {
        _load(await compute(_decodeJson, raw) as Map);
      } catch (_) {}
    }
    if (store.epgUrls.isEmpty) return;
    final ts = store.catalog.get('epg_xml_ts') as int?;
    final mode = store.get<String>('update_mode', 'daily');
    final age = ts == null ? 1 << 40 : DateTime.now().millisecondsSinceEpoch - ts;
    final stale = ts == null ||
        mode == 'start' ||
        (mode == 'daily' && age > 12 * 3600 * 1000);
    if (stale) refreshXml();
  }

  /// Télécharge toutes les sources XMLTV et renvoie le nombre de chaînes avec programme.
  Future<int> refreshXml() async {
    final urls = store.epgUrls;
    if (urls.isEmpty) return 0;
    final merged = <String, List<dynamic>>{};
    final names = <String, String>{};
    for (final u in urls) {
      try {
        final r = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 180));
        if (r.statusCode != 200) continue;
        final res = await compute(
            _parseXmltv, <dynamic>[r.bodyBytes, DateTime.now().millisecondsSinceEpoch]);
        (res['p'] as Map).forEach((k, v) {
          merged.putIfAbsent('$k', () => []).addAll(v as List);
        });
        (res['n'] as Map).forEach((k, v) => names['$k'] = '$v');
      } catch (_) {}
    }
    if (merged.isEmpty) return 0;
    final data = {'p': merged, 'n': names};
    _load(data);
    await store.catalog.put('epg_xml', await compute(_encodeJson, data));
    await store.catalog.put('epg_xml_ts', DateTime.now().millisecondsSinceEpoch);
    return merged.length;
  }

  Future<List<Programme>> forChannel(Item ch, {int limit = 8}) async {
    final now = DateTime.now();
    List<Programme>? l;
    final id = ch.epgId.toLowerCase();
    if (id.isNotEmpty && _byId.containsKey(id)) {
      l = _byId[id];
    } else {
      final nid = _names[_norm(ch.name)];
      if (nid != null) l = _byId[nid];
    }
    if (l != null) {
      final r = l.where((p) => p.end.isAfter(now)).take(limit).toList();
      if (r.isNotEmpty) return r;
    }
    if (store.get<bool>('epg_server', true)) {
      final c = _srv[ch.key];
      if (c != null && now.difference(c.t).inMinutes < 5) return c.l;
      try {
        final r = await api.serverEpg(ch, limit: limit);
        _srv[ch.key] = _Cached(now, r);
        return r;
      } catch (_) {}
    }
    return [];
  }
}
