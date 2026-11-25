import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'core/profile.dart';
import 'core/scope.dart';
import 'core/store.dart';
import 'data/catalog_repository.dart';
import 'data/epg_service.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'services/source.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  final store = await Store.open();
  runApp(ProMaxApp(store: store));
}

class ProMaxApp extends StatefulWidget {
  final Store store;
  const ProMaxApp({super.key, required this.store});

  @override
  State<ProMaxApp> createState() => _ProMaxAppState();
}

class _ProMaxAppState extends State<ProMaxApp> {
  Profile? _profile;
  Source? _api;
  CatalogRepository? _repo;
  EpgService? _epg;

  @override
  void initState() {
    super.initState();
    final active = widget.store.activeProfile;
    if (active != null) _bind(active);
  }

  void _bind(Profile p) {
    final api = buildSource(p);
    final repo = CatalogRepository(api, widget.store);
    final epg = EpgService(api, widget.store);
    _profile = p;
    _api = api;
    _repo = repo;
    _epg = epg;
  }

  Future<void> _activate(Profile p) async {
    await widget.store.setActive(p.id);
    if (mounted) setState(() => _bind(p));
  }

  Future<void> _add(Profile p) async {
    await widget.store.addProfile(p);
    await _activate(p);
  }

  Future<void> _remove(Profile p) async {
    await widget.store.removeProfile(p.id);
    final next = widget.store.activeProfile;
    if (mounted) {
      setState(() {
        if (next == null) {
          _profile = null;
          _api = null;
          _repo = null;
          _epg = null;
        } else {
          _bind(next);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const neonGreen = Color(0xFF69F028);

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select):
            const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA):
            const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            const ActivateIntent(),
      },
      child: MaterialApp(
        title: 'Pro Max TV',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0A0D12),
          colorScheme: ColorScheme.fromSeed(
            seedColor: neonGreen,
            brightness: Brightness.dark,
            primary: neonGreen,
          ),
          focusColor: neonGreen.withOpacity(0.28),
          hoverColor: neonGreen.withOpacity(0.14),
        ),
        home: (_profile == null || _api == null || _repo == null || _epg == null)
            ? ProfileFormScreen(first: true, onSave: _add)
            : AppScope(
                api: _api!,
                repo: _repo!,
                epg: _epg!,
                store: widget.store,
                profile: _profile!,
                onActivate: _activate,
                onAdd: _add,
                onRemove: _remove,
                child: const Shell(),
              ),
      ),
    );
  }
}
