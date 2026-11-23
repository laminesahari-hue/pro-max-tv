import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/models.dart';
import 'source.dart';

/// Portail MAG / Stalker (bêta, chaînes live uniquement, Android).
class MagSource extends Source {
  final String portal, mac;
  MagSource(this.portal, this.mac);

  String? _token;
  String _ep = '';

  @override
  String get subtitle => portal;
  @override
  bool get hasVod => false;
  @override
  bool get hasSeries => false;

  Map<String, String> get _h => {
        'Cookie': 'mac=$mac; stb_lang=en; timezone=Europe/Paris',
        'User-Agent':
            'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG250 stbapp ver: 2 rev: 250 Safari/533.3',
        'X-User-Agent': 'Model: MAG250; Link: WiFi',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<dynamic> _call(Map<String, String> q) async {
    final uri = Uri.parse(_ep).replace(queryParameters: {...q, 'JsHttpRequest': '1-xml'});
    final r = await http.get(uri, headers: _h).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) throw Exception('Erreur portail (${r.statusCode})');
    final d = json.decode(utf8.decode(r.bodyBytes, allowMalformed: true));
    return d is Map ? d['js'] : null;
  }

  Future<void> _connect() async {
    if (_token != null) return;
    final root = portal
        .trim()
        .replaceAll(RegExp(r'/+$'), '')
        .replaceAll(RegExp(r'/c$'), '');
    for (final ep in ['$root/server/load.php', '$root/portal.php']) {
      _ep = ep;
      try {
        final js = await _call({'type': 'stb', 'action': 'handshake', 'token': ''});
        final t = js is Map ? js['token'] : null;
        if (t != null && '$t'.isNotEmpty) {
          _token = '$t';
          try {
            await _call({'type': 'stb', 'action': 'get_profile'});
          } catch (_) {}
          return;
        }
      } catch (_) {}
    }
    throw Exception('Portail MAG injoignable ou adresse MAC refusée');
  }

  @override
  Future<void> validate() => _connect();

  @override
  Future<Map<String, String>> account() async => {'Portail': portal, 'MAC': mac};

  @override
  Future<List<dynamic>> getLiveCategories() async {
    await _connect();
    final js = await _call({'type': 'itv', 'action': 'get_genres'});
    return [
      for (final g in (js is List ? js : []))
        if (g is Map && '${g['id']}' != '*')
          {'category_id': '${g['id']}', 'category_name': '${g['title']}'}
    ];
  }

  @override
  Future<List<dynamic>> getLiveStreams() async {
    await _connect();
    final js = await _call({'type': 'itv', 'action': 'get_all_channels'});
    final data = js is Map ? js['data'] : null;
    return [
      for (final c in (data is List ? data : []))
        if (c is Map)
          {
            'stream_id': int.tryParse('${c['id']}') ?? 0,
            'name': c['name'],
            'stream_icon': '${c['logo'] ?? ''}'.startsWith('http') ? c['logo'] : '',
            'category_id': '${c['tv_genre_id']}',
            'direct_url': '${c['cmd']}',
            'num': c['number'],
          }
    ];
  }

  @override
  Future<String> liveStream(Item ch, {String ext = 'm3u8'}) async {
    await _connect();
    final cmd = ch.directUrl;
    final js = await _call({'type': 'itv', 'action': 'create_link', 'cmd': cmd});
    var u = js is Map ? '${js['cmd'] ?? ''}' : '';
    if (u.isEmpty) u = cmd;
    return u.replaceFirst(RegExp(r'^(ffmpeg|ffrt\d?|auto)\s+'), '').trim();
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
  String vodUrl(int id, String ext) => '';
  @override
  String episodeUrl(int id, String ext) => '';
}
