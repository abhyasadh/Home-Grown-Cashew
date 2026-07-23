// web.dart
import 'dart:typed_data';
import 'package:budget/database/binary_string_conversion.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:drift/wasm.dart';
import 'package:drift/drift.dart';
import 'package:budget/database/tables.dart';
import 'package:universal_html/html.dart' as html;

Future<FinanceDatabase> constructDb(String dbName,
    {Uint8List? initialDataWeb}) async {
  final result = await WasmDatabase.open(
    databaseName: dbName,
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.dart.js'),
    initializeDatabase: initialDataWeb != null ? () => initialDataWeb : null,
  );
  if (result.missingFeatures.isNotEmpty) {
    print('Using ${result.chosenImplementation} due to missing browser '
        'features: ${result.missingFeatures}');
  }
  return FinanceDatabase(result.resolvedExecutor);
}

Future<DBFileInfo> getCurrentDBFileInfo() async {
  Uint8List dbFileBytes;
  late Stream<List<int>> mediaStream;

  try {
    final result = await WasmDatabase.open(
      databaseName: 'db_temp_backup',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.dart.js'),
    );
    await result.resolvedExecutor.close();
  } catch (_) {}

  final html.Storage localStorage = html.window.localStorage;
  dbFileBytes = bin2str.decode(localStorage["moor_db_str_db"] ?? "");
  mediaStream = Stream.value(dbFileBytes);

  return DBFileInfo(dbFileBytes, mediaStream);
}

Future overwriteDefaultDB(Uint8List dataStore) async {
  final html.Storage localStorage = html.window.localStorage;
  localStorage.clear();
  localStorage["moor_db_str_db"] =
      bin2str.encode(Uint8List.fromList(dataStore));
  // we need to be able to sync with others after the restore
  await sharedPreferences.setString("dateOfLastSyncedWithClient", "{}");
}
