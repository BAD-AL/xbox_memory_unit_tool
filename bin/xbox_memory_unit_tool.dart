import 'dart:io';
import 'package:args/args.dart';
import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addCommand('ls')
    ..addCommand('import')
    ..addCommand('export')
    ..addCommand('format');

  ArgResults results;
  try {
    results = parser.parse(arguments);
  } catch (e) {
    printUsage(parser);
    return;
  }

  final command = results.command;
  if (command == null) {
    printUsage(parser);
    return;
  }

  switch (command.name) {
    case 'format':
      handleFormat(command);
      break;
    case 'ls':
      handleLs(command);
      break;
    case 'import':
      handleImport(command);
      break;
    case 'export':
      handleExport(command);
      break;
    default:
      printUsage(parser);
  }
}

void printUsage(ArgParser parser) {
  print('Usage: xbmut <command> [arguments]');
  print('');
  print('Commands:');
  print('  ls <image_path> [dir_path]           List files recursively starting at <dir_path>');
  print('  import <image_path> <zip_path>       Import a save ZIP');
  print('  export <image_path> <path> [zip]     Export a directory to ZIP (Supports name-based paths)');
  print('  format <image_path>                  Produce a formatted 8MB image file');
  print('');
  print('Examples:');
  print('  xbmut format card.bin                Create a fresh 8MB memory unit');
  print('  xbmut ls card.bin                    List all games and saves');
  print('  xbmut import card.bin MySave.zip     Import a save (strips UDATA/ prefix)');
  print('  xbmut export card.bin "NFL 2K5"      Export all game saves to "NFL 2K5.zip"');
  print('  xbmut export card.bin "NFL 2K5/R1"   Export specific save to "R1.zip"');
  print('  xbmut export card.bin 53450030/19FA  Export by literal IDs');
}

void handleFormat(ArgResults results) {
  if (results.rest.length != 1) {
    print('Usage: xbmut format <image_path>');
    return;
  }

  final path = results.rest[0];
  print('Formatting $path...');
  final buffer = FatxFormatter.format();
  File(path).writeAsBytesSync(buffer);
  print('Done.');
}

void handleLs(ArgResults results) {
  if (results.rest.isEmpty) {
    print('Usage: xbmut ls <image_path> [dir_path]');
    return;
  }

  final imagePath = results.rest[0];
  final startDir = results.rest.length > 1 ? results.rest[1] : '/';

  if (!File(imagePath).existsSync()) {
    print('Error: File $imagePath does not exist.');
    return;
  }

  final bytes = File(imagePath).readAsBytesSync();
  final image = FatxImage(bytes);

  var targetCluster = 1;
  if (startDir != '/' && startDir != '') {
    final parts = startDir.split('/').where((p) => p.isNotEmpty);
    for (final part in parts) {
      final entries = image.listDirectory(targetCluster);
      final dir = entries.firstWhere(
        (e) => e.filename == part && e.isDirectory,
        orElse: () => throw Exception('Directory $part not found in $startDir'),
      );
      targetCluster = dir.firstCluster;
    }
  }

  print('Listing $imagePath starting at $startDir...');
  _listRecursive(image, targetCluster, '');
}

void _listRecursive(FatxImage image, int cluster, String indent) {
  final entries = image.listDirectory(cluster);
  for (final entry in entries) {
    String meta = '';
    if (entry.filename == 'TitleMeta.xbx' || entry.filename == 'SaveMeta.xbx') {
      meta = _extractMetaName(image, entry);
    }

    print('$indent${entry.isDirectory ? "[DIR] " : "      "}${entry.filename} ${meta != '' ? "('$meta' " : "("}${entry.fileSize} bytes)');
    if (entry.isDirectory && entry.firstCluster != 0) {
      _listRecursive(image, entry.firstCluster, '$indent  ');
    }
  }
}

String _extractMetaName(FatxImage image, FatxDirEntry entry) {
  try {
    final bytes = image.readChain(entry.firstCluster, entry.fileSize);
    return XbxMeta.parseName(entry.filename, bytes) ?? '';
  } catch (e) {
    // Silently fail for malformed meta files
  }
  return '';
}

void handleImport(ArgResults results) {
  if (results.rest.length < 2) {
    print('Usage: xbmut import <image_path> <zip_path>');
    return;
  }

  final imagePath = results.rest[0];
  final zipPath = results.rest[1];

  if (!File(imagePath).existsSync()) {
    print('Error: File $imagePath does not exist.');
    return;
  }

  if (!File(zipPath).existsSync()) {
    print('Error: ZIP $zipPath does not exist.');
    return;
  }

  final imageBytes = File(imagePath).readAsBytesSync();
  final image = FatxImage(imageBytes);
  final importer = FatxImporter(image);

  print('Importing $zipPath into $imagePath...');
  final zipBytes = File(zipPath).readAsBytesSync();
  importer.importZip(zipBytes);
  
  // Save changes
  File(imagePath).writeAsBytesSync(imageBytes);
  print('Done.');
}

void handleExport(ArgResults results) {
  if (results.rest.length < 2) {
    print('Usage: xbmut export <image_path> <search_path> [zip_path]');
    return;
  }

  final imagePath = results.rest[0];
  final searchPath = results.rest[1];
  
  // Infer ZIP path if not provided
  String zipPath;
  if (results.rest.length > 2) {
    zipPath = results.rest[2];
  } else {
    final parts = searchPath.split('/').where((p) => p.isNotEmpty);
    zipPath = '${parts.last}.zip';
  }

  if (!File(imagePath).existsSync()) {
    print('Error: File $imagePath does not exist.');
    return;
  }

  final bytes = File(imagePath).readAsBytesSync();
  final image = FatxImage(bytes);
  final searcher = FatxSearcher(image);
  final exporter = FatxExporter(image);

  try {
    print('Searching for $searchPath...');
    final result = searcher.resolvePath(searchPath);
    
    final targetDesc = result.saveName != null ? '${result.gameName}/${result.saveName}' : result.gameName;
    print('Exporting $targetDesc to $zipPath...');
    
    final zipBytes = exporter.exportGameOrSave(result);
    File(zipPath).writeAsBytesSync(zipBytes);
    print('Done.');
  } catch (e) {
    print('Error: ${e.toString()}');
  }
}
