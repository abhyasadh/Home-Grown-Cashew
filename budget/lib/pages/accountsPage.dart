import 'package:budget/colors.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/serverAuth.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/syncClient.dart';
import 'package:budget/widgets/accountAndBackup.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/exportCSV.dart';
import 'package:budget/widgets/exportDB.dart';
import 'package:budget/widgets/importCSV.dart';
import 'package:budget/widgets/importDB.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({Key? key}) : super(key: key);

  @override
  State<AccountsPage> createState() => AccountsPageState();
}

class AccountsPageState extends State<AccountsPage> {
  bool currentlyExporting = false;

  void refreshState() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    bool isLoggedIn = ServerAuth.isLoggedIn;
    String? username = ServerAuth.currentUsername;

    Widget profileWidget = Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dynamicPastel(context, Theme.of(context).colorScheme.primary,
            amount: 0.2),
      ),
      child: Center(
        child: TextFont(
            text: isLoggedIn ? (username?[0].toUpperCase() ?? "S") : "S",
            fontSize: 60,
            textAlign: TextAlign.center,
            fontWeight: FontWeight.bold,
            textColor: dynamicPastel(
                context, Theme.of(context).colorScheme.primary,
                amount: 0.85, inverse: false)),
      ),
    );

    return PageFramework(
      horizontalPaddingConstrained: true,
      dragDownToDismiss: true,
      expandedHeight: 56,
      title: getPlatform() == PlatformOS.isIOS
          ? "backup".tr()
          : "data-backup".tr(),
      appBarBackgroundColor: getPlatform() == PlatformOS.isIOS
          ? null
          : Theme.of(context).colorScheme.secondaryContainer,
      appBarBackgroundColorStart: getPlatform() == PlatformOS.isIOS
          ? null
          : Theme.of(context).colorScheme.secondaryContainer,
      bottomPadding: false,
      listWidgets: [
        Column(
        children: [
          SizedBox(height: 20),
          profileWidget,
          SizedBox(height: 12),
          if (isLoggedIn) ...[
            TextFont(
              text: username ?? "server-connected".tr(),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            SizedBox(height: 4),
            TextFont(
              text: "server-url".tr() + ": " + (appStateSettings["serverUrl"] ?? ""),
              fontSize: 12,
              textColor: Theme.of(context).colorScheme.outline,
            ),
            SizedBox(height: 12),
            Padding(
              padding:
                  EdgeInsetsDirectional.symmetric(horizontal: 16),
              child: Button(
                label: "logout".tr(),
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.logout_outlined
                    : Icons.logout_rounded,
                onTap: () async {
                  await signOutServer();
                  setState(() {});
                },
              ),
            ),
          ] else ...[
            TextFont(
              text: "not-connected".tr(),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            SizedBox(height: 12),
            Padding(
              padding:
                  EdgeInsetsDirectional.symmetric(horizontal: 16),
              child: Button(
                label: "server-login".tr(),
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.login_outlined
                    : Icons.login_rounded,
                onTap: () async {
                  await openServerLoginPopup(context);
                  setState(() {});
                },
              ),
            ),
          ],
          SizedBox(height: 20),
          if (isLoggedIn) ...[
            Divider(),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
              child: Column(
                children: [
                  SettingsContainer(
                    title: "backup".tr(),
                    description: "create-backup-description".tr(),
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.backup_outlined
                        : Icons.backup_rounded,
                    onTap: () async {
                      await createBackup(context);
                    },
                  ),
                  SettingsContainer(
                    title: "restore".tr(),
                    description: "restore-backup-description".tr(),
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.restore_outlined
                        : Icons.restore_rounded,
                    onTap: () async {
                      await chooseBackup(context);
                    },
                  ),
                  SettingsContainer(
                    title: "manage-backups".tr(),
                    description: "manage-backups-description".tr(),
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.folder_outlined
                        : Icons.folder_rounded,
                    onTap: () {
                      openBottomSheet(
                        context,
                        PopupFramework(
                          title: "manage-backups".tr(),
                          child: BackupManagement(),
                        ),
                      );
                    },
                  ),
                  Divider(),
                  SettingsContainer(
                    title: "sync".tr(),
                    description: "sync-description".tr(),
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.sync_outlined
                        : Icons.sync_rounded,
                    onTap: () async {
                      await syncDataToServer(context);
                      setState(() {});
                    },
                  ),
                  Divider(),
                  SettingsContainer(
                    title: "import-database".tr(),
                    description: "import-database-description".tr(),
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.file_download_outlined
                        : Icons.file_download_rounded,
                    onTap: () {
                      importDBFileFromDevice(context);
                    },
                  ),
                  ExportDB(),
                  ImportDB(),
                  ExportCSV(),
                  ImportCSV(),
                ],
              ),
            ),
          ],
          SizedBox(height: 40),
        ],
        ),
      ],
    );
  }
}
