import 'dart:io';
import 'dart:typed_data';
import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';
import 'package:test/test.dart';

void main() {
  group('High-Level API (XboxMemoryUnit)', () {
    test('Format new MU', () {
      XboxMemoryUnit mu = XboxMemoryUnit.format();
      expect(mu.bytes.length, 8388608);
      expect(mu.titles.isEmpty, isTrue);
    });

    test('Load roster MU and verify hierarchy', () {
      Uint8List bytes = File('test/test_files/XEMU_Created_default_roster.bin').readAsBytesSync();
      XboxMemoryUnit mu = XboxMemoryUnit.fromBytes(bytes);

      expect(mu.titles.length, 1);
      XboxTitle title = mu.titles.first;
      expect(title.name, 'ESPN NFL 2K5');
      expect(title.id, '53450030');

      expect(title.saves.length, 1);
      XboxSave save = title.saves.first;
      expect(save.name, 'Roster1');
      expect(save.folderName, '19FA1AF775EF');
      
      expect(title.titleImage, isNotNull);
      expect(save.saveImage, isNotNull);
    });

    test('Find title by name', () {
      Uint8List bytes = File('test/test_files/XEMU_Created_default_roster.bin').readAsBytesSync();
      XboxMemoryUnit mu = XboxMemoryUnit.fromBytes(bytes);

      XboxTitle? title = mu.findTitleByName('ESPN NFL 2K5');
      expect(title, isNotNull);
      expect(title!.id, '53450030');
    });

    test('High-level Export (Context-Aware)', () {
      Uint8List bytes = File('test/test_files/XEMU_Created_default_roster.bin').readAsBytesSync();
      XboxMemoryUnit mu = XboxMemoryUnit.fromBytes(bytes);

      Uint8List zipBytes = mu.export('ESPN NFL 2K5/Roster1');
      expect(zipBytes, isNotEmpty);
      // We already tested ZIP contents in low-level tests, 
      // here we verify the high-level bridge.
    });
  });
}
