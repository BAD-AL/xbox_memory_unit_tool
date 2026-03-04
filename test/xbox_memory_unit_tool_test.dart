import 'dart:io';
import 'dart:typed_data';
import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';
import 'package:test/test.dart';
import 'package:archive/archive.dart';

void main() {
  group('FATX MU Formatting (TR-1, TR-2, TR-3, TR-4)', () {
    final buffer = FatxFormatter.format();

    test('TR-1: Formatting Signature', () {
      expect(String.fromCharCodes(buffer.sublist(0, 4)), 'FATX');
    });

    test('TR-2: Volume ID', () {
      final view = ByteData.sublistView(buffer);
      expect(view.getUint32(4, Endian.little), 0x00000029);
    });

    test('TR-3: Hybrid Offsets (Cluster 2 starts at 0x6000)', () {
      expect(FatxMapper.clusterToOffset(2), 0x6000);
    });

    test('TR-4: Padding Initialization (Data Area)', () {
      // Check first 64 bytes of cluster 1 (root directory)
      final rootOffset = FatxMapper.clusterToOffset(1);
      final rootArea = buffer.sublist(rootOffset, rootOffset + 64);
      expect(rootArea.every((b) => b == 0xFF), isTrue);
    });
  });

  group('Directory Parsing (TR-5)', () {
    test('TR-5: Recognize 0x00 and 0xFF as terminators', () {
      final terminator00 = Uint8List(64)..[0] = 0x00;
      final terminatorFF = Uint8List(64)..[0] = 0xFF;
      
      expect(FatxDirEntry.fromBytes(terminator00).isEnd, isTrue);
      expect(FatxDirEntry.fromBytes(terminatorFF).isEnd, isTrue);
    });
  });

  group('Import & Normalization (TR-6, TR-8, TR-9, TR-10)', () {
    test('TR-6 & TR-8: Path Normalization & Hidden Attribute', () {
      final buffer = FatxFormatter.format();
      final image = FatxImage(buffer);
      final importer = FatxImporter(image);

      // Create a ZIP with UDATA/ prefix and .xbx file
      final archive = Archive();
      final content = Uint8List.fromList('test'.codeUnits);
      archive.addFile(ArchiveFile('UDATA/53450030/TitleMeta.xbx', content.length, content));
      
      final zipEncoder = ZipEncoder();
      final zipBytes = Uint8List.fromList(zipEncoder.encode(archive)!);

      importer.importZip(zipBytes);

      // Verify TR-6: Directory '53450030' should be in root (UDATA/ stripped)
      final rootEntries = image.listDirectory(1);
      expect(rootEntries.any((e) => e.filename == '53450030'), isTrue);

      final titleIdCluster = rootEntries.firstWhere((e) => e.filename == '53450030').firstCluster;
      final titleIdEntries = image.listDirectory(titleIdCluster);
      final xbxFile = titleIdEntries.firstWhere((e) => e.filename == 'TitleMeta.xbx');

      // Verify TR-8: .xbx has System bit (0x04)
      expect(xbxFile.attributes & FatxDirEntry.attrSystem, FatxDirEntry.attrSystem);
    });

    test('TR-9: Reject Filenames > 42 chars', () {
      final buffer = FatxFormatter.format();
      final image = FatxImage(buffer);
      final importer = FatxImporter(image);
      final longName = 'A' * 43;

      final archive = Archive();
      archive.addFile(ArchiveFile('UDATA/$longName', 0, Uint8List(0)));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      expect(() => importer.importZip(zipBytes), throwsException);
    });

    test('TR-10: FAT16 Chaining (> 16KB)', () {
      final buffer = FatxFormatter.format();
      final image = FatxImage(buffer);
      final importer = FatxImporter(image);

      // Create a file larger than 16KB (e.g., 20KB)
      final size = 20000;
      final content = Uint8List(size);
      for (var i = 0; i < size; i++) content[i] = i % 256;

      final archive = Archive();
      archive.addFile(ArchiveFile('UDATA/large_file', size, content));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      importer.importZip(zipBytes);

      final entries = image.listDirectory(1);
      final fileEntry = entries.firstWhere((e) => e.filename == 'large_file');
      
      // Should occupy 2 clusters
      final chain = image.getClusterChain(fileEntry.firstCluster);
      expect(chain.length, 2);

      // Verify data integrity
      final readData = image.readChain(fileEntry.firstCluster, fileEntry.fileSize);
      expect(readData, content);
    });
  });

  group('Export (TR-7)', () {
    test('TR-7: ZIP Compatibility (Prepend UDATA/)', () {
      final buffer = FatxFormatter.format();
      final image = FatxImage(buffer);
      
      // Manually add a file
      final dirCluster = image.fat.allocateCluster();
      image.addEntry(1, FatxDirEntry()
        ..filename = 'MYDIR'
        ..attributes = FatxDirEntry.attrDirectory
        ..firstCluster = dirCluster);
      
      final fileCluster = image.fat.allocateCluster();
      image.addEntry(dirCluster, FatxDirEntry()
        ..filename = 'test.txt'
        ..fileSize = 4
        ..firstCluster = fileCluster);
      image.writeCluster(fileCluster, Uint8List(FatxConfig.clusterSizeReal)..[0] = 65); // 'A'

      final exporter = FatxExporter(image);
      final zipBytes = exporter.exportToZip(dirCluster, 'MYDIR/');

      final decoded = ZipDecoder().decodeBytes(zipBytes);
      expect(decoded.files.first.name, startsWith('UDATA/MYDIR/'));
      expect(decoded.files.any((f) => f.name == 'UDATA/MYDIR/test.txt'), isTrue);
    });
  });

  group('Gold Standard Verification: 2024Week6.zip', () {
    test('Import 2024Week6.zip and verify .xbx attributes', () {
      final zipPath = 'test/test_files/2024Week6.zip';
      final zipBytes = File(zipPath).readAsBytesSync();
      
      final buffer = FatxFormatter.format();
      final image = FatxImage(buffer);
      final importer = FatxImporter(image);

      importer.importZip(zipBytes);

      _verifyXbxAttributes(image, 1);
    });
  });
}

void _verifyXbxAttributes(FatxImage image, int cluster) {
  final entries = image.listDirectory(cluster);
  for (final entry in entries) {
    if (entry.isDirectory) {
      if (entry.firstCluster != 0) {
        _verifyXbxAttributes(image, entry.firstCluster);
      }
    } else if (entry.filename.toLowerCase().endsWith('.xbx')) {
      expect(entry.attributes & FatxDirEntry.attrSystem, FatxDirEntry.attrSystem,
          reason: 'File ${entry.filename} is missing System attribute (0x04)');
    }
  }
}

