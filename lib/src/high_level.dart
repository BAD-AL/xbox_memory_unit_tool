import 'dart:typed_data';
import 'fatx.dart';
import 'fatx_image.dart';
import 'formatter.dart';
import 'importer.dart';
import 'exporter.dart';
import 'searcher.dart';
import 'xbx_meta.dart';
import 'models.dart';

// High-level API types

class XboxMemoryUnit {
  final FatxImage _image;

  XboxMemoryUnit._(this._image);

  /// Formats a new 8MB Xbox Memory Unit.
  factory XboxMemoryUnit.format() {
    final buffer = FatxFormatter.format();
    return XboxMemoryUnit._(FatxImage(buffer));
  }

  /// Loads an Xbox Memory Unit from an 8MB buffer.
  factory XboxMemoryUnit.fromBytes(Uint8List bytes) {
    return XboxMemoryUnit._(FatxImage(bytes));
  }

  /// Returns the raw 8MB buffer.
  Uint8List get bytes => _image.bytes;

  /// Returns a list of all games/titles on the memory unit.
  List<XboxTitle> get titles {
    final entries = _image.listDirectory(1); // Root
    return entries
        .where((e) => e.isDirectory)
        .map((e) => XboxTitle._(this, e))
        .toList();
  }

  /// Imports a save ZIP into the memory unit.
  void importZip(Uint8List zipBytes) {
    final importer = FatxImporter(_image);
    importer.importZip(zipBytes);
  }

  /// Exports a specific game or save by friendly path (e.g., "NFL 2K5/Roster1").
  Uint8List export(String path) {
    final searcher = FatxSearcher(_image);
    final result = searcher.resolvePath(path);
    final exporter = FatxExporter(_image);
    return exporter.exportGameOrSave(result);
  }

  /// Finds a title by its internal name (case-insensitive).
  XboxTitle? findTitleByName(String name) {
    final searchName = name.toUpperCase();
    for (final title in titles) {
      if (title.name.toUpperCase() == searchName) return title;
    }
    return null;
  }
}

class XboxTitle {
  final XboxMemoryUnit _mu;
  final FatxDirEntry _entry;
  late final String name;

  XboxTitle._(this._mu, this._entry) {
    final metaBytes = _readFile('TitleMeta.xbx');
    name = (metaBytes != null ? XbxMeta.parseName('TitleMeta.xbx', metaBytes) : null) ?? _entry.filename;
  }

  String get id => _entry.filename;

  /// Returns a list of all saves belonging to this title.
  List<XboxSave> get saves {
    final entries = _mu._image.listDirectory(_entry.firstCluster);
    return entries
        .where((e) => e.isDirectory)
        .map((e) => XboxSave._(this, e))
        .toList();
  }

  /// Returns the TitleImage.xbx bytes, if present.
  Uint8List? get titleImage => _readFile('TitleImage.xbx');

  /// Returns the TitleMeta.xbx bytes, if present.
  Uint8List? get titleMeta => _readFile('TitleMeta.xbx');

  Uint8List? _readFile(String filename) {
    final entries = _mu._image.listDirectory(_entry.firstCluster);
    final file = entries.where((e) => e.filename == filename).toList();
    if (file.isEmpty) return null;
    return _mu._image.readChain(file.first.firstCluster, file.first.fileSize);
  }
}

class XboxSave {
  final XboxTitle parent;
  final FatxDirEntry _entry;
  late final String name;

  XboxSave._(this.parent, this._entry) {
    final metaBytes = _readFile('SaveMeta.xbx');
    name = (metaBytes != null ? XbxMeta.parseName('SaveMeta.xbx', metaBytes) : null) ?? _entry.filename;
  }

  String get folderName => _entry.filename;

  /// Returns the SaveImage.xbx bytes, if present (checks save folder then parent title folder).
  Uint8List? get saveImage => _readFile('SaveImage.xbx') ?? parent._readFile('SaveImage.xbx');

  Uint8List? _readFile(String filename) {
    final entries = parent._mu._image.listDirectory(_entry.firstCluster);
    final file = entries.where((e) => e.filename == filename).toList();
    if (file.isEmpty) return null;
    return parent._mu._image.readChain(file.first.firstCluster, file.first.fileSize);
  }
}
