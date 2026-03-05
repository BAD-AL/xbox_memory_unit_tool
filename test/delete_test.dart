import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';
import 'package:xbox_memory_unit_tool/src/storage.dart';
import 'package:test/test.dart';

void main() {
  group('FATX Deletion', () {
    test('Should delete a save folder and free its clusters', () {
      final mu = XboxMemoryUnit.format();
      final image = FatxImage(MemoryStorage(mu.bytes));

      // 1. Manually add a game folder and a save folder
      final gameCluster = image.fat.allocateCluster();
      image.addEntry(1, FatxDirEntry()
        ..filename = '53450030'
        ..attributes = FatxDirEntry.attrDirectory
        ..firstCluster = gameCluster);
      
      final saveCluster = image.fat.allocateCluster();
      image.addEntry(gameCluster, FatxDirEntry()
        ..filename = 'SAVE1'
        ..attributes = FatxDirEntry.attrDirectory
        ..firstCluster = saveCluster);

      // Verify they exist
      expect(image.listDirectory(1).length, 1);
      expect(image.listDirectory(gameCluster).length, 1);
      expect(image.fat.getEntry(saveCluster), 0xFFFF); // Allocated

      // 2. Delete the save
      mu.delete('53450030/SAVE1');

      // 3. Verify save is gone from game folder
      final entries = image.listDirectory(gameCluster);
      expect(entries.length, 0);

      // 4. Verify FAT entry for save cluster is freed (0x0000)
      expect(image.fat.getEntry(saveCluster), 0x0000);
    });

    test('Should delete an entire game folder recursively', () {
      final mu = XboxMemoryUnit.format();
      final image = FatxImage(MemoryStorage(mu.bytes));

      // 1. Setup Game with two saves
      final gameCluster = image.fat.allocateCluster();
      image.addEntry(1, FatxDirEntry()
        ..filename = 'GAME'
        ..attributes = FatxDirEntry.attrDirectory
        ..firstCluster = gameCluster);
      
      final s1 = image.fat.allocateCluster();
      image.addEntry(gameCluster, FatxDirEntry()..filename = 'S1'..attributes = FatxDirEntry.attrDirectory..firstCluster = s1);
      
      final s2 = image.fat.allocateCluster();
      image.addEntry(gameCluster, FatxDirEntry()..filename = 'S2'..attributes = FatxDirEntry.attrDirectory..firstCluster = s2);

      // 2. Delete Game
      mu.delete('GAME');

      // 3. Verify Root is empty
      expect(image.listDirectory(1).length, 0);

      // 4. Verify all clusters are freed
      expect(image.fat.getEntry(gameCluster), 0x0000);
      expect(image.fat.getEntry(s1), 0x0000);
      expect(image.fat.getEntry(s2), 0x0000);
    });
  });
}
