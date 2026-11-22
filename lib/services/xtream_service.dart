import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

dynamic _parse(Uint8List b) => json.decode(utf8.decode(b));

class XtreamService {
  final String serverUrl, username, password;

  XtreamService({
    required String serverUrl,
    required this.username,
    required this.password,
  }) : serverUrl = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');

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

  Future<List<dynamic>> getLiveCategories() async =>
      _list(await _get(_api({'action': 'get_live_categories'})));
  Future<List<dynamic>> getVodCategories() async =>
      _list(await _get(_api({'action': 'get_vod_categories'})));
  Future<List<dynamic>> getSeriesCategories() async =>
      _list(await _get(_api({'action': 'get_series_categories'})));

  Future<List<dynamic>> getLiveStreams() async =>
      _list(await _get(_api({'action': 'get_live_streams'})));
  Future<List<dynamic>> getVodStreams() async =>
      _list(await _get(_api({'action': 'get_vod_streams'})));
  Future<List<dynamic>> getSeries() async =>
      _list(await _get(_api({'action': 'get_series'})));

  Future<Map<String, dynamic>> getSeriesInfo(int id) async =>
      _map(await _get(_api({'action': 'get_series_info', 'series_id': '$id'})));
  Future<Map<String, dynamic>> getVodInfo(int id) async =>
      _map(await _get(_api({'action': 'get_vod_info', 'vod_id': '$id'})));

  Future<List<dynamic>> getShortEpg(int streamId, {int limit = 2}) async {
    final d = await _get(_api({
      'action': 'get_short_epg',
      'stream_id': '$streamId',
      'limit': '$limit',
    }));
    return d is Map ? _list(d['epg_listings']) : [];
  }

  String liveUrl(int id, {String ext = 'm3u8'}) =>
      '$serverUrl/live/$username/$password/$id.$ext';
  String vodUrl(int id, String ext) =>
      '$serverUrl/movie/$username/$password/$id.$ext';
  String episodeUrl(int id, String ext) =>
      '$serverUrl/series/$username/$password/$id.$ext';
}
