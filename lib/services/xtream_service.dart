import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/models.dart';
import 'source.dart';

dynamic _parse(Uint8List b) => json.decode(utf8.decode(b));

String _b64(dynamic v) {
  final s = v == null ? '' : '$v';
  try {
    return utf8.decode(base64.decode(s));
  } catch (_) {
    return s;
  }
}

class XtreamService extends Source {
  final String serverUrl, username, password;

  XtreamService({
    required String serverUrl,
    required this.username,
    required this.password,
  }) : serverUrl = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');

  @override
  String get subtitle => serverUrl;

  Uri _api([Map<String, String> extra = const {}]) =>
      Uri.parse('$serverUrl/player_api.php').replace(queryParameters: {
        'username': username,
        'password': password,
        ...extra,
      });

  Future<dynamic> _get(Uri uri) async {
    final res = await http.get(uri).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) {
      throw Exception('Erreur serveur (${res.statusCode})');
    }
    return compute(_parse, res.bodyBytes);
  }

  List<dynamic> _list(dynamic d) => d is List ? d : [];
  Map<String, dynamic> _map(dynamic d) =>
      d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

  Future<Map<String, dynamic>> login() async {
    final d = await _get(_api());
    if (d is Map && d['user_info'] is Map && '${d['user_info']['auth']}' == '1') {
      return Map<String, dynamic>.from(d);
    }
    throw Exception('Identifiants invalides');
  }

  @override
  Future<void> validate() async {
    await login();
  }

  String _exp(dynamic v) {
    final n = int.tryParse('${v ?? ''}');
    if (n == null) return 'Illimité';
    final d = DateTime.fromMillisecondsSinceEpoch(n * 1000);
    String t(int x) => x.toString().padLeft(2, '0');
    return '${t(d.day)}/${t(d.month)}/${d.year}';
  }

  @override
  Future<Map<String, String>> account() async {
    final d = await login();
    final u = Map<String, dynamic>.from(d['user_info'] as Map);
    return {
      'Serveur': serverUrl,
      'Utilisateur': username,
      'Statut': '${u['status'] ?? '-'}',
      'Expiration': _exp(u['exp_date']),
      'Connexions': '${u['active_cons'] ?? 0} / ${u['max_connections'] ?? '-'}',
    };
  }

  @override
  Future<List<dynamic>> getLiveCategories() async =>
      _list(await _get(_api({'action': 'get_live_categories'})));
  @override
  Future<List<dynamic>> getVodCategories() async =>
      _list(await _get(_api({'action': 'get_vod_categories'})));
  @override
  Future<List<dynamic>> getSeriesCategories() async =>
      _list(await _get(_api({'action': 'get_series_categories'})));

  @override
  Future<List<dynamic>> getLiveStreams() async =>
      _list(await _get(_api({'action': 'get_live_streams'})));
  @override
  Future<List<dynamic>> getVodStreams() async =>
      _list(await _get(_api({'action': 'get_vod_streams'})));
  @override
  Future<List<dynamic>> getSeries() async =>
      _list(await _get(_api({'action': 'get_series'})));

  @override
  Future<Map<String, dynamic>> getSeriesInfo(int id) async =>
      _map(await _get(_api({'action': 'get_series_info', 'series_id': '$id'})));
  @override
  Future<Map<String, dynamic>> getVodInfo(int id) async =>
      _map(await _get(_api({'action': 'get_vod_info', 'vod_id': '$id'})));

  @override
  Future<List<Programme>> serverEpg(Item ch, {int limit = 8}) async {
    final d = await _get(_api({
      'action': 'get_short_epg',
      'stream_id': '${ch.id}',
      'limit': '$limit',
    }));
    final out = <Programme>[];
    if (d is Map && d['epg_listings'] is List) {
      for (final e in d['epg_listings'] as List) {
        final s = int.tryParse('${e['start_timestamp']}');
        final t = int.tryParse('${e['stop_timestamp']}');
        if (s == null || t == null) continue;
        out.add(Programme(_b64(e['title']),
            DateTime.fromMillisecondsSinceEpoch(s * 1000),
            DateTime.fromMillisecondsSinceEpoch(t * 1000)));
      }
    }
    return out;
  }

  @override
  Future<String> liveStream(Item ch, {String ext = 'm3u8'}) async =>
      '$serverUrl/live/$username/$password/${ch.id}.$ext';
  @override
  String vodUrl(int id, String ext) => '$serverUrl/movie/$username/$password/$id.$ext';
  @override
  String episodeUrl(int id, String ext) =>
      '$serverUrl/series/$username/$password/$id.$ext';
}
