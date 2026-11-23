import 'package:flutter/material.dart';
import '../core/profile.dart';
import '../core/scope.dart';
import '../widgets/tv_field.dart';
import 'login_screen.dart';

class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  late final AppScope app;

  @override
  void initState() {
    super.initState();
    app = AppScope.of(context);
  }

  void _toRoot() => Navigator.of(context).popUntil((r) => r.isFirst);

  Future<void> _delete(Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette source ?'),
        content: Text('${p.name} et ses favoris seront supprimés.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    final wasActive = p.id == app.profile.id;
    await app.onRemove(p);
    if (!mounted) return;
    if (wasActive) {
      _toRoot();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = app.store.profiles;
    final hasFree = list.any((p) => p.id == 'free');
    return Scaffold(
      appBar: AppBar(title: const Text('Sources & playlists')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileFormScreen(onSave: (p) async {
              await app.onAdd(p);
              if (mounted) _toRoot();
            }),
          ),
        ),
      ),
      body: ListView(children: [
        for (final p in list)
          ListTile(
            leading: Icon(p.id == app.profile.id
                ? Icons.radio_button_checked
                : Icons.radio_button_off),
            title: Text(p.name),
            subtitle: Text(p.typeLabel),
            onTap: () {
              if (p.id != app.profile.id) {
                app.onActivate(p);
                _toRoot();
              }
            },
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Supprimer',
              onPressed: () => _delete(p),
            ),
          ),
        if (!hasFree)
          ListTile(
            leading: const Icon(Icons.live_tv),
            title: const Text('Ajouter les chaînes gratuites'),
            subtitle: const Text('France 24, Al Jazeera…'),
            onTap: () async {
              await app.onAdd(const Profile(
                  id: 'free', name: 'Chaînes gratuites', type: 'free'));
              if (mounted) _toRoot();
            },
          ),
        const SizedBox(height: 80),
      ]),
    );
  }
}

class EpgSourcesScreen extends StatefulWidget {
  const EpgSourcesScreen({super.key});

  @override
  State<EpgSourcesScreen> createState() => _EpgSourcesScreenState();
}

class _EpgSourcesScreenState extends State<EpgSourcesScreen> {
  late final AppScope app;
  late List<String> _urls;

  static const suggestion = 'https://xmltvfr.fr/xmltv/xmltv.xml.gz';

  @override
  void initState() {
    super.initState();
    app = AppScope.of(context);
    _urls = app.store.epgUrls;
  }

  Future<void> _add(String u) async {
    u = u.trim();
    if (!u.startsWith('http')) return;
    if (!_urls.contains(u)) {
      _urls = [..._urls, u];
      await app.store.saveEpgUrls(_urls);
    }
    if (mounted) setState(() {});
  }

  Future<void> _remove(String u) async {
    _urls = _urls.where((x) => x != u).toList();
    await app.store.saveEpgUrls(_urls);
    if (mounted) setState(() {});
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sources EPG')),
        body: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          SwitchListTile(
            title: const Text("EPG du serveur"),
            subtitle: const Text("Utiliser le guide fourni par l'abonnement (Xtream)"),
            value: app.store.get<bool>('epg_server', true),
            onChanged: (v) async {
              await app.store.set('epg_server', v);
              if (mounted) setState(() {});
            },
          ),
          TvField(
            label: 'Ajouter une source EPG (XMLTV)',
            hint: 'https://…/guide.xml ou .xml.gz',
            value: '',
            onChanged: _add,
          ),
          if (!_urls.contains(suggestion))
            ListTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: const Text('Suggestion : guide TV France (gratuit)'),
              subtitle: const Text('xmltvfr.fr — fichier volumineux, à tester'),
              onTap: () => _add(suggestion),
            ),
          for (final u in _urls)
            ListTile(
              leading: const Icon(Icons.rss_feed),
              title: Text(u, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _remove(u),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Mettre à jour maintenant'),
            onTap: () async {
              _snack('Téléchargement du guide…');
              final n = await app.epg.refreshXml();
              _snack(n == 0
                  ? 'Aucun programme récupéré'
                  : '$n chaînes avec programme');
            },
          ),
        ]),
      );
}
