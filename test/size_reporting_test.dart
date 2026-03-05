import 'dart:io';
import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';
import 'package:xbox_memory_unit_tool/src/storage.dart';
import 'package:test/test.dart';

void main() {
  group('FATX Size and Free Space Reporting', () {
    test('Should report correct free space on a blank card', () {
      final mu = XboxMemoryUnit.format();
      // Usable: (8388608 - 8192) = 8380416. 
      // Clusters = 8380416 / 16384 = 511.5 -> 511 clusters.
      // Root uses 1. Free = 510.
      expect(mu.freeBytes, 510 * 16384);
    });

    test('Should report reduced free space after import', () {
      final mu = XboxMemoryUnit.format();
      final initialFree = mu.freeBytes;
      
      // Import a small save
      mu.importZip(File('test/test_files/test_import_minimal.zip').readAsBytesSync());
      
      // Title dir (1) + file (1) = 2 clusters used.
      expect(mu.freeBytes, initialFree - (2 * 16384));
    });

    test('Should calculate recursive directory sizes correctly', () {
      final mu = XboxMemoryUnit.format();
      final image = FatxImage(MemoryStorage(mu.bytes));

      // 1. Manually create a structure
      // Title Folder
      final gameCluster = image.fat.allocateCluster();
      image.addEntry(1, FatxDirEntry()
        ..filename = 'GAME'
        ..attributes = FatxDirEntry.attrDirectory
        ..firstCluster = gameCluster);
      
      // File in Title Folder (10KB)
      final f1Cluster = image.fat.allocateCluster();
      image.addEntry(gameCluster, FatxDirEntry()
        ..filename = 'meta.xbx'
        ..fileSize = 10000
        ..firstCluster = f1Cluster);

      // Save Folder inside Title
      final saveCluster = image.fat.allocateCluster();
      image.addEntry(gameCluster, FatxDirEntry()
        ..filename = 'SAVE1'
        ..attributes = FatxDirEntry.attrDirectory
        ..firstCluster = saveCluster);
      
      // File in Save Folder (5KB)
      final f2Cluster = image.fat.allocateCluster();
      image.addEntry(saveCluster, FatxDirEntry()
        ..filename = 'data.bin'
        ..fileSize = 5000
        ..firstCluster = f2Cluster);

      final title = mu.titles.first;
      final save = title.saves.first;

      expect(save.size, 5000);
      expect(title.size, 10000 + 5000); // Title size is recursive
    });

    test('Should report sane modified timestamps', () {
      final mu = XboxMemoryUnit.format();
      final initialFree = mu.freeBytes;
      
      // Import a save
      mu.importZip(File('test/test_files/test_import_minimal.zip').readAsBytesSync());
      
      final title = mu.titles.first;
      expect(title.modifiedAt.year, greaterThanOrEqualTo(2000));
      expect(title.modifiedAt.year, lessThanOrEqualTo(2100));
    });
  });
}
