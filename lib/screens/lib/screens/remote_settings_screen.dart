import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/scope.dart';
import '../widgets/tv_settings_items.dart';

class RemoteSettingsScreen extends StatefulWidget {
  const RemoteSettingsScreen({super.key});

  @override
  State<RemoteSettingsScreen> createState() => _RemoteSettingsScreenState();
}

class _RemoteSettingsScreenState extends State<RemoteSettingsScreen> {
  late final AppScope app;

  static const Map<String, String> actions = {
    'none': 'Non défini',
    'channel_list': 'Liste des chaînes',
    'channel_up': 'Chaîne vers le haut',
    'channel_down': 'Chaîne vers le bas',
    'seek_back': 'Aller en arrière',
    'seek_forward': 'Aller en avant',
    'toggle_controls': 'Afficher / masquer les commandes',
    'epg_guide': 'Guide TV (EPG)',
    'toggle_fav': 'Ajouter / retirer des favoris',
  };

  @override
  void initState() {
    super.initState();
    app = AppScope.of(context);
  }

  Widget _keyTile(String storeKey, String label, String defAction,
      {bool autofocus = false}) {
    final cur = app.store.get<String>(storeKey, defAction);
    return TvNavTile(
      autofocus: autofocus,
      icon: Icons.settings_remote_outlined,
      title: label,
      subtitle: actions[cur] ?? 'Non défini',
      onTap: () async {
        final chosen = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(label),
            children: [
              for (final e in actions.entries)
                TvNavTile(
                  autofocus: e.key == cur,
                  icon: e.key == cur
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  title: e.value,
                  onTap: () => Navigator.pop(ctx, e.key),
                ),
            ],
          ),
        );
        if (chosen != null) {
          await app.store.set(storeKey, chosen);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Télécommande')),
      body: ValueListenableBuilder(
        valueListenable: app.store.settings.listenable(),
        builder: (_, __, ___) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            _keyTile('rc_ok', 'OK', 'toggle_controls', autofocus: true),
            _keyTile('rc_ok_long', 'OK (appui long)', 'channel_list'),
            _keyTile('rc_left', 'Gauche', 'seek_back'),
            _keyTile('rc_left_long', 'Gauche (appui long)', 'none'),
            _keyTile('rc_right', 'Droite', 'seek_forward'),
            _keyTile('rc_right_long', 'Droite (appui long)', 'none'),
            _keyTile('rc_up', 'Haut', 'channel_up'),
            _keyTile('rc_up_long', 'Haut (appui long)', 'none'),
            _keyTile('rc_down', 'Bas', 'channel_down'),
            _keyTile('rc_down_long', 'Bas (appui long)', 'none'),
          ],
        ),
      ),
    );
  }
}
