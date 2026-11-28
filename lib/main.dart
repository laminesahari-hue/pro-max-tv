import 'dart:async';
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
import 'splash_screen.dart';

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
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    final active = widget.store.active;
    if (active != null) _bind(active);

    Timer(const Duration(seconds: 6), () {
      if (mounted) {
        setState(() => _showSplash = false);
      }
    });
  }


  void _bind(Profile p) {
    final api = buildSource(p);
    final repo = CatalogRepository(api, widget.store, p.id);
    final epg = EpgService(widget.store, api);
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
    final list = [...widget.store.profiles.where((x) => x.id != p.id), p];
    await widget.store.saveProfiles(list);
    await _activate(p);
  }

  Future<void> _remove(Profile p) async {
    final list = widget.store.profiles.where((x) => x.id != p.id).toList();
    await widget.store.saveProfiles(list);
    await widget.store.removeProfileData(p.id);
    final next = widget.store.active;
    if (next != null) {
      await widget.store.setActive(next.id);
    }
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
        title: 'TV Max Pro',
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
        builder: (context, child) {
          if (_profile == null || _api == null || _repo == null || _epg == null) {
            return child!;
          }
          return AppScope(
            key: ValueKey(_profile!.id),
            api: _api!,
            repo: _repo!,
            epg: _epg!,
            store: widget.store,
            profile: _profile!,
            onActivate: _activate,
            onAdd: _add,
            onRemove: _remove,
            child: child!,
          );
        },
                home: _showSplash
            ? SplashScreen(
                nextScreen: (_profile == null ||
                        _api == null ||
                        _repo == null ||
                        _epg == null)
                    ? ProfileFormScreen(first: true, onSave: _add)
                    : const Shell(),
              )
            : (_profile == null || _api == null || _repo == null || _epg == null)
                ? ProfileFormScreen(first: true, onSave: _add)
                : const Shell(),

      ),
    );
  }
}
