import '../core/models.dart';
import '../core/profile.dart';
import 'm3u_source.dart';
import 'mag_source.dart';
import 'xtream_service.dart';

abstract class Source {
  String get subtitle;
  bool get hasVod => true;
  bool get hasSeries => true;

  Future<void> validate();
  Future<Map<String, String>> account();

  Future<List<dynamic>> getLiveCategories();
  Future<List<dynamic>> getVodCategories();
  Future<List<dynamic>> getSeriesCategories();
  Future<List<dynamic>> getLiveStreams();
  Future<List<dynamic>> getVodStreams();
  Future<List<dynamic>> getSeries();
  Future<Map<String, dynamic>> getSeriesInfo(int id);
  Future<Map<String, dynamic>> getVodInfo(int id);

  Future<List<Programme>> serverEpg(Item ch, {int limit = 8});
  Future<String> liveStream(Item ch, {String ext = 'm3u8'});
  String vodUrl(int id, String ext);
  String episodeUrl(int id, String ext);
}

Source buildSource(Profile p) {
  switch (p.type) {
    case 'm3u':
      return M3uSource(p.url);
    case 'mag':
      return MagSource(p.url, p.mac);
    case 'free':
      return FreeSource();
    default:
      return XtreamService(serverUrl: p.url, username: p.user, password: p.pass);
  }
}
