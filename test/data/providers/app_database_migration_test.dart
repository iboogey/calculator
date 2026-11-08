import 'dart:io';

import 'package:calculator/app/data/providers/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

const _debtTables = [
  'debt_people',
  'debt_entries',
  'obligations',
  'obligation_payments',
];

Future<List<String>> _tableNames(Database db) async => (await db.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'table'",
    ))
        .map((r) => r['name'] as String)
        .toList();

void main() {
  test('fresh database has the debt tables', () async {
    final db = (await openTestDatabase()).db;
    expect(await _tableNames(db), containsAll(_debtTables));
    expect(AppDatabase.version, 2);
  });

  test('upgrading a version-1 database keeps its data and adds the debt tables',
      () async {
    sqfliteFfiInit();
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = p.join(dir.path, 'v1.db');

    final v1 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final s in AppDatabase.schemaV1) {
            await db.execute(s);
          }
          await db.insert('categories', {
            'name': 'طعام',
            'icon_key': 'food',
            'color_value': 0,
            'kind': 'expense',
          });
          await db.insert('transactions', {
            'kind': 'expense',
            'amount': 5000,
            'category_id': 1,
            'date': '2026-11-01',
            'created_at': 0,
          });
        },
      ),
    );
    expect(await _tableNames(v1), isNot(contains('debt_people')));
    await v1.close();

    final db =
        await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    addTearDown(db.close);
    expect(await db.query('transactions'), hasLength(1));
    expect(await _tableNames(db), containsAll(_debtTables));
    expect(
      (await db.rawQuery('PRAGMA user_version')).single['user_version'],
      2,
    );
  });

  test('deleting a person cascades to their entries', () async {
    final db = (await openTestDatabase()).db;
    final id = await db.insert('debt_people', {'name': 'أحمد', 'created_at': 0});
    await db.insert('debt_entries', {
      'person_id': id,
      'amount': 1000,
      'date': '2026-11-01',
      'created_at': 0,
    });
    await db.delete('debt_people', where: 'id = ?', whereArgs: [id]);
    expect(await db.query('debt_entries'), isEmpty);
  });

  test('deleting a transaction clears payment.transaction_id', () async {
    final db = (await openTestDatabase()).db;
    final txId = await db.insert('transactions', {
      'kind': 'expense',
      'amount': 1000,
      'category_id': 1,
      'date': '2026-11-01',
      'created_at': 0,
    });
    final obId = await db.insert(
        'obligations', {'title': 'إيجار', 'amount': 1000, 'created_at': 0});
    await db.insert('obligation_payments', {
      'obligation_id': obId,
      'amount': 1000,
      'date': '2026-11-01',
      'transaction_id': txId,
      'created_at': 0,
    });
    await db.delete('transactions', where: 'id = ?', whereArgs: [txId]);
    final payment = (await db.query('obligation_payments')).single;
    expect(payment['transaction_id'], isNull);
  });
}
