import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/serverAuth.dart';
import 'package:budget/struct/serverClient.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/util/debouncer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

Timer? syncTimeoutTimer;
Debouncer backupDebounce = Debouncer(milliseconds: 5000);

bool canSyncData = true;
bool requestSyncDataCancel = false;

CancelableCompleter<bool> syncDataCompleter = CancelableCompleter(onCancel: () {
  requestSyncDataCancel = true;
});

Future<dynamic> cancelAndPreventSyncOperation() async {
  requestSyncDataCancel = true;
  return await syncDataCompleter.operation.cancel();
}

Future<bool> syncDataToServer(BuildContext context) async {
  if (syncDataCompleter.isCompleted) {
    syncDataCompleter = CancelableCompleter(onCancel: () {
      requestSyncDataCancel = true;
    });
  }

  syncDataCompleter.complete(Future.value(_syncDataToServer(context)));
  return syncDataCompleter.operation.value;
}

Future<bool> _syncDataToServer(BuildContext context) async {
  if (canSyncData == false) return false;
  if (appStateSettings["backupSync"] == false) return false;
  if (!ServerAuth.isLoggedIn) return false;

  canSyncData = false;

    try {
      loadingIndeterminateKey.currentState?.setVisibility(true);

      // Upload current database state to server
      final dbDir = await getApplicationDocumentsDirectory();
      final filePath = p.join(dbDir.path, 'db.sqlite');
      final file = File(filePath);

      if (await file.exists()) {
        await ServerClient.uploadFile(
          '/api/sync/upload',
          filePath,
          'file',
          fields: {'deviceId': clientID},
        );
      }

      // Download latest state from server
      final response = await ServerClient.downloadFile('/api/sync/download');
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(p.join(tempDir.path, 'sync_download.sqlite'));
        await tempFile.writeAsBytes(response.bodyBytes);

        // Validate the downloaded file is a valid SQLite database
        final header = await tempFile.openRead(0, 16).first;
        final headerString = String.fromCharCodes(header);
        if (headerString != "SQLite format 3\u0000") {
          throw Exception("Downloaded file is not a valid database");
        }

        // Keep a local backup of the current database in case something goes wrong
        final localBackup = File(p.join(tempDir.path, 'sync_local_backup.sqlite'));
        if (await file.exists()) {
          await file.copy(localBackup.path);
        }

        // Replace current database with downloaded version
        await database.close();
        try {
          await tempFile.copy(filePath);
          await tempFile.delete();
          // Reinitialize database
          database = await constructDb('db');
          await updateSettings("lastSynced", DateTime.now().toString(),
              updateGlobalState: false);
        } catch (e) {
          // Try to restore the local backup if replacement failed
          print("Error replacing database, restoring local backup: " + e.toString());
          if (await localBackup.exists()) {
            await localBackup.copy(filePath);
          }
          database = await constructDb('db');
          rethrow;
        }
      }

      loadingIndeterminateKey.currentState?.setVisibility(false);
      canSyncData = true;
      return true;
    } catch (e) {
      print("Error syncing to server: " + e.toString());
      loadingIndeterminateKey.currentState?.setVisibility(false);
      canSyncData = true;
      return false;
    }
}

Future<bool> createSyncBackup(
    {bool changeMadeSync = false,
    bool changeMadeSyncWaitForDebounce = true}) async {
  if (!ServerAuth.isLoggedIn) return false;
  if (appStateSettings["backupSync"] == false) return false;
  if (changeMadeSync == true && appStateSettings["syncEveryChange"] == false)
    return false;

  if (changeMadeSync == true &&
      (appStateSettings["syncEveryChange"] == true && kIsWeb) &&
      changeMadeSyncWaitForDebounce == true) {
    backupDebounce.run(() {
      createSyncBackup(
          changeMadeSync: true, changeMadeSyncWaitForDebounce: false);
    });
  }

  if (syncTimeoutTimer?.isActive == true) return false;
  syncTimeoutTimer = Timer(Duration(milliseconds: 5000), () {
    syncTimeoutTimer!.cancel();
  });

  try {
    final dbDir = await getApplicationDocumentsDirectory();
    final filePath = p.join(dbDir.path, 'db.sqlite');
    final file = File(filePath);

    if (await file.exists()) {
      await ServerClient.uploadFile(
        '/api/sync/upload',
        filePath,
        'file',
        fields: {'deviceId': clientID},
      );
    }
    return true;
  } catch (e) {
    print("Error creating sync backup: " + e.toString());
    return false;
  }
}

Future<Map<String, dynamic>?> getSyncStatus() async {
  try {
    return await ServerClient.get('/api/sync/status');
  } catch (e) {
    return null;
  }
}
