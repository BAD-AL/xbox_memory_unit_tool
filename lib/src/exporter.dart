import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'fatx.dart';
import 'fatx_image.dart';

class FatxExporter {
  final FatxImage image;

  FatxExporter(this.image);

  /// Exports the content of a directory into a ZIP archive.
  /// Prepends 'UDATA/' as per TR-7.
  Uint8List exportToZip(int startCluster, String rootPrefix) {
    final archive = Archive();
    _recursiveAdd(archive, startCluster, 'UDATA/$rootPrefix');
    
    final encoder = ZipEncoder();
    return Uint8List.fromList(encoder.encode(archive)!);
  }

  void _recursiveAdd(Archive archive, int cluster, String currentPath) {
    final entries = image.listDirectory(cluster);
    
    for (final entry in entries) {
      final path = '$currentPath${entry.filename}';
      if (entry.isDirectory) {
        // ZIP format doesn't *require* directory entries, but they are good practice.
        // For FATX, directories are often empty or just containers.
        if (entry.firstCluster != 0) {
          _recursiveAdd(archive, entry.firstCluster, '$path/');
        }
      } else {
        final fileData = image.readChain(entry.firstCluster, entry.fileSize);
        final file = ArchiveFile(path, entry.fileSize, fileData);
        archive.addFile(file);
      }
    }
  }
}
