import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/scope.dart';
import '../core/store.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AppScope app;
  late final Future<Map<String, dynamic>> _acc;

  @override
  void initState() {
    super.initState();
    app = AppScope.of(context);
    _acc = app.api.login();
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

  Widget _action(IconData icon, String title, String sub, Future<void> Function() run,
      {String? done}) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: sub.isEmpty ? null : Text(sub),
        onTap: () async {
          await run();
          if (done != null && mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(done)));
          }
        },
      );

  String _exp(dynamic v) {
    final n = int.tryParse('${v ?? ''}');
    if (n == null) return 'Illimité';
    final d = DateTime.fromMillisecondsSinceEpoch(n * 1000);
    String t(int x) => x.toString().padLeft(2, '0');
    return '${t(d.day)}/${t(d.month)}/${d.year}';
  }

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
        _head('Interface'),
        _sw('show_live', 'Live TV', "Afficher l'onglet Live"),
        _sw('show_vod', 'Films', "Afficher l'onglet Films"),
        _sw('show_series', 'Séries', "Afficher l'onglet Séries"),
        _sw('show_hero', "Bannière à la une", "Afficher les contenus mis en avant sur l'accueil"),
        _sw('hide_adult', 'Masquer le contenu adulte',
            'Cache les catégories adultes (XXX, 18+...)'),
        _choice<int>('accent', 'Couleur du thème', const {
          0: 'Rouge',
          1: 'Bleu',
          2: 'Vert',
          3: 'Orange',
          4: 'Violet',
        }, 0),
        _head('Lecture'),
        _choice<String>('live_ext', 'Format des chaînes live', const {
          'm3u8': 'HLS (.m3u8) - recommandé',
          'ts': 'MPEG-TS (.ts)',
        }, 'm3u8'),
        _sw('hwdec', 'Décodage matériel', 'Plus fluide, désactive-le si l\'image bug'),
        _choice<int>('buffer', 'Taille du tampon', const {
          0: 'Court (zapping rapide)',
          1: 'Normal',
          2: 'Long (connexion instable)',
        }, 1),
        _choice<int>('fit', 'Format de l\'image par défaut', const {
          0: 'Adapté (barres noires)',
          1: 'Remplir (recadré)',
          2: 'Étirer',
        }, 0),
        _sw('resume', 'Reprendre la lecture', 'Reprend les films et épisodes où tu t\'es arrêté'),
        _head('Données'),
        _choice<int>('ttl_h', 'Actualisation du catalogue', const {
          1: 'Toutes les heures',
          6: 'Toutes les 6 heures',
          24: 'Tous les jours',
        }, 6),
        _action(Icons.refresh, 'Vider le cache et recharger', '', () async {
          app.repo.clearMemory();
          await st.catalog.clear();
          await st.set('refresh', DateTime.now().millisecondsSinceEpoch);
        }, done: 'Catalogue rechargé'),
        _action(Icons.history, "Effacer l'historique", 'Reprise de lecture et chaînes récentes',
            () => st.clearPrefix('hist:'), done: 'Historique effacé'),
        _action(Icons.favorite_border, 'Effacer les favoris', '',
            () => st.clearPrefix('fav:'), done: 'Favoris effacés'),
        _head('Compte'),
        FutureBuilder<Map<String, dynamic>>(
          future: _acc,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const ListTile(title: Text('Chargement...'));
            }
            if (snap.hasError) {
              return const ListTile(title: Text("Infos d'abonnement indisponibles"));
            }
            final u = Map<String, dynamic>.from(snap.data!['user_info'] as Map);
            return Column(children: [
              ListTile(title: const Text('Serveur'), subtitle: Text(app.api.serverUrl)),
              ListTile(title: const Text('Utilisateur'), subtitle: Text(app.api.username)),
              ListTile(title: const Text('Statut'), subtitle: Text('${u['status'] ?? '-'}')),
              ListTile(title: const Text('Expiration'), subtitle: Text(_exp(u['exp_date']))),
              ListTile(
                  title: const Text('Connexions'),
                  subtitle: Text('${u['active_cons'] ?? 0} / ${u['max_connections'] ?? '-'}')),
            ]);
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Se déconnecter'),
          onTap: app.onLogout,
        ),
        _head('À propos'),
        const ListTile(title: Text('Pro Max TV'), subtitle: Text('Version 1.1.0')),
        const SizedBox(height: 24),
      ]),
    );
  }
}
