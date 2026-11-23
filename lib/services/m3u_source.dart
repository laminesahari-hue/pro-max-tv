import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/models.dart';
import 'source.dart';

int _hash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0x7fffffff;
  }
  return h;
}

List<dynamic> _parseM3u(String text) {
  final out = <Map<String, dynamic>>[];
  final attr = RegExp(r'([\w-]+)="([^"]*)"');
  Map<String, dynamic>? cur;
  for (final line in const LineSplitter().convert(text)) {
    final l = line.trim();
    if (l.isEmpty) continue;
    if (l.startsWith('#EXTINF')) {
      final a = <String, String>{
        for (final m in attr.allMatches(l)) m[1]!.toLowerCase(): m[2]!
      };
      final rest = l.replaceAll(attr, '');
      final i = rest.indexOf(',');
      var name = i >= 0 ? rest.substring(i + 1).trim() : '';
      if (name.isEmpty) name = a['tvg-name'] ?? '';
      final group = a['group-title'] ?? '';
      cur = {
        'name': name,
        'logo': a['tvg-logo'] ?? '',
        'group': group.isEmpty ? 'Autres' : group,
        'epg': a['tvg-id'] ?? '',
      };
    } else if (!l.startsWith('#') && cur != null) {
      cur['url'] = l;
      out.add(cur);
      cur = null;
    }
  }
  return out;
}

class M3uSource extends Source {
  final String url;
  M3uSource(this.url);

  Future<List<Map<String, dynamic>>>? _list;

  @override
  String get subtitle => url;
  @override
  bool get hasVod => false;
  @override
  bool get hasSeries => false;

  Future<String> fetchText() async {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw Exception('Erreur serveur (${r.statusCode})');
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  Future<List<Map<String, dynamic>>> _fetchParsed() async {
    final raw = await compute(_parseM3u, await fetchText());
    final l = [for (final e in raw) Map<String, dynamic>.from(e as Map)];
    if (l.isEmpty) throw Exception('Playlist vide ou invalide');
    return l;
  }

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      return await (_list ??= _fetchParsed());
    } catch (_) {
      _list = null;
      rethrow;
    }
  }

  @override
  Future<void> validate() async {
    await _load();
  }

  @override
  Future<Map<String, String>> account() async => {
        'Source': 'Playlist M3U',
        'Adresse': subtitle,
        'Chaînes': '${(await _load()).length}',
      };

  @override
  Future<List<dynamic>> getLiveCategories() async {
    final groups = <String>{};
    for (final e in await _load()) {
      groups.add('${e['group']}');
    }
    return [
      for (final g in groups) {'category_id': g, 'category_name': g}
    ];
  }

  @override
  Future<List<dynamic>> getLiveStreams() async {
    final l = await _load();
    return [
      for (var i = 0; i < l.length; i++)
        {
          'stream_id': _hash('${l[i]['url']}'),
          'name': l[i]['name'],
          'stream_icon': l[i]['logo'],
          'category_id': l[i]['group'],
          'epg_channel_id': l[i]['epg'],
          'direct_url': l[i]['url'],
          'num': i + 1,
        }
    ];
  }

  @override
  Future<List<dynamic>> getVodCategories() async => [];
  @override
  Future<List<dynamic>> getSeriesCategories() async => [];
  @override
  Future<List<dynamic>> getVodStreams() async => [];
  @override
  Future<List<dynamic>> getSeries() async => [];
  @override
  Future<Map<String, dynamic>> getSeriesInfo(int id) async => {};
  @override
  Future<Map<String, dynamic>> getVodInfo(int id) async => {};
  @override
  Future<List<Programme>> serverEpg(Item ch, {int limit = 8}) async => [];
  @override
  Future<String> liveStream(Item ch, {String ext = 'm3u8'}) async => ch.directUrl;
  @override
  String vodUrl(int id, String ext) => '';
  @override
  String episodeUrl(int id, String ext) => '';
}

/// Chaînes d'information publiques et gratuites (adresses officielles des diffuseurs).
/// Elles peuvent changer : si une chaîne ne démarre plus, l'adresse doit être mise à jour.
const _freeM3u = '''
#EXTM3U
#EXTINF:-1 group-title="Actualités",France 24 (Français)
https://static.france24.com/live/F24_FR_LO_HLS/live_web.m3u8
#EXTINF:-1 group-title="Actualités",France 24 (English)
https://static.france24.com/live/F24_EN_LO_HLS/live_web.m3u8
#EXTINF:-1 group-title="Actualités",France 24 (العربية)
https://static.france24.com/live/F24_AR_LO_HLS/live_web.m3u8
#EXTINF:-1 group-title="Actualités",Al Jazeera English
https://live-hls-web-aje.getaj.net/AJE/index.m3u8
#EXTINF:-1 group-title="Actualités",Al Jazeera (العربية)
https://live-hls-web-aja.getaj.net/AJA/index.m3u8
''';

class FreeSource extends M3uSource {
  FreeSource() : super('');

  @override
  String get subtitle => 'Chaînes publiques gratuites';

  @override
  Future<String> fetchText() async => _freeM3u;

  @override
  Future<Map<String, String>> account() async => {
        'Source': 'Chaînes gratuites',
        'Chaînes': '${(await getLiveStreams()).length}',
      };
}
