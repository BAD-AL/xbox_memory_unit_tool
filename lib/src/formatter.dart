import 'dart:typed_data';
import 'fatx.dart';

class FatxFormatter {
  /// Formats an 8MB buffer as an Xbox FATX Memory Unit.
  static Uint8List format() {
    // 1. Initialize entire image with 0xFF padding (XEMU Gold Standard)
    final buffer = Uint8List(FatxConfig.muSize)..fillRange(0, FatxConfig.muSize, 0xFF);
    
    // 2. Clear FAT area to 0x00 for free clusters
    for (var i = FatxConfig.fatOffset; i < FatxConfig.fatOffset + 4096; i++) {
      buffer[i] = 0x00;
    }

    final view = ByteData.view(buffer.buffer);

    // Write Superblock (4KB) at offset 0
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
