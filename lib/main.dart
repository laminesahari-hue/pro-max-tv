import 'package:flutter/material.dart';
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
          return MaterialApp(
            title: 'Pro Max TV',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              colorSchemeSeed: accent,
              scaffoldBackgroundColor: const Color(0xFF0B0D12),
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
            home: _api == null
                ? ProfileFormScreen(first: true, onSave: _add)
                : Shell(key: ValueKey(_profile!.id)),
          );
        },
      );
}
