import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/xtream_service.dart';

class SettingsScreen extends StatelessWidget {
  final Box settings, catalog;
  final XtreamService api;
  final VoidCallback onLogout;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.catalog,
    required this.api,
    required this.onLogout,
  });

  bool _on(String key) => settings.get(key, defaultValue: true) as bool;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Paramètres')),
        body: ValueListenableBuilder(
          valueListenable: settings.listenable(keys: ['show_vod', 'show_series']),
          builder: (_, __, ___) => ListView(children: [
            const _Header('Affichage'),
            SwitchListTile(
              title: const Text('Films'),
              subtitle: const Text("Afficher l'onglet Films"),
              value: _on('show_vod'),
              onChanged: (v) => settings.put('show_vod', v),
            ),
            SwitchListTile(
              title: const Text('Séries'),
              subtitle: const Text("Afficher l'onglet Séries"),
              value: _on('show_series'),
              onChanged: (v) => settings.put('show_series', v),
            ),
            const _Header('Compte'),
            ListTile(title: const Text('Serveur'), subtitle: Text(api.serverUrl)),
            ListTile(
                title: const Text('Utilisateur'), subtitle: Text(api.username)),
            const _Header('Données'),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Vider le cache et recharger'),
              onTap: () async {
                await catalog.clear();
                await settings.put(
                    'refresh', DateTime.now().millisecondsSinceEpoch);
                if (context.mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Se déconnecter'),
              onTap: () {
                Navigator.pop(context);
                onLogout();
              },
            ),
          ]),
        ),
      );
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary)),
      );
}
