class Profile {
  final String id, name, type, url, user, pass, mac;
  const Profile({
    required this.id,
    required this.name,
    required this.type,
    this.url = '',
    this.user = '',
    this.pass = '',
    this.mac = '',
  });

  String get typeLabel =>
      const {
        'xtream': 'Xtream Codes',
        'm3u': 'Playlist M3U',
        'mag': 'Portail MAG (bêta)',
        'free': 'Chaînes gratuites',
      }[type] ??
      type;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'url': url,
        'user': user,
        'pass': pass,
        'mac': mac,
      };

  factory Profile.fromJson(Map<String, dynamic> m) => Profile(
        id: '${m['id']}',
        name: '${m['name']}',
        type: '${m['type']}',
        url: '${m['url'] ?? ''}',
        user: '${m['user'] ?? ''}',
        pass: '${m['pass'] ?? ''}',
        mac: '${m['mac'] ?? ''}',
      );
}
