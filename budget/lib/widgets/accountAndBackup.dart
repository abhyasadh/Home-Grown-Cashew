import 'dart:async';
import 'dart:io';

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/accountsPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/serverAuth.dart';
import 'package:budget/struct/serverClient.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/syncClient.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/restartApp.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

Future<bool> checkConnection() async {
  late bool isConnected;
  if (!kIsWeb) {
    try {
      final result = await InternetAddress.lookup('example.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        isConnected = true;
      }
    } on SocketException catch (e) {
      print(e.toString());
      isConnected = false;
    }
  } else {
    isConnected = true;
  }
  return isConnected;
}

Future<bool> signInAndSync({BuildContext? context}) async {
  if (!ServerAuth.isLoggedIn) return false;
  try {
    await syncDataToServer(context ?? navigatorKey.currentContext!);
    await createBackupInBackground(context ?? navigatorKey.currentContext!);
    return true;
  } catch (e) {
    print("Error signing in and syncing: " + e.toString());
    return false;
  }
}

Future<void> signOutServer() async {
  await ServerAuth.logout();
  settingsPageStateKey.currentState?.refreshState();
  sidebarStateKey.currentState?.refreshState();
}

Future<bool> createBackup(BuildContext? context,
    {bool silentBackup = false,
    bool deleteOldBackups = true,
    String? clientIDForSync}) async {
  if (!ServerAuth.isLoggedIn) return false;

  try {
    final dbDir = await getApplicationDocumentsDirectory();
    final filePath = p.join(dbDir.path, 'db.sqlite');
    final file = File(filePath);

    if (!await file.exists()) return false;

    String deviceName = clientIDForSync ?? clientID;
    String backupName = "backup-${DateTime.now().millisecondsSinceEpoch}";

    await ServerClient.uploadFile(
      '/api/backups',
      filePath,
      'file',
      fields: {
        'name': backupName,
        'deviceName': deviceName,
        'schemaVersion': schemaVersionGlobal.toString(),
      },
    );

    await updateSettings("lastBackup", DateTime.now().toString(),
        updateGlobalState: false);

    if (silentBackup != true) {
      openSnackbar(SnackbarMessage(
        title: "backup-created".tr(),
      ));
    }

    return true;
  } catch (e) {
    print("Error creating backup: " + e.toString());
    if (silentBackup != true) {
      openSnackbar(SnackbarMessage(
        title: "backup-error".tr(),
      ));
    }
    return false;
  }
}

Future<bool> createBackupInBackground(BuildContext context) async {
  if (!ServerAuth.isLoggedIn) return false;
  if (appStateSettings["autoBackups"] == false) return false;

  DateTime lastBackup = DateTime.tryParse(
          appStateSettings["lastBackup"] ?? "") ??
      DateTime.now().subtract(Duration(days: 10));
  int frequencyDays = appStateSettings["autoBackupsFrequency"] ?? 3;

  if (DateTime.now().difference(lastBackup).inDays >= frequencyDays) {
    return await createBackup(context, silentBackup: true);
  }
  return false;
}

Future<List<Map<String, dynamic>>> getDriveFiles() async {
  if (!ServerAuth.isLoggedIn) return [];
  try {
    final result = await ServerClient.get('/api/backups');
    final backups = result['backups'] as List<dynamic>? ?? [];
    return backups.cast<Map<String, dynamic>>();
  } catch (e) {
    print("Error getting drive files: " + e.toString());
    return [];
  }
}

Future<bool> deleteBackup(String backupId) async {
  if (!ServerAuth.isLoggedIn) return false;
  try {
    await ServerClient.delete('/api/backups/$backupId');
    return true;
  } catch (e) {
    print("Error deleting backup: " + e.toString());
    return false;
  }
}

