import 'package:budget/struct/serverAuth.dart';
import 'package:budget/struct/serverClient.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';

Future<String?> getPhotoAndUpload({required ImageSource source}) async {
  dynamic result = await openLoadingPopupTryCatch(() async {
    final ImagePicker picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: source);
    if (photo == null) {
      if (source == ImageSource.camera) throw ("no-photo-taken".tr());
      if (source == ImageSource.gallery) throw ("no-file-selected".tr());
      throw ("error-getting-photo");
    }

    if (!ServerAuth.isLoggedIn) {
      throw ("not-connected-to-server".tr());
    }

    try {
      String path = photo.path;

      final response = await ServerClient.uploadFile(
        '/api/attachments',
        path,
        'file',
      );

      return response['id'];
    } catch (e) {
      print("Error uploading file: " + e.toString());
      rethrow;
    }
  }, onError: (e) {
    openSnackbar(
      SnackbarMessage(
        title: "error-attaching-file".tr(),
        description: e.toString(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.error_outlined
            : Icons.error_rounded,
      ),
    );
  });
  if (result is String) return result;
  return null;
}

Future<String?> getFileAndUpload() async {
  dynamic result = await openLoadingPopupTryCatch(() async {
    FilePickerResult? result = await FilePicker.pickFiles();
    if (result == null) throw ("no-file-selected".tr());

    if (!ServerAuth.isLoggedIn) {
      throw ("not-connected-to-server".tr());
    }

    try {
      String? path = result.files.single.path;
      if (path == null) throw ("error-getting-file");

      final response = await ServerClient.uploadFile(
        '/api/attachments',
        path,
        'file',
      );

      return response['id'];
    } catch (e) {
      print("Error uploading file: " + e.toString());
      rethrow;
    }
  }, onError: (e) {
    openSnackbar(
      SnackbarMessage(
        title: "error-attaching-file".tr(),
        description: e.toString(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.error_outlined
            : Icons.error_rounded,
      ),
    );
  });
  if (result is String) return result;
  return null;
}
