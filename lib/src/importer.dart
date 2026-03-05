import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'fatx.dart';
import 'fatx_image.dart';

class FatxImporter {
  final FatxImage image;

  FatxImporter(this.image);

  /// Imports a ZIP archive into the FATX image.
  void importZip(Uint8List zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);

    for (final file in archive) {
      if (!file.isFile) continue;

      String path = file.name;
      // TR-6: Path Normalization (strip UDATA/)
      if (path.startsWith('UDATA/') || path.startsWith('udata/')) {
        path = path.substring(6);
      }

      final parts = path.split('/').where((p) => p.isNotEmpty).toList();
      _importFile(parts, file.content as Uint8List);
    }
  }

  void _importFile(List<String> pathParts, Uint8List data) {
    var currentDirCluster = 1; // Root

    // Ensure parent directories exist
    for (var i = 0; i < pathParts.length - 1; i++) {
      final dirName = pathParts[i];
      if (dirName.length > 42) throw Exception('Filename too long: $dirName');

      final entries = image.listDirectory(currentDirCluster);
      final existing = entries.where((e) => e.filename == dirName && e.isDirectory).toList();

      if (existing.isEmpty) {
        // Create directory
        final newCluster = image.fat.allocateCluster();
        final dirEntry = FatxDirEntry()
          ..filename = dirName
          ..filenameLength = dirName.length
          ..attributes = FatxDirEntry.attrDirectory
          ..firstCluster = newCluster
          ..fileSize = 0;
        
        // Initialize directory cluster with 0xFF (XEMU Gold Standard)
        final padding = Uint8List(FatxConfig.clusterSizeReal)
          ..fillRange(0, FatxConfig.clusterSizeReal, 0xFF);
        image.writeCluster(newCluster, padding);
        
        image.addEntry(currentDirCluster, dirEntry);
        currentDirCluster = newCluster;
      } else {
        currentDirCluster = existing.first.firstCluster;
      }
    }

    final filename = pathParts.last;
    if (filename.length > 42) throw Exception('Filename too long: $filename (TR-9)');

    // Write file
    final firstCluster = _writeFileData(data);
    final entry = FatxDirEntry()
      ..filename = filename
      ..filenameLength = filename.length
      ..attributes = filename.toLowerCase().endsWith('.xbx') ? FatxDirEntry.attrSystem : 0x00
      ..firstCluster = firstCluster
      ..fileSize = data.length;

    image.addEntry(currentDirCluster, entry);
  }

  int _writeFileData(Uint8List data) {
    if (data.isEmpty) return 0;

    final numClusters = (data.length / FatxConfig.clusterSizeReal).ceil();
    final clusters = <int>[];
    for (var i = 0; i < numClusters; i++) {
      clusters.add(image.fat.allocateCluster());
    }

    // Link FAT chain
    for (var i = 0; i < clusters.length - 1; i++) {
      image.fat.setEntry(clusters[i], clusters[i + 1]);
    }
    image.fat.setEntry(clusters.last, 0xFFFF);

    // Write data
    for (var i = 0; i < clusters.length; i++) {
      final start = i * FatxConfig.clusterSizeReal;
      var end = (i + 1) * FatxConfig.clusterSizeReal;
      
      final chunk = Uint8List(FatxConfig.clusterSizeReal);
      if (end > data.length) {
          final sub = data.sublist(start);
          chunk.setRange(0, sub.length, sub);
      } else {
          final sub = data.sublist(start, end);
          chunk.setRange(0, FatxConfig.clusterSizeReal, sub);
      }
      image.writeCluster(clusters[i], chunk);
    }

    return clusters.first;
  }
}
