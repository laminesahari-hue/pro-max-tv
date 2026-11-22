import 'package:flutter/widgets.dart';
import '../data/catalog_repository.dart';
import '../services/xtream_service.dart';
import 'store.dart';

class AppScope extends InheritedWidget {
  final XtreamService api;
  final CatalogRepository repo;
  final Store store;
  final VoidCallback onLogout;

  const AppScope({
    super.key,
    required this.api,
    required this.repo,
    required this.store,
    required this.onLogout,
    required super.child,
  });

  static AppScope of(BuildContext c) =>
      c.getInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => false;
}
