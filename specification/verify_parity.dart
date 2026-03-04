
import 'dart:io';
import 'dart:typed_data';

/// FATX Parity Verifier
///
/// Compares two 8MB FATX images, ignoring Volume ID and Timestamps.
void main(List<String> args) {
  if (args.length < 2) {
    print('Usage: dart verify_parity.dart <image1.bin> <image2.bin>');
    exit(1);
  }

  final file1 = File(args[0]);
  final file2 = File(args[1]);

  if (!file1.existsSync() || !file2.existsSync()) {
    print('Error: One or both files do not exist.');
    exit(1);
  }

  final bytes1 = file1.readAsBytesSync();
  final bytes2 = file2.readAsBytesSync();

  if (bytes1.length != bytes2.length) {
    print('FAIL: File sizes differ (${bytes1.length} vs ${bytes2.length})');
    exit(1);
  }

  print('Pre-processing buffers (Zeroing Volume ID and Timestamps)...');
  
  // 1. Zero out Volume ID (Offset 4-7)
  for (int i = 4; i <= 7; i++) {
    bytes1[i] = 0;
    bytes2[i] = 0;
  }

  // 2. Scan for directory entries and zero out timestamps
  // A directory entry is 64 bytes. We scan the whole data area from 0x2000.
  for (int i = 0x2000; i < bytes1.length - 64; i += 64) {
    // Basic check if this looks like a directory entry (valid filename length)
    final len1 = bytes1[i];
    final len2 = bytes2[i];
    
    // We only process if both buffers have a likely entry here
    if (len1 > 0 && len1 <= 42) {
      _zeroTimestamps(bytes1, i);
    }
    if (len2 > 0 && len2 <= 42) {
      _zeroTimestamps(bytes2, i);
    }
  }

  // 3. Final bit-wise comparison
  bool match = true;
  for (int i = 0; i < bytes1.length; i++) {
    if (bytes1[i] != bytes2[i]) {
      print('FAIL: Mismatch at offset 0x${i.toRadixString(16)}');
      print('  File 1: 0x${bytes1[i].toRadixString(16).padLeft(2, '0')}');
      print('  File 2: 0x${bytes2[i].toRadixString(16).padLeft(2, '0')}');
      match = false;
      break;
    }
  }

  if (match) {
    print('PASS: Images are functionally identical!');
  } else {
    exit(1);
  }
}

/// Zeroes out creation, modification, and access timestamps in a 64-byte dirent.
void _zeroTimestamps(Uint8List buffer, int startOffset) {
  // Timestamps start at offset 52 within the 64-byte entry
  for (int j = 52; j < 64; j++) {
    buffer[startOffset + j] = 0;
  }
}
