import 'dart:convert';

enum Kind { live, vod, series }

String _s(dynamic v) => v == null ? '' : '$v';

class Item {
  final Kind kind;
  final Map raw;
  Item(this.kind, this.raw);

  int get id => int.tryParse(_s(kind == Kind.series ? raw['series_id'] : raw['stream_id'])) ?? 0;
  String get name => _s(raw['name']);
  String get image =>
      _s(raw['stream_icon']).isNotEmpty ? _s(raw['stream_icon']) : _s(raw['cover']);
  String get cat => _s(raw['category_id']);
  double get rating5 {
    final r5 = double.tryParse(_s(raw['rating_5based']));
    if (r5 != null) return r5;
    return (double.tryParse(_s(raw['rating'])) ?? 0) / 2;
  }

  String get ext =>
      _s(raw['container_extension']).isEmpty ? 'mp4' : _s(raw['container_extension']);
  int get added =>
      int.tryParse(_s(raw['added'])) ?? int.tryParse(_s(raw['last_modified'])) ?? 0;
  String get epgId => _s(raw['epg_channel_id']);
  String get directUrl => _s(raw['direct_url']);
  int get number => int.tryParse(_s(raw['num'])) ?? 0;
  String get key => '${kind.name}:$id';

  String encode() => json.encode({'k': kind.name, 'r': raw});
  static Item decode(String s) {
    final m = json.decode(s);
    return Item(Kind.values.byName(m['k']), Map<String, dynamic>.from(m['r']));
  }
}

class Programme {
  final String title;
  final DateTime start, end;
  const Programme(this.title, this.start, this.end);

  bool get isNow {
    final n = DateTime.now();
    return !n.isBefore(start) && n.isBefore(end);
  }

  double get progress {
    final total = end.difference(start).inSeconds;
    if (total <= 0) return 0;
    return (DateTime.now().difference(start).inSeconds / total).clamp(0.0, 1.0).toDouble();
  }
}