Future<bool> loadBackup(String backupId, BuildContext context) async {
  if (!ServerAuth.isLoggedIn) return false;
  try {
    loadingIndeterminateKey.currentState?.setVisibility(true);

    final response = await ServerClient.downloadFile('/api/backups/$backupId');
    if (response.statusCode != 200) {
      loadingIndeterminateKey.currentState?.setVisibility(false);
      return false;
    }

    final dbDir = await getApplicationDocumentsDirectory();
    final filePath = p.join(dbDir.path, 'db.sqlite');

    await database.close();
    final file = File(filePath);
    await file.writeAsBytes(response.bodyBytes);

    database = await constructDb('db');

    await updateSettings("databaseJustImported", true,
        updateGlobalState: false);

    loadingIndeterminateKey.currentState?.setVisibility(false);

    openSnackbar(SnackbarMessage(
      title: "backup-restored".tr(),
    ));

    RestartApp.restartApp(context);
    return true;
  } catch (e) {
    print("Error loading backup: " + e.toString());
    loadingIndeterminateKey.currentState?.setVisibility(false);
    return false;
  }
}

Future<void> chooseBackup(BuildContext context,
    {bool isManaging = false, bool isClientSync = false}) async {
  if (!ServerAuth.isLoggedIn) return;

  List<Map<String, dynamic>> backups = await getDriveFiles();

  if (backups.isEmpty) {
    openSnackbar(SnackbarMessage(
      title: "no-backups".tr(),
    ));
    return;
  }

  openBottomSheet(
    context,
    PopupFramework(
      title: isManaging ? "manage-backups".tr() : "restore-backup".tr(),
      child: Column(
        children: [
          for (var backup in backups)
            Tappable(
              onTap: () async {
                if (isManaging) {
                  bool? confirm = await openPopup(
                    context,
                    title: "delete-backup-confirm".tr(),
                    onSubmit: () {
                      Navigator.pop(context, true);
                    },
                    onCancel: () {
                      Navigator.pop(context, false);
                    },
                    onSubmitLabel: "delete".tr(),
                    onCancelLabel: "cancel".tr(),
                  );
                  if (confirm == true) {
                    await deleteBackup(backup['id']);
                    Navigator.pop(context);
                    openSnackbar(SnackbarMessage(
                      title: "backup-deleted".tr(),
                    ));
                  }
                } else {
                  await loadBackup(backup['id'], context);
                  Navigator.pop(context);
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFont(
                            text: backup['name'] ?? 'Unknown',
                            fontWeight: FontWeight.bold,
                          ),
                          TextFont(
                            text: backup['createdAt'] ?? '',
                            fontSize: 12,
                          ),
                        ],
                      ),
                    ),
                    if (isManaging)
                      Icon(Icons.delete, color: Colors.red),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class ServerLoginButton extends StatelessWidget {
  const ServerLoginButton({
    Key? key,
    this.isOutlined = false,
    this.description,
  }) : super(key: key);

  final bool isOutlined;
  final String? description;

  @override
  Widget build(BuildContext context) {
    bool isLoggedIn = ServerAuth.isLoggedIn;
    String? username = ServerAuth.currentUsername;

    String title = isLoggedIn
        ? (username ?? "server-connected".tr())
        : "server-login".tr();
    String? subtitle = isLoggedIn
        ? (appStateSettings["serverUrl"] ?? "")
        : (description ?? "server-login-description".tr());
    IconData icon = isLoggedIn
        ? (appStateSettings["outlinedIcons"]
            ? Icons.cloud_done_outlined
            : Icons.cloud_done_rounded)
        : (appStateSettings["outlinedIcons"]
            ? Icons.cloud_outlined
            : Icons.cloud_rounded);

    return SettingsContainer(
      title: title,
      description: isOutlined ? null : subtitle,
      icon: icon,
      isOutlined: isOutlined,
      onTap: () {
        if (isLoggedIn) {
          if (getIsFullScreen(context)) {
            sidebarStateKey.currentState?.setSelectedIndex(8);
          } else {
            pushRoute(context, AccountsPage(key: accountsPageStateKey));
          }
        } else {
          openServerLoginPopup(context);
        }
      },
    );
  }
}

String? validateServerUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return "server-url-required".tr();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.isScheme("http") && !uri.isScheme("https")) {
    return "server-url-invalid".tr();
  }
  return null;
}

Future<void> openServerLoginPopup(
  BuildContext context, {
  VoidCallback? onLoginSuccess,
}) async {
  String initialUrl = appStateSettings["serverUrl"] ?? "";
  if (initialUrl.isEmpty && kIsWeb) {
    try {
      initialUrl = Uri.base.origin;
    } catch (_) {}
  }
  final serverUrlController = TextEditingController(text: initialUrl);
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  bool isTestingConnection = false;
  bool isRegister = false;
  String? errorMessage;

  openBottomSheet(
    context,
    popupWithKeyboard: true,
    PopupFramework(
      title: "server-login".tr(),
      subtitle: "server-login-subtitle".tr(),
      child: StatefulBuilder(
        builder: (context, setState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 8),
              TextInput(
                padding: EdgeInsetsDirectional.zero,
                startContentPadding: 12,
                controller: serverUrlController,
                labelText: "server-url".tr(),
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.link_outlined
                    : Icons.link_rounded,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                onChanged: (value) {
                  if (errorMessage != null) {
                    setState(() => errorMessage = null);
                  }
                },
              ),
              SizedBox(height: 12),
              TextInput(
                padding: EdgeInsetsDirectional.zero,
                startContentPadding: 12,
                controller: usernameController,
                labelText: "username".tr(),
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.person_outlined
                    : Icons.person_rounded,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                onChanged: (value) {
                  if (errorMessage != null) {
                    setState(() => errorMessage = null);
                  }
                },
              ),
              SizedBox(height: 12),
              TextInput(
                padding: EdgeInsetsDirectional.zero,
                startContentPadding: 12,
                controller: passwordController,
                labelText: "password".tr().capitalizeFirst,
                obscureText: true,
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.lock_outlined
                    : Icons.lock_rounded,
                textInputAction: TextInputAction.done,
                onSubmitted: (value) {
                  // Trigger login on keyboard done
                },
                onChanged: (value) {
                  if (errorMessage != null) {
                    setState(() => errorMessage = null);
                  }
                },
              ),
              if (errorMessage != null) ...[
                SizedBox(height: 10),
                TextFont(
                  text: errorMessage!,
                  fontSize: 13,
                  textColor: Theme.of(context).colorScheme.error,
                  maxLines: 5,
                ),
              ],
              SizedBox(height: 16),
              Button(
                label: isTestingConnection
                    ? "loading".tr()
                    : "test-connection".tr(),
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.network_check_outlined
                    : Icons.network_check_rounded,
                onTap: isTestingConnection || isLoading
                    ? () {}
                    : () async {
                        final urlError = validateServerUrl(
                            serverUrlController.text);
                        if (urlError != null) {
                          setState(() => errorMessage = urlError);
                          return;
                        }
                        setState(() {
                          isTestingConnection = true;
                          errorMessage = null;
                        });
                        final reachable = await ServerAuth.testConnection(
                            serverUrlController.text.trim());
                        setState(() => isTestingConnection = false);
                        openSnackbar(SnackbarMessage(
                          title: reachable
                              ? "server-reachable".tr()
                              : "server-unreachable".tr(),
                        ));
                      },
              ),
              SizedBox(height: 12),
              Button(
                label: isLoading
                    ? "loading".tr()
                    : (isRegister
                        ? "register".tr()
                        : "login".tr()),
                icon: isRegister
                    ? (appStateSettings["outlinedIcons"]
                        ? Icons.person_add_outlined
                        : Icons.person_add_rounded)
                    : (appStateSettings["outlinedIcons"]
                        ? Icons.login_outlined
                        : Icons.login_rounded),
                onTap: isLoading || isTestingConnection
                    ? () {}
                    : () async {
                        final urlError = validateServerUrl(
                            serverUrlController.text);
                        if (urlError != null) {
                          setState(() => errorMessage = urlError);
                          return;
                        }
                        if (usernameController.text.trim().isEmpty) {
                          setState(() =>
                              errorMessage = "username-required".tr());
                          return;
                        }
                        if (passwordController.text.isEmpty) {
                          setState(() =>
                              errorMessage = "password-required".tr());
                          return;
                        }

                        setState(() {
                          isLoading = true;
                          errorMessage = null;
                        });
                        final result = isRegister
                            ? await ServerAuth.register(
                                serverUrlController.text.trim(),
                                usernameController.text.trim(),
                                passwordController.text,
                              )
                            : await ServerAuth.login(
                                serverUrlController.text.trim(),
                                usernameController.text.trim(),
                                passwordController.text,
                              );
                        setState(() => isLoading = false);

                        if (result.success) {
                          Navigator.pop(context);
                          openSnackbar(SnackbarMessage(
                            title: "login-success".tr(),
                          ));
                          refreshUIAfterLoginChange();
                          onLoginSuccess?.call();
                        } else {
                          setState(() => errorMessage =
                              result.errorMessage ??
                                  (isRegister
                                      ? "register-error".tr()
                                      : "login-error".tr()));
                        }
                      },
              ),
              SizedBox(height: 14),
              Center(
                child: Tappable(
                  borderRadius: 10,
                  onTap: isLoading || isTestingConnection
                      ? () {}
                      : () {
                          setState(() {
                            isRegister = !isRegister;
                            errorMessage = null;
                          });
                        },
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 12, vertical: 6),
                    child: TextFont(
                      text: isRegister
                          ? "already-have-account".tr()
                          : "no-account-register".tr(),
                      fontSize: 14,
                      textColor:
                          Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

void refreshUIAfterLoginChange() {
  sidebarStateKey.currentState?.refreshState();
  settingsPageStateKey.currentState?.refreshState();
}

class BackupManagement extends StatefulWidget {
  const BackupManagement({Key? key}) : super(key: key);

  @override
  State<BackupManagement> createState() => _BackupManagementState();
}

class _BackupManagementState extends State<BackupManagement> {
  List<Map<String, dynamic>> backups = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => isLoading = true);
    backups = await getDriveFiles();
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsContainer(
          title: "backup-sync".tr(),
          description: "backup-sync-description".tr(),
          onTap: () {},
          afterWidget: Switch(
            value: appStateSettings["backupSync"] ?? false,
            onChanged: (value) {
              updateSettings("backupSync", value, updateGlobalState: true);
            },
          ),
        ),
        SettingsContainer(
          title: "auto-backups".tr(),
          description: "auto-backups-description".tr(),
          onTap: () {},
          afterWidget: Switch(
            value: appStateSettings["autoBackups"] ?? false,
            onChanged: (value) {
              updateSettings("autoBackups", value, updateGlobalState: true);
            },
          ),
        ),
        SizedBox(height: 12),
        if (isLoading)
          Center(child: CircularProgressIndicator())
        else
          for (var backup in backups)
            ListTile(
              title: TextFont(text: backup['name'] ?? 'Unknown'),
              subtitle: TextFont(
                text: backup['createdAt'] ?? '',
                fontSize: 12,
              ),
              trailing: IconButton(
                icon: Icon(Icons.delete, color: Colors.red),
                onPressed: () async {
                  await deleteBackup(backup['id']);
                  _loadBackups();
                },
              ),
              onTap: () async {
                await loadBackup(backup['id'], context);
              },
            ),
      ],
    );
  }
}

void openBackupReminderPopupCheck(BuildContext context) {
  if (appStateSettings["hasSignedIn"] == true &&
      appStateSettings["canShowBackupReminderPopup"] == true) {
    DateTime lastBackup = DateTime.tryParse(
            appStateSettings["lastBackup"] ?? "") ??
        DateTime.now().subtract(Duration(days: 10));
    if (DateTime.now().difference(lastBackup).inDays > 7) {
      openPopup(
        context,
        title: "backup-reminder".tr(),
        descriptionWidget: Column(
          children: [
            TextFont(text: "backup-reminder-description".tr()),
            SizedBox(height: 12),
            Button(
              label: "create-backup".tr(),
              onTap: () async {
                await createBackup(context);
                Navigator.pop(context);
              },
            ),
          ],
        ),
        onCancelLabel: "cancel".tr(),
        onCancel: () {},
      );
    }
  }
}
