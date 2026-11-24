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
    _sel = start == 'home' ? 'Accueil' : 'TV Live';
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
    final accent = Theme.of(context).colorScheme.primary;

    return ValueListenableBuilder(
      valueListenable: st.settings.listenable(),
      builder: (_, __, ___) {
        final tabs = <_Tab>[
          _Tab('Accueil', Icons.home_rounded, const HomePage()),
          if (st.get('show_live', true))
            _Tab('TV Live', Icons.live_tv_rounded, const BrowsePage(kind: Kind.live)),
          if (st.get('show_live', true))
            _Tab('Guide', Icons.event_note_rounded, const GuidePage()),
          if (st.get('show_vod', true) && app.api.hasVod)
            _Tab('Films', Icons.movie_rounded, const BrowsePage(kind: Kind.vod)),
          if (st.get('show_series', true) && app.api.hasSeries)
            _Tab('Séries', Icons.video_library_rounded, const BrowsePage(kind: Kind.series)),
          _Tab('Réglages', Icons.settings_rounded, const SettingsPage()),
        ];

        var i = tabs.indexWhere((t) => t.label == _sel);
        if (i < 0) i = 0;

        final tick = st.get<int>('refresh', 0);
        final page = KeyedSubtree(
          key: ValueKey('${tabs[i].label}$tick'),
          child: tabs[i].page,
        );

        void select(int n) => setState(() => _sel = tabs[n].label);

        return Scaffold(
          backgroundColor: const Color(0xFF0B0D12),
          body: SafeArea(
            child: Column(
              children: [
                _TopNavBar(
                  tabs: tabs,
                  selectedIndex: i,
                  accent: accent,
                  onSelect: select,
                ),
                Expanded(child: page),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TopNavBar extends StatelessWidget {
  final List<_Tab> tabs;
  final int selectedIndex;
  final Color accent;
  final ValueChanged<int> onSelect;

  const _TopNavBar({
    required this.tabs,
    required this.selectedIndex,
    required this.accent,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 720;

    return Container(
      height: isWide ? 64 : 56,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF10131C),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.08), width: 1),
        ),
      ),
      child: Row(
        children: [
          if (isWide) ...[
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
                children: [
                  const TextSpan(text: 'TV MAX '),
                  TextSpan(text: 'PRO', style: TextStyle(color: accent)),
                ],
              ),
            ),
            const SizedBox(width: 28),
          ],
          Expanded(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tabs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final tab = tabs[idx];
                  final selected = idx == selectedIndex;
                  return _TopNavItem(
                    label: tab.label,
                    icon: tab.icon,
                    selected: selected,
                    accent: accent,
                    onTap: () => onSelect(idx),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopNavItem extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _TopNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_TopNavItem> createState() => _TopNavItemState();
}

class _TopNavItemState extends State<_TopNavItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _focused;

    return Center(
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (f) => setState(() => _focused = f),
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: widget.selected
                ? widget.accent.withOpacity(0.22)
                : _focused
                    ? Colors.white.withOpacity(0.12)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _focused
                  ? widget.accent
                  : widget.selected
                      ? widget.accent.withOpacity(0.6)
                      : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 19,
                color: active ? Colors.white : Colors.white70,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? Colors.white : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
