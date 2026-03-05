import 'dart:io';
import 'package:args/args.dart';
import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addCommand('ls')
    ..addCommand('import')
    ..addCommand('export')
    ..addCommand('rm')
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

  try {
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
      case 'rm':
        handleRm(command);
        break;
      default:
        printUsage(parser);
    }
  } catch (e) {
    _printError(e);
  }
}

void _printError(Object e) {
  if (e is UnimplementedError) {
    print('Error: This feature is not yet implemented.');
  } else if (e is FileSystemException) {
    print('Error: ${e.message}${e.path != null ? " (Path: ${e.path})" : ""}');
    if (e.osError != null) {
      print('OS Error: ${e.osError!.message} (Code: ${e.osError!.errorCode})');
    }
  } else {
    final msg = e.toString().replaceFirst('Exception: ', '');
    print('Error: $msg');
  }
}

void printUsage(ArgParser parser) {
  print('Usage: xbmut <command> [arguments]');
  print('');
  print('Commands:');
  print('  ls <image_path>                      List all games and saves');
  print('  import <image_path> <zip_path>       Import a save ZIP');
  print('  export <image_path> <path> [zip]     Export a directory to ZIP (Supports name-based paths)');
  print('  rm <image_path> <path>               Delete a game or save by friendly path');
  print('  format <image_path>                  Produce a formatted 8MB image file');
  print('');
  print('Examples:');
  print('  xbmut format card.bin                Create a fresh 8MB memory unit');
  print('  xbmut ls card.bin                    List all games and saves');
  print('  xbmut import card.bin MySave.zip     Import a save (strips UDATA/ prefix)');
  print('  xbmut export card.bin "NFL 2K5"      Export all game saves to "NFL 2K5.zip"');
  print('  xbmut export card.bin "NFL 2K5/R1"   Export specific save to "R1.zip"');
  print('  xbmut export card.bin 53450030/19FA  Export by literal IDs');
  print('  xbmut rm card.bin "NFL 2K5/R1"       Delete specific save');
}

void handleRm(ArgResults results) {
  if (results.rest.length < 2) {
    print('Usage: xbmut rm <image_path> <path>');
    return;
  }

  final imagePath = results.rest[0];
  final searchPath = results.rest[1];

  final file = File(imagePath);
  if (!file.existsSync()) {
    print('Error: File $imagePath does not exist.');
    return;
  }

  final mu = XboxMemoryUnit.fromFile(file);

  print('Searching for $searchPath to delete...');
  mu.delete(searchPath);
  mu.flush();
  print('Done.');
}

void handleFormat(ArgResults results) {
  if (results.rest.length != 1) {
    print('Usage: xbmut format <image_path>');
    return;
  }

  final path = results.rest[0];
  print('Formatting $path...');
  final mu = XboxMemoryUnit.format();
  File(path).writeAsBytesSync(mu.bytes);
  print('Done.');
}

void handleLs(ArgResults results) {
  if (results.rest.isEmpty) {
    print('Usage: xbmut ls <image_path>');
    return;
  }

  final file = File(imagePath);
  if (!file.existsSync()) {
    print('Error: File ${file.absolute.path} does not exist.');
    return;
  }

  // Use fromFile to avoid loading entire image into RAM
  final mu = XboxMemoryUnit.fromFile(file, writeAccess: false);

  print('Listing ${file.absolute.path}...');
  for (final title in mu.titles) {
    print('Game: ${title.name} (${title.id})');
    for (final save in title.saves) {
      print('  - Save: ${save.name} (${save.folderName})');
    }
  }
}

void handleImport(ArgResults results) {
  if (results.rest.length < 2) {
    print('Usage: xbmut import <image_path> <zip_path>');
    return;
  }

  final imagePath = results.rest[0];
  final zipPath = results.rest[1];

  final file = File(imagePath);
  if (!file.existsSync()) {
    print('Error: File $imagePath does not exist.');
    return;
  }

  if (!File(zipPath).existsSync()) {
    print('Error: ZIP $zipPath does not exist.');
    return;
  }

  final mu = XboxMemoryUnit.fromFile(file);

  print('Importing $zipPath into $imagePath...');
  final zipBytes = File(zipPath).readAsBytesSync();
  mu.importZip(zipBytes);
  mu.flush();
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

  final file = File(imagePath);
  if (!file.existsSync()) {
    print('Error: File $imagePath does not exist.');
    return;
  }

  final mu = XboxMemoryUnit.fromFile(file, writeAccess: false);

  print('Searching for $searchPath...');
  final zipBytes = mu.export(searchPath);
  print('Exporting to $zipPath...');
  File(zipPath).writeAsBytesSync(zipBytes);
  print('Done.');
}
