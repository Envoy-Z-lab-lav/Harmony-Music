import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tailwind/flutter_tailwind.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/res/tailwind_ext.dart';
import 'package:harmonymusic/services/permission_service.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/widgets/common_dialog_widget.dart';
import 'package:harmonymusic/ui/widgets/loader.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:hive/hive.dart';

class BackupDialog extends StatelessWidget {
  const BackupDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final backupDialogController = Get.put(BackupDialogController());
    return CommonDialog(
      child: Container(
        height: GetPlatform.isAndroid ? 350 : 300,
        padding: const EdgeInsets.only(top: 20, bottom: 30, left: 20, right: 20),
        child: Stack(
          children: [
            column.children(
              [
                container.pb18.pt18.child(
                  'backupAppData'.tr.text.titleMedium.mk,
                ),
                Expanded(
                  child: sizedBox.h100.child(
                    Center(
                      child: column.center.children([
                        Obx(() =>
                            (backupDialogController.scanning.isTrue || backupDialogController.backupRunning.isTrue)
                                ? const LoadingIndicator()
                                : const SizedBox.shrink()),
                        const SizedBox(height: 10),
                        column.children([
                          Obx(
                            () => (backupDialogController.scanning.isTrue
                                    ? 'scanning'.tr
                                    : backupDialogController.backupRunning.isTrue
                                        ? 'backupInProgress'.tr
                                        : backupDialogController.isbackupCompleted.isTrue
                                            ? 'backupMsg'.tr
                                            : 'letsStrart')
                                .text
                                .center
                                .mk,
                          ),
                          if (GetPlatform.isAndroid)
                            Obx(
                              () => (backupDialogController.isDownloadedfilesSeclected.isTrue)
                                  ? padding.pt16.child('androidBackupWarning'.tr.text.bold.center.titleSmall.mk)
                                  : const SizedBox.shrink(),
                            )
                        ]),
                      ]),
                    ),
                  ),
                ),
                if (!GetPlatform.isDesktop)
                  Obx(
                    () => padding.pv16.child(
                      row.center.children([
                        Checkbox(
                          value: backupDialogController.isDownloadedfilesSeclected.value,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                          onChanged: backupDialogController.scanning.isTrue ||
                                  backupDialogController.backupRunning.isTrue ||
                                  backupDialogController.isbackupCompleted.isTrue
                              ? null
                              : (bool? value) {
                                  backupDialogController.isDownloadedfilesSeclected.value = value!;
                                },
                        ),
                        'includeDownloadedFiles'.tr.text.mk,
                      ]),
                    ),
                  ),
                SizedBox(
                  width: double.maxFinite,
                  child: Align(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).textTheme.titleLarge!.color,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: InkWell(
                        onTap: () {
                          if (backupDialogController.isbackupCompleted.isTrue) {
                            Navigator.of(context).pop();
                          } else {
                            backupDialogController.backup();
                          }
                        },
                        child: Obx(
                          () => Visibility(
                            visible: !(backupDialogController.backupRunning.isTrue ||
                                backupDialogController.scanning.isTrue),
                            replacement: const SizedBox(
                              height: 40,
                            ),
                            child: padding.ph28.pv18.child(
                              Obx(() {
                                return (backupDialogController.isbackupCompleted.isTrue ? 'close'.tr : 'backup'.tr)
                                    .text
                                    .canvasColor
                                    .mk;
                              }),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BackupDialogController extends GetxController {
  final scanning = false.obs;
  final isbackupCompleted = false.obs;
  final backupRunning = false.obs;
  final isDownloadedfilesSeclected = false.obs;
  List<String> filesToExport = [];
  final supportDirPath = Get.find<SettingsScreenController>().supportDirPath;

  Future<void> scanFilesToBackup() async {
    final dbDir = await Get.find<SettingsScreenController>().dbDir;
    filesToExport.addAll(await processDirectoryInIsolate(dbDir));
    if (isDownloadedfilesSeclected.value) {
      var downlodedSongFilePaths = Hive.box('SongDownloads').values.map<String>((data) => data['url']).toList();
      filesToExport.addAll(downlodedSongFilePaths);
      try {
        filesToExport.addAll(await processDirectoryInIsolate('$supportDirPath/thumbnails', extensionFilter: '.png'));
      } catch (e) {
        printERROR(e);
      }
    }
  }

  Future<void> backup() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final pickedFolderPath = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select backup file folder');
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    scanning.value = true;
    await Future.delayed(const Duration(seconds: 4));
    await scanFilesToBackup();
    scanning.value = false;

    backupRunning.value = true;
    final exportDirPath = pickedFolderPath;

    compressFilesInBackground(filesToExport, '$exportDirPath/${DateTime.now().millisecondsSinceEpoch}.hmb').then((_) {
      backupRunning.value = false;
      isbackupCompleted.value = true;
    }).catchError((e) {
      printERROR('Error during compression: $e');
    });
  }
}

// Function to convert file paths to base64-encoded file data
List<String> filePathsToBase64(List<String> filePaths) {
  var base64Data = <String>[];

  for (var path in filePaths) {
    try {
      // Read the file data as bytes
      var file = File(path);
      List<int> fileData = file.readAsBytesSync();
      // Convert bytes to base64
      var base64String = base64Encode(fileData);
      base64Data.add(base64String);
    } catch (e) {
      printERROR('Error reading file $path: $e');
    }
  }

  return base64Data;
}

// Function to convert file paths to file data (List<int>)
List<List<int>> filePathsToFileData(List<String> filePaths) {
  var filesData = <List<int>>[];

  for (var path in filePaths) {
    try {
      // Read the file data as bytes
      var file = File(path);
      List<int> fileData = file.readAsBytesSync();
      filesData.add(fileData);
    } catch (e) {
      printERROR('Error reading file $path: $e');
    }
  }

  return filesData;
}

// Function to compress files (to be used with compute or isolate)
void _compressFiles(Map<String, dynamic> params) {
  final List<List<int>> filesData = params['filesData'];
  final List<String> fileNames = params['fileNames'];
  final String zipFilePath = params['zipFilePath'];

  final archive = Archive();

  for (var i = 0; i < filesData.length; i++) {
    final fileData = filesData[i];
    final fileName = fileNames[i];
    final file = ArchiveFile(fileName, fileData.length, fileData);
    archive.addFile(file);
  }

  final encoder = ZipEncoder();
  final zipFile = File(zipFilePath);
  zipFile.writeAsBytesSync(encoder.encode(archive)!);
}

// Example usage
Future<void> compressFilesInBackground(List<String> filePaths, String zipFilePath) async {
  // Convert file paths to file data
  final filesData = filePathsToFileData(filePaths);
  final fileNames = filePaths.map((path) => path.split(GetPlatform.isWindows ? '\\' : '/').last).toList();

  printINFO(fileNames);
  // Use compute to run the compression in the background
  await compute(_compressFiles, {
    'filesData': filesData,
    'fileNames': fileNames,
    'zipFilePath': zipFilePath,
  });
}

Future<List<String>> processDirectoryInIsolate(String dbDir, {String extensionFilter = '.hive'}) async {
  // Use Isolate.run to execute the function in a new isolate
  return Isolate.run(() async {
    // List files in the directory
    final filesEntityList = await Directory(dbDir).list().toList();

    // Filter out .hive files
    final filesPath = filesEntityList
        .whereType<File>() // Ensure we only work with files
        .map((entity) {
          if (entity.path.endsWith(extensionFilter)) return entity.path;
        })
        .whereType<String>()
        .toList();

    return filesPath;
  });
}
