import 'fatx.dart';
import 'fatx_image.dart';
import 'xbx_meta.dart';
import 'models.dart';

class FatxSearcher {
  final FatxImage image;

  FatxSearcher(this.image);

  /// Resolves a path like "Game Name/Save Name" or "53450030/19FA1AF775EF".
  FatxSearchResult resolvePath(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) throw Exception('Empty path');

    final gameSearch = parts[0];
    final rootEntries = image.listDirectory(1);

    // 1. Find Game
    FatxDirEntry? gameEntry;
    String? resolvedGameName;

    for (final entry in rootEntries) {
      if (!entry.isDirectory) continue;
      
      // Try literal TitleID match
      if (entry.filename.toUpperCase() == gameSearch.toUpperCase()) {
        gameEntry = entry;
        resolvedGameName = _getInternalName(entry, 'TitleMeta.xbx') ?? entry.filename;
        break;
      }

      // Try TitleMeta match
      final name = _getInternalName(entry, 'TitleMeta.xbx');
      if (name != null && name.toUpperCase() == gameSearch.toUpperCase()) {
        gameEntry = entry;
        resolvedGameName = name;
        break;
      }
    }

    if (gameEntry == null) throw Exception('Game not found: $gameSearch');

    // 2. Find Save (if requested)
    if (parts.length > 1) {
      final saveSearch = parts[1];
      final gameEntries = image.listDirectory(gameEntry.firstCluster);
      FatxDirEntry? saveEntry;
      String? resolvedSaveName;

      for (final entry in gameEntries) {
        if (!entry.isDirectory) continue;

        // Try literal folder name match
        if (entry.filename.toUpperCase() == saveSearch.toUpperCase()) {
          saveEntry = entry;
          resolvedSaveName = _getInternalName(entry, 'SaveMeta.xbx') ?? entry.filename;
          break;
        }

        // Try SaveMeta match
        final name = _getInternalName(entry, 'SaveMeta.xbx');
        if (name != null && name.toUpperCase() == saveSearch.toUpperCase()) {
          saveEntry = entry;
          resolvedSaveName = name;
          break;
        }
      }

      if (saveEntry == null) throw Exception('Save not found: $saveSearch');

      return FatxSearchResult(
        gameCluster: gameEntry.firstCluster,
        saveCluster: saveEntry.firstCluster,
        gameName: resolvedGameName!,
        saveName: resolvedSaveName,
      );
    }

    return FatxSearchResult(
      gameCluster: gameEntry.firstCluster,
      gameName: resolvedGameName!,
    );
  }

  String? _getInternalName(FatxDirEntry dir, String metaFile) {
    final entries = image.listDirectory(dir.firstCluster);
    final metaEntry = entries.where((e) => e.filename == metaFile).toList();
    if (metaEntry.isEmpty) return null;

    final bytes = image.readChain(metaEntry.first.firstCluster, metaEntry.first.fileSize);
    return XbxMeta.parseName(metaFile, bytes);
  }
}
