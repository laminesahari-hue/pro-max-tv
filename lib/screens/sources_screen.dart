import 'package:flutter/material.dart';
import '../core/profile.dart';
import '../core/scope.dart';
import '../widgets/tv_field.dart';
import '../widgets/tv_settings_items.dart';
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

  Future<void> _onSourceTap(Profile p) async {
    final isCurrent = p.id == app.profile.id;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(p.name),
        children: [
          if (!isCurrent)
            TvNavTile(
              autofocus: true,
              icon: Icons.check_circle_outline,
              title: 'Activer cette source',
              onTap: () => Navigator.pop(ctx, 'activate'),
            ),
          TvNavTile(
            autofocus: isCurrent,
            icon: Icons.delete_outline,
            title: 'Supprimer cette source',
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    );
    if (action == 'activate') {
      app.onActivate(p);
      _toRoot();
    } else if (action == 'delete') {
      await _delete(p);
    }
  }

  Future<void> _delete(Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette source ?'),
        content: Text('${p.name} et ses favoris seront supprimés.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
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
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          for (var i = 0; i < list.length; i++)
            TvNavTile(
              autofocus: i == 0,
              icon: list[i].id == app.profile.id
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              title: list[i].name,
              subtitle: list[i].id == app.profile.id
                  ? '${list[i].typeLabel} • Active (OK pour options)'
                  : list[i].typeLabel,
              onTap: () => _onSourceTap(list[i]),
            ),
          TvNavTile(
            autofocus: list.isEmpty,
            icon: Icons.add_circle_outline,
            title: 'Ajouter une source',
            subtitle: 'Xtream Codes, M3U ou portail MAG',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileFormScreen(onSave: (p) async {
                  await app.onAdd(p);
                  if (mounted) _toRoot();
                }),
              ),
            ),
          ),
          if (!hasFree)
            TvNavTile(
              icon: Icons.live_tv,
              title: 'Ajouter les chaînes gratuites',
              subtitle: 'France 24, Al Jazeera…',
              onTap: () async {
                await app.onAdd(const Profile(
                    id: 'free', name: 'Chaînes gratuites', type: 'free'));
                if (mounted) _toRoot();
              },
            ),
        ],
      ),
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
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            TvSwitchTile(
              title: 'EPG du serveur',
              subtitle:
                  "Utiliser le guide fourni par l'abonnement (Xtream)",
              value: app.store.get<bool>('epg_server', true),
              onChanged: (v) async {
                await app.store.set('epg_server', v);
                if (mounted) setState(() {});
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: TvField(
                label: 'Ajouter une source EPG (XMLTV)',
                hint: 'https://…/guide.xml ou .xml.gz',
                value: '',
                onChanged: _add,
              ),
            ),
            if (!_urls.contains(suggestion))
              TvNavTile(
                icon: Icons.lightbulb_outline,
                title: 'Suggestion : guide TV France (gratuit)',
                subtitle: 'xmltvfr.fr — fichier volumineux, à tester',
                onTap: () => _add(suggestion),
              ),
            for (final u in _urls)
              TvNavTile(
                icon: Icons.rss_feed,
                title: u,
                subtitle: 'Appuyez sur OK pour supprimer',
                onTap: () => _remove(u),
              ),
            TvNavTile(
              icon: Icons.refresh,
              title: 'Mettre à jour maintenant',
              onTap: () async {
                _snack('Téléchargement du guide…');
                final n = await app.epg.refreshXml();
                _snack(n == 0
                    ? 'Aucun programme récupéré'
                    : '$n chaînes avec programme');
              },
            ),
          ],
        ),
      );
}
