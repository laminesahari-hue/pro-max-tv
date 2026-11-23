import 'package:flutter/widgets.dart';
import '../data/catalog_repository.dart';
import '../data/epg_service.dart';
import '../services/source.dart';
import 'profile.dart';
import 'store.dart';

class AppScope extends InheritedWidget {
  final Source api;
  final CatalogRepository repo;
  final EpgService epg;
  final Store store;
  final Profile profile;
  final void Function(Profile) onActivate;
  final Future<void> Function(Profile) onAdd;
  final Future<void> Function(Profile) onRemove;

  const AppScope({
    super.key,
    required this.api,
    required this.repo,
    required this.epg,
    required this.store,
    required this.profile,
    required this.onActivate,
    required this.onAdd,
    required this.onRemove,
    required super.child,
  });

  static AppScope of(BuildContext c) =>
      c.getInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => false;
}
