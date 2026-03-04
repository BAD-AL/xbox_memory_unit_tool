import 'dart:io';
import 'dart:typed_data';

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

  // TODO: Zero-out Timestamps in directory entries if comparing non-blank cards
  // (Not needed for blank cards)

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
