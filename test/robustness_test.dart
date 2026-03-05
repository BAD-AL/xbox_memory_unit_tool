import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';
import 'package:xbox_memory_unit_tool/src/storage.dart';
import 'package:test/test.dart';

void main() {
  group('Robustness: Directory Extension', () {
    test('Should extend root directory when more than 256 entries are added', () {
      final mu = XboxMemoryUnit.format();
      final image = FatxImage(MemoryStorage(mu.bytes));

      // 1. Fill the root directory (Cluster 1)
      // 16384 bytes / 64 bytes per entry = 256 entries.
      for (var i = 1; i <= 256; i++) {
        image.addEntry(1, FatxDirEntry()
          ..filename = 'DIR_$i'
          ..attributes = FatxDirEntry.attrDirectory
          ..firstCluster = 0);
      }

      // 2. Verify root still has 1 cluster
      expect(image.getClusterChain(1).length, 1);

      // 3. Add the 257th entry - this should trigger extension
      image.addEntry(1, FatxDirEntry()
        ..filename = 'EXTENDED'
        ..attributes = FatxDirEntry.attrDirectory
        ..firstCluster = 0);

      // 4. Verify root now has 2 clusters
      final chain = image.getClusterChain(1);
      expect(chain.length, 2);

      // 5. Verify we can list all 257 entries
      final entries = image.listDirectory(1);
      expect(entries.length, 257);
      expect(entries.last.filename, 'EXTENDED');
    });

    test('Should handle multiple extensions', () {
        final mu = XboxMemoryUnit.format();
        final image = FatxImage(MemoryStorage(mu.bytes));

        // Add 600 entries (should be 3 clusters: 256 + 256 + 88)
        for (var i = 1; i <= 600; i++) {
            image.addEntry(1, FatxDirEntry()
            ..filename = 'F_$i'
            ..attributes = 0x00
            ..firstCluster = 0);
        }

        final chain = image.getClusterChain(1);
        expect(chain.length, 3);
        
        final entries = image.listDirectory(1);
        expect(entries.length, 600);
        expect(entries.any((e) => e.filename == 'F_600'), isTrue);
    });
  });
}
