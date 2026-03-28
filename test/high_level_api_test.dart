import 'dart:io';
import 'dart:typed_data';
import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';
import 'package:test/test.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

void main() {
  group('High-Level API: XboxMemoryUnit', () {
    test('1. Formatting a New Memory Unit', () {
      XboxMemoryUnit mu = XboxMemoryUnit.format();
      expect(mu.bytes.length, 8388608);
      expect(mu.titles, isEmpty);
    });

    test('2. Loading an Existing Image', () {
      Uint8List bytes = File('test/test_files/XEMU_Created_default_roster.bin').readAsBytesSync();
      XboxMemoryUnit mu = XboxMemoryUnit.fromBytes(bytes);

      expect(mu.titles.length, 1);
      expect(mu.titles.first.name, 'ESPN NFL 2K5');
    });

    test('3. Full Workflow: Create, Import, and Save (Reload Verification)', () {
      // 1. Create a fresh memory unit
      XboxMemoryUnit mu = XboxMemoryUnit.format();

      // 2. We'll use a ZIP that we know has full TitleMeta (exported from our reference bin)
      Uint8List rosterBytes = File('test/test_files/XEMU_Created_default_roster.bin').readAsBytesSync();
      XboxMemoryUnit refMu = XboxMemoryUnit.fromBytes(rosterBytes);
      Uint8List zipBytes = refMu.export('ESPN NFL 2K5');

      // 3. Import the save into the fresh memory unit
      mu.importZip(zipBytes);

      // 4. Simulate saving and reloading
      Uint8List finalBytes = mu.bytes;
      XboxMemoryUnit reloadedMu = XboxMemoryUnit.fromBytes(finalBytes);

      // 5. Verify the content survived the reload
      expect(reloadedMu.titles.length, 1);
      XboxTitle title = reloadedMu.titles.first;
      expect(title.name, 'ESPN NFL 2K5');
      expect(title.saves.length, 1);
      expect(title.saves.first.name, 'Roster1');
    });

    test('4. Full Workflow: Import and Save (using mega_x_key_saves sweep)', () {
      // We will loop through all mega_x_key_saves to ensure broad game support
      final megaPath = 'test/test_files/mega_x_key_saves';
      final zipFiles = Directory(megaPath).listSync().where((f) => f.path.endsWith('.zip')).toList();
      
      expect(zipFiles, isNotEmpty, reason: 'No ZIP files found in $megaPath');

      for (var zipFile in zipFiles) {
        final zipFilename = p.basename(zipFile.path);
        
        XboxMemoryUnit mu = XboxMemoryUnit.format();
        Uint8List zipBytes = File(zipFile.path).readAsBytesSync();
        
        mu.importZip(zipBytes);

        // Filter out TDATA if it exists
        final titles = mu.titles.where((t) => t.id != 'TDATA').toList();
        expect(titles, isNotEmpty, reason: 'Failed to import $zipFilename');
        
        // Use the first game title found
        final title = titles.first;
        
        // Internal name parsing should work (usually)
        // Note: Some saves might not have TitleMeta.xbx, but all in this folder should.
        expect(title.name, isNotEmpty, reason: 'Title name should be parsed for $zipFilename');
        expect(title.saves, isNotEmpty, reason: 'No saves found for $zipFilename');
        
        XboxSave save = title.saves.first;
        expect(save.name, isNotEmpty, reason: 'Save name should be parsed for $zipFilename');
        
        print('Verified game: ${title.name} (${title.id}) -> Save: ${save.name}');
      }
    });

    test('4. Exporting a Specific Save (Thick Export by Friendly Path)', () {
      Uint8List bytes = File('test/test_files/XEMU_Created_default_roster.bin').readAsBytesSync();
      XboxMemoryUnit mu = XboxMemoryUnit.fromBytes(bytes);

      // Export by friendly path: "Game Name/Save Name"
      Uint8List zipBytes = mu.export("ESPN NFL 2K5/Roster1");
      expect(zipBytes, isNotEmpty);

      Archive archive = ZipDecoder().decodeBytes(zipBytes);
      
      // Verify thick context (TitleID folder + Metadata + Specific Save Folder)
      expect(archive.files.any((f) => f.name == 'UDATA/53450030/TitleMeta.xbx'), isTrue);
      expect(archive.files.any((f) => f.name.startsWith('UDATA/53450030/19FA1AF775EF/')), isTrue);
    });

    test('5. Accessing Metadata and Images', () {
      Uint8List bytes = File('test/test_files/XEMU_Created_default_roster.bin').readAsBytesSync();
      XboxMemoryUnit mu = XboxMemoryUnit.fromBytes(bytes);

      XboxTitle? title = mu.findTitle("ESPN NFL 2K5");
      expect(title, isNotNull);
      
      // Verification of images (these specific files are known to have them)
      expect(title!.titleImage, isNotNull);
      expect(title.titleMeta, isNotNull);
      
      expect(title.saves.first.saveImage, isNotNull);
    });

    test('6. Individual Save Export (XboxSave.exportZip)', () {
      Uint8List bytes = File('test/test_files/XEMU_Created_default_roster.bin').readAsBytesSync();
      XboxMemoryUnit mu = XboxMemoryUnit.fromBytes(bytes);

      final title = mu.titles.first;
      final save = title.saves.first;
      
      Uint8List zipBytes = save.exportZip();
      expect(zipBytes, isNotEmpty);
      
      Archive archive = ZipDecoder().decodeBytes(zipBytes);
      // Should have game context
      expect(archive.files.any((f) => f.name.contains('TitleMeta.xbx')), isTrue);
      expect(archive.files.any((f) => f.name.contains(save.folderName)), isTrue);
    });
  });
}
