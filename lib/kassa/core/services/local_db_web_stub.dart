// Web stub for sqflite types
class Database {
  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async => [];
  Future<int> insert(
    String table,
    Map<String, dynamic> values, {
    ConflictAlgorithm? conflictAlgorithm,
  }) async => 0;
  Future<int> delete(String table) async => 0;
  Future<void> execute(String sql) async {}
  Future<void> transaction(Future<void> Function(Database txn) action) async {}
}

enum ConflictAlgorithm { replace, abort, fail, ignore, rollback }

Future<String> getDatabasesPath() async => '';
Future<Database> openDatabase(
  String path, {
  int? version,
  dynamic onCreate,
  dynamic onUpgrade,
}) async => Database();
String join(String a, String b) => '$a/$b';
