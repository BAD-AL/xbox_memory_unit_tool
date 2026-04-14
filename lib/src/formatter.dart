import 'dart:typed_data';
import 'fatx.dart';

class FatxFormatter {
  /// Formats an Xbox FATX Memory Unit of the specified size.
  static Uint8List format({int size = 8388608}) {
    final config = FatxConfig.forSize(size);

    // 1. Initialize entire image with 0xFF padding (XEMU Gold Standard)
    final buffer = Uint8List(size)..fillRange(0, size, 0xFF);
    
    // 2. Clear FAT area to 0x00 for free clusters
    for (var i = FatxConfig.fatOffset; i < FatxConfig.fatOffset + config.fatSize; i++) {
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
    view.setUint32(4, FatxConfig.generateRandomVolumeId(), Endian.little);

    // Offset 8: Sectors Per Cluster (The "Lie")
    view.setUint32(8, config.sectorsPerClusterReported, Endian.little);

    // Offset 12: Root Directory Cluster (Usually 1)
    view.setUint32(12, 1, Endian.little);

    // Offset 16: Unknown/Reserved (0x0000)
    view.setUint16(16, 0x0000, Endian.little);

    // 2. Initialize FAT (at 0x1000)
    // Offset 0x1000: Media Byte (0xFFF8 in little-endian is [F8, FF])
    view.setUint16(FatxConfig.fatOffset + 0, 0xFFF8, Endian.little);
    
    // Offset 0x1002: Root Directory (Cluster 1) is end of chain (0xFFFF)
    view.setUint16(FatxConfig.fatOffset + 2, 0xFFFF, Endian.little);

    // 3. Data Area starts at config.dataOffset (already 0xFF padded)

    return buffer;
  }
}
