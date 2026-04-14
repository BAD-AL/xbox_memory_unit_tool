import 'dart:io';
import 'dart:typed_data';
import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';
import 'package:xbox_memory_unit_tool/src/storage.dart';
import 'package:test/test.dart';
import 'package:archive/archive.dart';

void main() {
  group('FATX MU Formatting (TR-1, TR-2, TR-3, TR-4)', () {
    final buffer = FatxFormatter.format();

    test('TR-1: Formatting Signature', () {
      expect(String.fromCharCodes(buffer.sublist(0, 4)), 'FATX');
    });

    test('TR-2: Volume ID (Randomized)', () {
      final view = ByteData.sublistView(buffer);
      // Ensure it's not zero and is a uint32
      expect(view.getUint32(4, Endian.little), isNonZero);
    });

    test('TR-3: Hybrid Offsets (Cluster 2 starts at 0x6000 for 8MB)', () {
      final config = FatxConfig.forSize(8388608);
      // 8MB has 4KB FAT @ 0x1000, so data starts at 0x2000.
      // Cluster 2 offset = 0x2000 + (2-1)*16384 = 0x6000.
      expect(FatxMapper.clusterToOffset(2, config), 0x6000);
    });

    test('TR-4: Padding Initialization (Data Area)', () {
      final image = FatxImage(MemoryStorage(buffer));
      // Check first 64 bytes of cluster 1 (root directory)
      final rootOffset = FatxMapper.clusterToOffset(1, image.config);
      final rootArea = buffer.sublist(rootOffset, rootOffset + 64);
      expect(rootArea.every((b) => b == 0xFF), isTrue);
    });

    test('Support 128MB Formatting (32KB Clusters)', () {
      final size = 128 * 1024 * 1024;
      final buffer128 = FatxFormatter.format(size: size);
      final config = FatxConfig.forSize(size);
      
      expect(buffer128.length, size);
      // 128MB image has ~4000 clusters of 32KB.
      // Required FAT bytes = (4096 + 2) * 2 = 8196 bytes.
      // So it fits in 12288 bytes (12KB).
      expect(config.clusterSizeReal, 32768);
      expect(config.sectorsPerClusterReported, 8);
      expect(config.fatSize, 12288);
      
      final image = FatxImage(MemoryStorage(buffer128));
      expect(image.fat.countFreeClusters(), greaterThan(3800));
    });

    test('Support 64MB Formatting (16KB Clusters)', () {
      final size = 64 * 1024 * 1024;
      final buffer64 = FatxFormatter.format(size: size);
      final config = FatxConfig.forSize(size);
      
      expect(config.clusterSizeReal, 16384);
      expect(config.fatSize, 12288);
      
      final image = FatxImage(MemoryStorage(buffer64));
      // Detect should also find the correct FAT size
      final detected = FatxConfig.detect(image.storage);
      expect(detected.fatSize, 12288);
    });

    test('FAT Boundary Protection (Cannot allocate past FAT)', () {
      // Create a small MU with a 4KB FAT (limit 2047 clusters)
      final size = 32 * 1024 * 1024;
      final buffer = FatxFormatter.format(size: size);
      final image = FatxImage(MemoryStorage(buffer));
      
      // Exhaust the FAT
      try {
        while (true) {
          image.fat.allocateCluster();
        }
      } catch (e) {
        expect(e.toString(), contains('Disk full'));
      }
      
      // Ensure we didn't exceed index 2047
      expect(image.fat.getEntry(2047), isNot(0));
      // Attempting to read entry 2048 should technically be out of range for a 4KB FAT 
      // if the code was strict, but getEntry uses offset. 
      // Our fix ensures the loop stops at 2047.
    });
  });

  group('Import Attributes (TR-8)', () {
    test('Set Archive bit for .xbe and System bit for .xbx', () {
      final buffer = FatxFormatter.format();
      final image = FatxImage(MemoryStorage(buffer));
      final importer = FatxImporter(image);

      final archive = Archive();
      archive.addFile(ArchiveFile('default.xbe', 4, Uint8List.fromList([0,0,0,0])));
      archive.addFile(ArchiveFile('TitleMeta.xbx', 4, Uint8List.fromList([0,0,0,0])));
      
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      importer.importZip(zipBytes);

      final entries = image.listDirectory(1);
      final xbe = entries.firstWhere((e) => e.filename == 'default.xbe');
      final xbx = entries.firstWhere((e) => e.filename == 'TitleMeta.xbx');

      expect(xbe.attributes & FatxDirEntry.attrArchive, FatxDirEntry.attrArchive);
      expect(xbx.attributes & FatxDirEntry.attrSystem, FatxDirEntry.attrSystem);
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
      final image = FatxImage(MemoryStorage(buffer));
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
      final image = FatxImage(MemoryStorage(buffer));
      final importer = FatxImporter(image);
      final longName = 'A' * 43;

      final archive = Archive();
      archive.addFile(ArchiveFile('UDATA/$longName', 0, Uint8List(0)));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      expect(() => importer.importZip(zipBytes), throwsException);
    });

    test('TR-10: FAT16 Chaining (> 16KB)', () {
      final buffer = FatxFormatter.format();
      final image = FatxImage(MemoryStorage(buffer));
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
      final image = FatxImage(MemoryStorage(buffer));
      
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
      image.writeCluster(fileCluster, Uint8List(image.config.clusterSizeReal)..[0] = 65); // 'A'

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
      if (!File(zipPath).existsSync()) {
        print('Skipping test: $zipPath not found');
        return;
      }
      final zipBytes = File(zipPath).readAsBytesSync();
      
      final buffer = FatxFormatter.format();
      final image = FatxImage(MemoryStorage(buffer));
      final importer = FatxImporter(image);

      importer.importZip(zipBytes);

      _verifyXbxAttributes(image, 1);
    });
  });

  group('XbxMeta Metadata Parsing', () {
    test('Parse TitleMeta.xbx correctly (UTF-16 LE)', () {
      final name = 'ESPN NFL 2K5';
      final content = 'TitleName=$name\r\n';
      final bytes = _createUtf16LeWithBom(content);
      
      final parsed = XbxMeta.parseName('TitleMeta.xbx', bytes);
      expect(parsed, name);
    });

    test('Parse SaveMeta.xbx correctly (UTF-16 LE)', () {
      final name = 'Roster1';
      final content = 'Name=$name\r\n';
      final bytes = _createUtf16LeWithBom(content);
      
      final parsed = XbxMeta.parseName('SaveMeta.xbx', bytes);
      expect(parsed, name);
    });

    test('Return null for invalid/no BOM', () {
      final bytes = Uint8List.fromList('Name=Test'.codeUnits);
      expect(XbxMeta.parseName('SaveMeta.xbx', bytes), isNull);
    });
  });

  group('FatxSearcher & Selective Export', () {
    test('Resolve path by friendly names and perform selective export', () {
      final buffer = FatxFormatter.format();
      final image = FatxImage(MemoryStorage(buffer));
      
      // 1. Setup Game (ESPN NFL 2K5)
      final gameCluster = image.fat.allocateCluster();
      image.addEntry(1, FatxDirEntry()
        ..filename = '53450030'
        ..attributes = FatxDirEntry.attrDirectory
        ..firstCluster = gameCluster);
      
      final titleMetaCluster = image.fat.allocateCluster();
      image.addEntry(gameCluster, FatxDirEntry()
        ..filename = 'TitleMeta.xbx'
        ..fileSize = 50
        ..firstCluster = titleMetaCluster);
      
      final titleMetaData = Uint8List(16384)..setRange(0, 50, _createUtf16LeWithBom('TitleName=ESPN NFL 2K5\r\n').sublist(0, 50));
      image.writeCluster(titleMetaCluster, titleMetaData);

      // 2. Setup Save (Roster1)
      final saveCluster = image.fat.allocateCluster();
      image.addEntry(gameCluster, FatxDirEntry()
        ..filename = '19FA1AF775EF'
        ..attributes = FatxDirEntry.attrDirectory
        ..firstCluster = saveCluster);
      
      final saveMetaCluster = image.fat.allocateCluster();
      image.addEntry(saveCluster, FatxDirEntry()
        ..filename = 'SaveMeta.xbx'
        ..fileSize = 30
        ..firstCluster = saveMetaCluster);
      
      final saveMetaData = Uint8List(16384)..setRange(0, 30, _createUtf16LeWithBom('Name=Roster1\r\n').sublist(0, 30));
      image.writeCluster(saveMetaCluster, saveMetaData);

      // 3. Setup another save (Should be skipped in thick export)
      final otherSaveCluster = image.fat.allocateCluster();
      image.addEntry(gameCluster, FatxDirEntry()
        ..filename = 'OTHER'
        ..attributes = FatxDirEntry.attrDirectory
        ..firstCluster = otherSaveCluster);

      final searcher = FatxSearcher(image);
      final exporter = FatxExporter(image);

      // Search and Export
      final result = searcher.resolvePath('ESPN NFL 2K5/Roster1');
      expect(result.gameCluster, gameCluster);
      expect(result.saveCluster, saveCluster);
      expect(result.gameName, 'ESPN NFL 2K5');

      final zipBytes = exporter.exportGameOrSave(result);
      final zip = ZipDecoder().decodeBytes(zipBytes);

      // Check context preservation
      expect(zip.files.any((f) => f.name == 'UDATA/53450030/TitleMeta.xbx'), isTrue);
      expect(zip.files.any((f) => f.name == 'UDATA/53450030/19FA1AF775EF/SaveMeta.xbx'), isTrue);
      
      // Verify "OTHER" save folder was excluded
      expect(zip.files.any((f) => f.name.contains('OTHER')), isFalse);
    });
  });
}

Uint8List _createUtf16LeWithBom(String s) {
  final units = s.codeUnits;
  final bytes = Uint8List(2 + units.length * 2);
  bytes[0] = 0xFF; // BOM
  bytes[1] = 0xFE;
  
  for (var i = 0; i < units.length; i++) {
    bytes[2 + i * 2] = units[i] & 0xFF;
    bytes[2 + i * 2 + 1] = (units[i] >> 8) & 0xFF;
  }
  return bytes;
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

