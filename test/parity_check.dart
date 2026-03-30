import 'dart:io';
import 'dart:typed_data';
import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';
import 'package:xbox_memory_unit_tool/src/storage.dart';

void main(List<String> args) {
  if (args.length != 2) {
    print('Usage: dart parity_check.dart <file1> <file2>');
    exit(1);
  }

  final file1 = File(args[0]).readAsBytesSync();
  final file2 = File(args[1]).readAsBytesSync();

  if (file1.length != file2.length) {
    print('FAIL: Lengths differ (file1: ${file1.length}, file2: ${file2.length})');
    exit(1);
  }

  // Zero-out Volume ID (offsets 4-7)
  final b1 = Uint8List.fromList(file1);
  final b2 = Uint8List.fromList(file2);
  for (var i = 4; i < 8; i++) {
    b1[i] = 0;
    b2[i] = 0;
  }

  // Zero-out Timestamps in directory entries (offsets 52-63 in each 64-byte entry)
  _zeroTimestamps(b1);
  _zeroTimestamps(b2);

  for (var i = 0; i < b1.length; i++) {
    if (b1[i] != b2[i]) {
      print('FAIL: First mismatch at offset 0x${i.toRadixString(16).toUpperCase()}');
      print('File1: 0x${b1[i].toRadixString(16).padLeft(2, '0')}');
      print('File2: 0x${b2[i].toRadixString(16).padLeft(2, '0')}');
      exit(1);
    }
  }

  print('PASS');
}

void _zeroTimestamps(Uint8List bytes) {
  final storage = MemoryStorage(bytes);
  final image = FatxImage(storage);
  _zeroDirRecursive(image, 1);
}

void _zeroDirRecursive(FatxImage image, int cluster) {
  final chain = image.getClusterChain(cluster);
  for (final c in chain) {
    final offset = FatxMapper.clusterToOffset(c, image.config);
    final clusterData = image.storage.read(offset, image.config.clusterSizeReal);
    
    for (var i = 0; i < image.config.clusterSizeReal; i += 64) {
      final entryOffset = offset + i;
      final filenameLen = clusterData[i];
      
      if (filenameLen == 0x00 || filenameLen == 0xFF) break;
      if (filenameLen == 0xE5) continue; // Deleted

      // Attributes at +1
      final attributes = clusterData[i + 1];
      final isDirectory = (attributes & 0x10) != 0;
      
      final view = ByteData.sublistView(clusterData, i + 44, i + 48);
      final firstCluster = view.getUint32(0, Endian.little);

      // Zero-out timestamps (offsets 52 to 63)
      final zeroTs = Uint8List(12); // All zeros
      image.storage.write(entryOffset + 52, zeroTs);

      if (isDirectory && firstCluster != 0) {
        _zeroDirRecursive(image, firstCluster);
      }
    }
  }
}
