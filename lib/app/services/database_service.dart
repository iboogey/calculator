import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../data/providers/app_database.dart';

/// Owns the open database and tells listeners when its data changes.
class DatabaseService extends GetxService {
  DatabaseService({this.factory, this.path});

  final DatabaseFactory? factory;
  final String? path;

  late final Database db;

  /// Bumped after every committed write. Controllers reload with
  /// `ever(database.revision, (_) => load())`.
  final revision = 0.obs;

  Future<DatabaseService> init() async {
    db = await AppDatabase.open(factory: factory, path: path);
    return this;
  }

  void notifyChanged() => revision.value++;

  @override
  void onClose() {
    db.close();
    super.onClose();
  }
}
