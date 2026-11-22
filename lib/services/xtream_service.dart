import 'dart:convert';
import 'package:http/http.dart' as http;

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
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('Erreur serveur (${res.statusCode})');
    }
    return json.decode(utf8.decode(res.bodyBytes));
  }

  List<dynamic> _list(dynamic d) => d is List ? d : [];

  Future<Map<String, dynamic>> login() async {
    final data = await _get(_api());
    if (data is Map<String, dynamic> &&
        data['user_info']?['auth']?.toString() == '1') {
      return data;
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

  Future<Map<String, dynamic>> getSeriesInfo(int id) async {
    final d = await _get(_api({'action': 'get_series_info', 'series_id': '$id'}));
    return d is Map<String, dynamic> ? d : {};
  }

  Future<List<dynamic>> getShortEpg(int streamId, {int limit = 4}) async {
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
