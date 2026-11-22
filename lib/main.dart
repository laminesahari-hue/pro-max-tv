import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'core/scope.dart';
import 'core/store.dart';
import 'data/catalog_repository.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'services/xtream_service.dart';

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
  XtreamService? _api;
  CatalogRepository? _repo;

  @override
  void initState() {
    super.initState();
    final s = widget.store.settings;
    if (s.get('url') != null) {
      _connect(XtreamService(
          serverUrl: s.get('url'), username: s.get('user'), password: s.get('pass')));
    }
  }

  void _connect(XtreamService a) {
    _api = a;
    _repo = CatalogRepository(a, widget.store);
  }

  Future<void> _onLogin(XtreamService s) async {
    final st = widget.store;
    if (st.settings.get('url') != s.serverUrl || st.settings.get('user') != s.username) {
      await st.user.clear(); // autre compte : on repart de zéro
    }
    await st.catalog.clear();
    await st.settings.putAll({'url': s.serverUrl, 'user': s.username, 'pass': s.password});
    setState(() => _connect(s));
  }

  Future<void> _logout() async {
    await widget.store.settings.deleteAll(['url', 'user', 'pass']);
    await widget.store.catalog.clear();
    setState(() {
      _api = null;
      _repo = null;
    });
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
                    store: widget.store,
                    onLogout: _logout,
                    child: child!,
                  ),
            home: _api == null ? LoginScreen(onLoggedIn: _onLogin) : const Shell(),
          );
        },
      );
}
