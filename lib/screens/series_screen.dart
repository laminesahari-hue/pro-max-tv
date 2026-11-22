import 'package:flutter/material.dart';
import '../services/xtream_service.dart';
import 'player_screen.dart';

class SeriesScreen extends StatelessWidget {
  final XtreamService api;
  final dynamic series;
  const SeriesScreen({super.key, required this.api, required this.series});

  @override
  Widget build(BuildContext context) {
    final id = int.tryParse('${series['series_id']}') ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text('${series['name'] ?? 'Série'}')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: api.getSeriesInfo(id),
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          final raw = snap.data?['episodes'];
          final seasons = <String, List>{};
          if (raw is Map) {
            raw.forEach((k, v) => seasons['$k'] = v is List ? v : []);
          } else if (raw is List) {
            seasons['1'] = raw;
          }
          if (seasons.isEmpty) return const Center(child: Text('Aucun épisode'));
          final keys = seasons.keys.toList()
            ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
          return ListView(children: [
            for (final k in keys)
              ExpansionTile(
                title: Text('Saison $k'),
                children: [
                  for (final ep in seasons[k]!)
                    ListTile(
                      title: Text('${ep['episode_num'] ?? ''}. ${ep['title'] ?? ''}'),
                      onTap: () {
                        final epId = int.tryParse('${ep['id']}') ?? 0;
                        final ext = '${ep['container_extension'] ?? 'mp4'}';
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PlayerScreen(
                              streamUrl: api.episodeUrl(epId, ext),
                              title: '${series['name']} S$k',
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
          ]);
        },
      ),
    );
  }
}
