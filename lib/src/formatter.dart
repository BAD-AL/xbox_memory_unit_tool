import 'dart:typed_data';
import 'fatx.dart';

class FatxFormatter {
  /// Formats an 8MB buffer as an Xbox FATX Memory Unit.
  static Uint8List format() {
    final buffer = Uint8List(FatxConfig.muSize);
    
    // 1. Initialize Superblock (4KB) with 0xFF padding
    for (var i = 0; i < 4096; i++) {
      buffer[i] = 0xFF;
    }

    final view = ByteData.view(buffer.buffer);

    // Offset 0: 'FATX' (Signature)
    view.setUint8(0, 'F'.codeUnitAt(0));
    view.setUint8(1, 'A'.codeUnitAt(0));
    view.setUint8(2, 'T'.codeUnitAt(0));
    view.setUint8(3, 'X'.codeUnitAt(0));

    // Offset 4: Volume ID (TR-2)
    view.setUint32(4, FatxConfig.volumeIdFixed, Endian.little);

    // Offset 8: Sectors Per Cluster (The "Lie")
    view.setUint32(8, FatxConfig.sectorsPerClusterReported, Endian.little);

    // Offset 12: Root Directory Cluster (Usually 1)
    view.setUint32(12, 1, Endian.little);

    // Offset 16: Unknown/Reserved (0x0000)
    view.setUint16(16, 0x0000, Endian.little);

    // 2. Initialize FAT (4KB at 0x1000)
    // Area is already 0x00 from Uint8List() initialization.
    final fatBytes = Uint8List.sublistView(buffer, FatxConfig.fatOffset, FatxConfig.fatOffset + 4096);
    final table = FatxTable(fatBytes);
    table.initialize();
    table.setEntry(1, 0xFFFF); // Root Directory (Cluster 1) is end of chain

    // 3. Initialize Data Area (TR-4: Zero initialized)
    // Already zeroed by Uint8List(FatxConfig.muSize)

    return buffer;
  }
}
