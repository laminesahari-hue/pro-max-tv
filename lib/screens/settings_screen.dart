import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/scope.dart';
import '../core/store.dart';
import 'sources_screen.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AppScope app;
  late final Future<Map<String, String>> _acc;

  @override
  void initState() {
    super.initState();
    app = AppScope.of(context);
    _acc = app.api.account();
  }

  Widget _head(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 4),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: Theme.of(context).colorScheme.primary)),
      );

  Widget _sw(String key, String title, String sub, {bool def = true}) =>
      SwitchListTile(
        title: Text(title),
        subtitle: Text(sub),
        value: app.store.get<bool>(key, def),
        onChanged: (v) => app.store.set(key, v),
      );

  Widget _choice<T>(String key, String title, Map<T, String> opts, T def) {
    final cur = app.store.get<T>(key, def);
    return ListTile(
      title: Text(title),
      subtitle: Text(opts[cur] ?? ''),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final v = await showDialog<T>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(title),
            children: [
              for (final e in opts.entries)
                ListTile(
                  leading: Icon(e.key == cur
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off),
                  title: Text(e.value),
                  onTap: () => Navigator.pop(ctx, e.key),
                ),
            ],
          ),
        );
        if (v != null) app.store.set(key, v);
      },
    );
  }

  Widget _link(IconData icon, String title, String sub, Widget page) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      );

  Widget _action(IconData icon, String title, String sub, Future<void> Function() run,
          String done) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: sub.isEmpty ? null : Text(sub),
        onTap: () async {
          await run();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
          }
        },
      );

  @override
  Widget build(BuildContext context) {
    final Store st = app.store;
    return ValueListenableBuilder(
      valueListenable: st.settings.listenable(),
      builder: (_, __, ___) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text('Réglages',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
        _head('Sources'),
        _link(Icons.dns, 'Sources & playlists', 'Source active : ${app.profile.name}',
            const SourcesScreen()),
        _link(Icons.event_note, 'Sources EPG', 'Guides des programmes (XMLTV)',
            const EpgSourcesScreen()),
        _choice<String>('update_mode', 'Mise à jour des listes', const {
          'start': 'Au démarrage',
          'daily': 'Toutes les 24 heures',
          'manual': 'Manuelle',
        }, 'daily'),
        _head('Live TV'),
        _choice<String>('start_tab', 'Au démarrage', const {
          'home': 'Accueil',
          'live': 'Live TV',
          'last': 'Reprendre la dernière chaîne',
        }, 'home'),
        _sw('fast_zap', 'Zapping rapide', 'Démarrage plus rapide des chaînes'),
        _choice<String>('live_ext', 'Format des chaînes (Xtream)', const {
          'm3u8': 'HLS (.m3u8) - recommandé',
          'ts': 'MPEG-TS (.ts)',
        }, 'm3u8'),
        _head('Lecture'),
        _sw('abr', 'Qualité adaptative', 'Baisse ou remonte la qualité selon la connexion'),
        _sw('hwdec', 'Décodage matériel', "Plus fluide, désactive-le si l'image bug"),
        _choice<int>('buffer', 'Taille du tampon', const {
          0: 'Court (zapping rapide)',
          1: 'Normal',
          2: 'Long (connexion instable)',
        }, 1),
        _choice<int>('fit', "Format de l'image par défaut", const {
          0: 'Adapté (barres noires)',
          1: 'Remplir (recadré)',
          2: 'Étirer',
        }, 0),
        _choice<int>('seek_step', 'Saut avant / arrière', const {
          10: '10 secondes',
          30: '30 secondes',
        }, 10),
        _choice<int>('overlay_secs', 'Masquage des commandes', const {
          3: 'Après 3 secondes',
          6: 'Après 6 secondes',
          10: 'Après 10 secondes',
        }, 6),
        _sw('resume', 'Reprendre la lecture', "Reprend les films et épisodes où tu t'es arrêté"),
        _head('Interface'),
        _sw('show_live', 'Live TV', "Afficher les onglets Live et Guide"),
        _sw('show_vod', 'Films', "Afficher l'onglet Films"),
        _sw('show_series', 'Séries', "Afficher l'onglet Séries"),
        _sw('show_hero', 'Bannière à la une', "Contenus mis en avant sur l'accueil"),
        _sw('hide_adult', 'Masquer le contenu adulte', 'Cache les catégories adultes (XXX, 18+...)'),
        _choice<int>('accent', 'Couleur du thème', const {
          0: 'Rouge',
          1: 'Bleu',
          2: 'Vert',
          3: 'Orange',
          4: 'Violet',
        }, 0),
        _head('Données'),
        _action(Icons.refresh, 'Vider le cache et recharger', '', () async {
          app.repo.clearMemory();
          await st.clearCatalog();
          await st.set('refresh', DateTime.now().millisecondsSinceEpoch);
        }, 'Catalogue rechargé'),
        _action(Icons.history, "Effacer l'historique", 'Reprise de lecture et chaînes récentes',
            st.clearHistory, 'Historique effacé'),
        _action(Icons.favorite_border, 'Effacer les favoris', '', st.clearFavorites,
            'Favoris effacés'),
        _head('Compte'),
        FutureBuilder<Map<String, String>>(
          future: _acc,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const ListTile(title: Text('Chargement...'));
            }
            if (snap.hasError) {
              return const ListTile(title: Text('Infos indisponibles'));
            }
            return Column(children: [
              for (final e in snap.data!.entries)
                ListTile(title: Text(e.key), subtitle: Text(e.value)),
            ]);
          },
        ),
        _head('À propos'),
        const ListTile(title: Text('Pro Max TV'), subtitle: Text('Version 1.2.0')),
        const SizedBox(height: 24),
      ]),
    );
  }
}
