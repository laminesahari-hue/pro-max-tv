import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'core/profile.dart';
import 'core/scope.dart';
import 'core/store.dart';
import 'data/catalog_repository.dart';
import 'data/epg_service.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'services/source.dart';

const accents = [
  Color(0xFFE50914),
  Color(0xFF2979FF),
  Color(0xFF00C853),
  Color(0xFFFF9100),
  Color(0xFF9C27B0),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final store = await Store.open();
  runApp(App(store: store));
}

class App extends StatefulWidget {
  final Store store;
  const App({super.key, required this.store});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  Source? _api;
  CatalogRepository? _repo;
  EpgService? _epg;
  Profile? _profile;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    final p = widget.store.active;
    if (p != null) _activate(p, notify: false);
  }

  void _activate(Profile p, {bool notify = true}) {
    final st = widget.store;
    st.setActive(p.id);
    final a = buildSource(p);
    final repo = CatalogRepository(a, st, p.id);
    final epg = EpgService(st, a);
    epg.init();
    void apply() {
      _profile = p;
      _api = a;
      _repo = repo;
      _epg = epg;
    }

    if (notify) {
      setState(apply);
    } else {
      apply();
    }
  }

  Future<void> _add(Profile p) async {
    final l = widget.store.profiles.where((x) => x.id != p.id).toList()..add(p);
    await widget.store.saveProfiles(l);
    _activate(p);
  }

  Future<void> _remove(Profile p) async {
    final st = widget.store;
    final l = st.profiles.where((x) => x.id != p.id).toList();
    await st.saveProfiles(l);
    await st.removeProfileData(p.id);
    if (_profile?.id != p.id) return;
    if (l.isEmpty) {
      await st.settings.delete('active');
      setState(() {
        _profile = null;
        _api = null;
        _repo = null;
        _epg = null;
      });
    } else {
      _activate(l.first);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: widget.store.settings.listenable(keys: ['accent']),
        builder: (_, __, ___) {
          final accent = accents[widget.store.get<int>('accent', 0)];
          final nextScreen = _api == null
              ? ProfileFormScreen(first: true, onSave: _add)
              : Shell(key: ValueKey(_profile!.id));

                    return MaterialApp(
            title: 'TV MAX PRO',
            debugShowCheckedModeBanner: false,
            shortcuts: <ShortcutActivator, Intent>{
              ...WidgetsApp.defaultShortcuts,
              const SingleActivator(LogicalKeyboardKey.select):
                  const ActivateIntent(),
              const SingleActivator(LogicalKeyboardKey.enter):
                  const ActivateIntent(),
              const SingleActivator(LogicalKeyboardKey.numpadEnter):
                  const ActivateIntent(),
              const SingleActivator(LogicalKeyboardKey.gameButtonA):
                  const ActivateIntent(),
            },
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              colorSchemeSeed: accent,
              scaffoldBackgroundColor: const Color(0xFF0B0D12),
              focusColor: const Color(0xFF69F028).withValues(alpha: 0.38),
              hoverColor: const Color(0xFF69F028).withValues(alpha: 0.25),
              highlightColor: const Color(0xFF69F028).withValues(alpha: 0.30),
              cardTheme: CardThemeData(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              listTileTheme: ListTileThemeData(
                selectedTileColor:
                    const Color(0xFF69F028).withValues(alpha: 0.22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            builder: (ctx, child) => _api == null
                ? child!
                : AppScope(
                    api: _api!,
                    repo: _repo!,
                    epg: _epg!,
                    store: widget.store,
                    profile: _profile!,
                    onActivate: _activate,
                    onAdd: _add,
                    onRemove: _remove,
                    child: child!,
                  ),
            home: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: _showSplash
                  ? _SplashScreen(
                      key: const ValueKey('splash'),
                      accent: accent,
                      onFinished: () {
                        if (mounted) setState(() => _showSplash = false);
                      },
                    )
                  : nextScreen,
            ),
          );
        },
      );
}

class _SplashScreen extends StatefulWidget {
  final Color accent;
  final VoidCallback onFinished;

  const _SplashScreen({
    super.key,
    required this.accent,
    required this.onFinished,
  });

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _lineWidth;
  late final Animation<double> _subOpacity;
  late final Animation<Offset> _subSlide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _scale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
      ),
    );

    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
      ),
    );

    _lineWidth = Tween<double>(begin: 0.0, end: 260.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.25, 0.75, curve: Curves.easeInOutCubic),
      ),
    );

    _subOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.55, 0.90, curve: Curves.easeOut),
      ),
    );

    _subSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.55, 0.90, curve: Curves.easeOutCubic),
      ),
    );

    _ctrl.forward();

    Future.delayed(const Duration(milliseconds: 2800), () {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D12),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.85,
            colors: [
              widget.accent.withOpacity(0.18),
              const Color(0xFF0B0D12),
            ],
          ),
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Opacity(
                  opacity: _titleOpacity.value,
                  child: Transform.scale(
                    scale: _scale.value,
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                          color: Colors.white,
                        ),
                        children: [
                          const TextSpan(text: 'TV MAX '),
                          TextSpan(
                            text: 'PRO',
                            style: TextStyle(
                              color: widget.accent,
                              shadows: [
                                Shadow(
                                  color: widget.accent.withOpacity(0.75),
                                  blurRadius: 24,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: _lineWidth.value,
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        widget.accent,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Opacity(
                  opacity: _subOpacity.value,
                  child: FractionalTranslation(
                    translation: _subSlide.value,
                    child: const Text(
                      'BY L S',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 10,
                        color: Color(0xFF8A99AD),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
