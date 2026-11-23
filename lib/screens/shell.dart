import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/models.dart';
import '../core/scope.dart';
import 'browse_screen.dart';
import 'detail_screen.dart';
import 'guide_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

class _Tab {
  final String label;
  final IconData icon;
  final Widget page;
  _Tab(this.label, this.icon, this.page);
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  static bool _auto = false;
  late String _sel;

  @override
  void initState() {
    super.initState();
    final app = AppScope.of(context);
    final start = app.store.get<String>('start_tab', 'home');
    _sel = start == 'home' ? 'Accueil' : 'Live';
    if (start == 'last' && !_auto) {
      _auto = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _resumeLast(app));
    }
  }

  Future<void> _resumeLast(AppScope app) async {
    final recents = app.store.recentLive();
    if (recents.isEmpty || !mounted) return;
    var list = recents;
    try {
      list = await app.repo.items(Kind.live);
    } catch (_) {}
    if (!mounted) return;
    final ok = list.any((c) => c.id == recents.first.id);
    openItem(context, recents.first, channels: ok ? list : recents);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final st = app.store;
    return ValueListenableBuilder(
      valueListenable: st.settings.listenable(),
      builder: (_, __, ___) {
        final tabs = <_Tab>[
          _Tab('Accueil', Icons.home, const HomePage()),
          if (st.get('show_live', true))
            _Tab('Live', Icons.live_tv, const BrowsePage(kind: Kind.live)),
          if (st.get('show_live', true))
            _Tab('Guide', Icons.event_note, const GuidePage()),
          if (st.get('show_vod', true) && app.api.hasVod)
            _Tab('Films', Icons.movie, const BrowsePage(kind: Kind.vod)),
          if (st.get('show_series', true) && app.api.hasSeries)
            _Tab('Séries', Icons.video_library, const BrowsePage(kind: Kind.series)),
          _Tab('Réglages', Icons.settings, const SettingsPage()),
        ];
        var i = tabs.indexWhere((t) => t.label == _sel);
        if (i < 0) i = 0;
        final tick = st.get<int>('refresh', 0);
        final page = KeyedSubtree(
            key: ValueKey('${tabs[i].label}$tick'), child: tabs[i].page);
        void select(int n) => setState(() => _sel = tabs[n].label);

        if (MediaQuery.of(context).size.width >= 720) {
          return Scaffold(
            body: Row(children: [
              NavigationRail(
                selectedIndex: i,
                onDestinationSelected: select,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final t in tabs)
                    NavigationRailDestination(icon: Icon(t.icon), label: Text(t.label)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: SafeArea(child: page)),
            ]),
          );
        }
        return Scaffold(
          body: SafeArea(child: page),
          bottomNavigationBar: NavigationBar(
            selectedIndex: i,
            onDestinationSelected: select,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              for (final t in tabs)
                NavigationDestination(icon: Icon(t.icon), label: t.label),
            ],
          ),
        );
      },
    );
  }
}
