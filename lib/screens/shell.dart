import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/models.dart';
import '../core/scope.dart';
import 'browse_screen.dart';
import 'detail_screen.dart';
import 'guide_screen.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class _Tab {
  final String label;
  final Widget page;
  _Tab(this.label, this.page);
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  static bool _auto = false;
  late String _sel;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final app = AppScope.of(context);
      final start = app.store.get<String>('start_tab', 'home');
      _sel = start == 'home' ? 'Accueil' : 'TV Live';
      if (start == 'last' && !_auto) {
        _auto = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _resumeLast(app));
      }
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
    const neonGreen = Color(0xFF69F028);

    return ValueListenableBuilder(
      valueListenable: st.settings.listenable(),
      builder: (_, __, ___) {
        final tabs = <_Tab>[
          _Tab('Accueil', const HomePage()),
          if (st.get('show_live', true))
            _Tab('TV Live', const BrowsePage(kind: Kind.live)),
          if (st.get('show_live', true))
            _Tab('Guide', const GuidePage()),
          if (st.get('show_vod', true) && app.api.hasVod)
            _Tab('Films', const BrowsePage(kind: Kind.vod)),
          if (st.get('show_series', true) && app.api.hasSeries)
            _Tab('Séries', const BrowsePage(kind: Kind.series)),
        ];

        final isSettings = _sel == 'Réglages';
        var i = tabs.indexWhere((t) => t.label == _sel);
        if (i < 0) i = 0;

        final tick = st.get<int>('refresh', 0);
        final page = isSettings
            ? KeyedSubtree(
                key: ValueKey('Réglages$tick'),
                child: const SettingsPage(),
              )
            : KeyedSubtree(
                key: ValueKey('${tabs[i].label}$tick'),
                child: tabs[i].page,
              );

        return Scaffold(
          backgroundColor: const Color(0xFF0A0D12),
          body: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: (!isSettings && tabs[i].label == 'Accueil') ? 0 : 72,
                  ),
                  child: page,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: _FloatingTopBar(
                    tabs: tabs,
                    selectedLabel: _sel,
                    accent: neonGreen,
                    onSelectLabel: (lbl) => setState(() => _sel = lbl),
                    onSearch: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Recherche')),
                          body: const SearchPage(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FloatingTopBar extends StatelessWidget {
  final List<_Tab> tabs;
  final String selectedLabel;
  final Color accent;
  final ValueChanged<String> onSelectLabel;
  final VoidCallback onSearch;

  const _FloatingTopBar({
    required this.tabs,
    required this.selectedLabel,
    required this.accent,
    required this.onSelectLabel,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 680;

    return Container(
      height: 68,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 32 : 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.80),
            Colors.black.withOpacity(0.35),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: Colors.white,
              ),
              children: [
                TextSpan(text: 'PRO', style: TextStyle(color: accent)),
                const TextSpan(text: 'MAX'),
                TextSpan(text: 'TV', style: TextStyle(color: accent)),
              ],
            ),
          ),
          const Spacer(),
          Flexible(
            flex: 4,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final t in tabs) ...[
                    _NavTabPill(
                      label: t.label,
                      selected: selectedLabel == t.label,
                      accent: accent,
                      onTap: () => onSelectLabel(t.label),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          const Spacer(),
          _CircleActionBtn(
            icon: Icons.search_rounded,
            accent: accent,
            selected: false,
            onTap: onSearch,
          ),
          const SizedBox(width: 10),
          _CircleActionBtn(
            icon: Icons.person_outline_rounded,
            accent: accent,
            selected: selectedLabel == 'Réglages',
            onTap: () => onSelectLabel('Réglages'),
          ),
        ],
      ),
    );
  }
}

class _NavTabPill extends StatefulWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _NavTabPill({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_NavTabPill> createState() => _NavTabPillState();
}

class _NavTabPillState extends State<_NavTabPill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      onFocusChange: (f) => setState(() => _focused = f),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        decoration: BoxDecoration(
          color: widget.selected
              ? Colors.white.withOpacity(0.18)
              : _focused
                  ? widget.accent.withOpacity(0.22)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _focused ? widget.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: (widget.selected || _focused)
                ? FontWeight.w700
                : FontWeight.w500,
            color: (widget.selected || _focused) ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _CircleActionBtn extends StatefulWidget {
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  const _CircleActionBtn({
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_CircleActionBtn> createState() => _CircleActionBtnState();
}

class _CircleActionBtnState extends State<_CircleActionBtn> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      onFocusChange: (f) => setState(() => _focused = f),
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.selected
              ? widget.accent.withOpacity(0.28)
              : Colors.white.withOpacity(0.14),
          border: Border.all(
            color: (_focused || widget.selected)
                ? widget.accent
                : Colors.white24,
            width: 1.5,
          ),
        ),
        child: Icon(widget.icon, color: Colors.white, size: 20),
      ),
    );
  }
}
