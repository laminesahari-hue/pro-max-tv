import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'data/catalog_repository.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/xtream_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Hive.initFlutter();
  final settings = await Hive.openBox('settings');
  final catalog = await Hive.openBox('catalog');
  runApp(App(settings: settings, catalog: catalog));
}

class App extends StatefulWidget {
  final Box settings, catalog;
  const App({super.key, required this.settings, required this.catalog});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  XtreamService? _service;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    if (s.get('url') != null) {
      _service = XtreamService(
          serverUrl: s.get('url'), username: s.get('user'), password: s.get('pass'));
    }
  }

  Future<void> _onLogin(XtreamService s) async {
    await widget.catalog.clear();
    await widget.settings.putAll(
        {'url': s.serverUrl, 'user': s.username, 'pass': s.password});
    setState(() => _service = s);
  }

  Future<void> _logout() async {
    await widget.settings.deleteAll(['url', 'user', 'pass']);
    await widget.catalog.clear();
    setState(() => _service = null);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Pro Max TV',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: _service == null
            ? LoginScreen(onLoggedIn: _onLogin)
            : HomeScreen(
                api: _service!,
                repo: CatalogRepository(_service!, widget.catalog),
                settings: widget.settings,
                catalog: widget.catalog,
                onLogout: _logout,
              ),
      );
}
