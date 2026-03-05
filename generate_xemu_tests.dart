import 'dart:io';

/// Usage: dart generate_xemu_tests.dart <source_zips_folder> [output_folder]
void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart generate_xemu_tests.dart <source_zips_folder> [output_folder]');
    return;
  }

  final savesDir = Directory(args[0]);
  final outDir = Directory(args.length > 1 ? args[1] : 'test_output');
  
  if (!savesDir.existsSync()) {
    print('Error: Source directory "${savesDir.path}" not found.');
    return;
  }
  
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final zips = savesDir.listSync().where((f) => f.path.endsWith('.zip')).toList();
  
  final allSavesPath = '${outDir.path}/ALL_SAVES.bin';
  print('Step 1: Creating ALL_SAVES.bin...');
  await runXbmut(['format', allSavesPath]);

  for (final zip in zips) {
    final zipPath = zip.path;
    final zipName = zip.path.split('/').last;
    print('Processing $zipName...');

    // 1. Create a temporary individual card to find the internal names
    final tempBin = '${outDir.path}/temp.bin';
    await runXbmut(['format', tempBin]);
    await runXbmut(['import', tempBin, zipPath]);

    // 2. Get the internal names via 'ls'
    final info = await runXbmut(['ls', tempBin], silent: true);
    final names = parseNames(info);
    
    if (names != null) {
      final safeGame = names.game.replaceAll(RegExp(r'[<>:"/\|?*]'), '_');
      final safeSave = names.save.replaceAll(RegExp(r'[<>:"/\|?*]'), '_');
      final newName = '$safeGame.$safeSave.bin';
      final finalPath = '${outDir.path}/$newName';
      
      print('  Internal Name: ${names.game} / ${names.save}');
      print('  Renaming to: $newName');
      
      // If file exists, add a suffix to avoid overwriting
      var actualPath = finalPath;
      var counter = 1;
      while (File(actualPath).existsSync()) {
          actualPath = finalPath.replaceFirst('.bin', '_$counter.bin');
          counter++;
      }
      File(tempBin).renameSync(actualPath);
    } else {
      print('  Warning: Could not parse internal names for $zipName');
      if (File(tempBin).existsSync()) File(tempBin).deleteSync();
    }

    // 3. Try to import into ALL_SAVES.bin
    print('  Adding to ALL_SAVES.bin...');
    final result = await runXbmut(['import', allSavesPath, zipPath], silent: true);
    if (result.contains('Disk full')) {
      print('  Skipped ALL_SAVES.bin: Disk full (standard 8MB limit)');
    }
  }

  print('Done! Files generated in ${outDir.path}/');
}

class Names {
  final String game;
  final String save;
  Names(this.game, this.save);
}

Names? parseNames(String output) {
  String? game;
  String? save;
  final lines = output.split('\n');
  
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('Game: ')) {
      final end = trimmed.lastIndexOf(' (');
      if (end != -1) game = trimmed.substring(6, end).trim();
    } else if (trimmed.contains('- Save: ')) {
      // Find the first save entry
      final start = trimmed.indexOf('- Save: ') + 8;
      final end = trimmed.lastIndexOf(' (');
      if (end != -1 && end > start) {
          save = trimmed.substring(start, end).trim();
          break; 
      }
    }
  }
  
  if (game != null && save != null) {
    return Names(game, save);
  }
  return null;
}

Future<String> runXbmut(List<String> args, {bool silent = false}) async {
  // Use the local xbmut binary if it exists, otherwise use dart run
  final exe = File('xbmut').existsSync() ? './xbmut' : 'dart';
  final procArgs = File('xbmut').existsSync() ? args : ['bin/xbox_memory_unit_tool.dart', ...args];

  final result = await Process.run(exe, procArgs);
  if (!silent && result.stdout.toString().isNotEmpty) {
    stdout.write(result.stdout);
  }
  if (result.stderr.toString().isNotEmpty) {
    stderr.write(result.stderr);
  }
  return result.stdout.toString();
}
