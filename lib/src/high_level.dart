import 'dart:typed_data';
import 'fatx.dart';
import 'fatx_image.dart';
import 'formatter.dart';
import 'importer.dart';
import 'exporter.dart';
import 'searcher.dart';
import 'xbx_meta.dart';
import 'xbx_image_converter.dart';
import 'models.dart';
import 'storage.dart';
import 'storage_factory_compat.dart';

// High-level API types

class XboxMemoryUnit {
  final FatxImage _image;

  XboxMemoryUnit._(this._image);

  /// Formats a new Xbox Memory Unit in memory. Default is 8MB.
  factory XboxMemoryUnit.format({int size = 8388608}) {
    final buffer = FatxFormatter.format(size: size);
    return XboxMemoryUnit._(FatxImage(MemoryStorage(buffer)));
  }

  /// Loads an Xbox Memory Unit from an in-memory buffer.
  factory XboxMemoryUnit.fromBytes(Uint8List bytes) {
    return XboxMemoryUnit._(FatxImage(MemoryStorage(bytes)));
  }

  /// Opens an Xbox Memory Unit from a physical file or device.
  /// Not available on web.
  factory XboxMemoryUnit.fromFile(dynamic file, {bool writeAccess = true}) {
    final storage = createFileStorage(file, writeAccess: writeAccess);
    return XboxMemoryUnit._(FatxImage(storage));
  }

  /// Returns the raw bytes of the memory unit.
  Uint8List get bytes {
    if (_image.storage is MemoryStorage) {
      return (_image.storage as MemoryStorage).bytes;
    }
    return _image.storage.read(0, _image.storage.length);
  }

  /// Flushes any pending writes to the underlying storage.
  void flush() {
    _image.storage.flush();
  }

  /// Returns the number of free bytes available.
  int get freeBytes => _image.fat.countFreeClusters() * _image.config.clusterSizeReal;

  /// Returns the total capacity of the storage in bytes.
  int get totalBytes => _image.storage.length;

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

  /// Deletes a game or save by friendly path (e.g., "NFL 2K5/Roster1").
  void delete(String path) {
    final searcher = FatxSearcher(_image);
    final result = searcher.resolvePath(path);

    if (result.saveCluster != null) {
      // Delete specific save folder inside the game folder
      final gameEntries = _image.listDirectory(result.gameCluster);
      final saveFolder = gameEntries.firstWhere((e) => e.firstCluster == result.saveCluster).filename;
      _image.deleteEntry(result.gameCluster, saveFolder);
    } else {
      // Delete the entire game folder from root
      final rootEntries = _image.listDirectory(1);
      final gameFolder = rootEntries.firstWhere((e) => e.firstCluster == result.gameCluster).filename;
      _image.deleteEntry(1, gameFolder);
    }
  }

  /// Exports the entire memory unit content to a ZIP (prepends UDATA/).
  Uint8List exportAll() {
    final exporter = FatxExporter(_image);
    return exporter.exportToZip(1, "");
  }

  /// Exports a specific game or save by friendly path (e.g., "NFL 2K5/Roster1").
  /// Use "all" to export everything.
  Uint8List export(String path) {
    if (path.toLowerCase() == 'all') {
      return exportAll();
    }
    final searcher = FatxSearcher(_image);
    final result = searcher.resolvePath(path);
    final exporter = FatxExporter(_image);
    return exporter.exportGameOrSave(result);
  }

  /// Finds a title by its internal name or Title ID (case-insensitive).
  XboxTitle? findTitle(String nameOrId) {
    final search = nameOrId.toUpperCase();
    for (final title in titles) {
      if (title.name.toUpperCase() == search || title.id.toUpperCase() == search) return title;
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

  /// Total size of all files in this title (including all saves).
  int get size => _mu._image.calculateDirectorySize(_entry.firstCluster);

  /// Last modification time of this title folder.
  DateTime get modifiedAt => _entry.modifiedAt;

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

  /// Finds a save by its friendly name or folder name (case-insensitive).
  XboxSave? findSave(String nameOrFolder) {
    final search = nameOrFolder.toUpperCase();
    for (final save in saves) {
      if (save.name.toUpperCase() == search || save.folderName.toUpperCase() == search) return save;
    }
    return null;
  }

  /// Returns the TitleImage.xbx converted to BMP, if present.
  Uint8List? get titleImageBmp {
    final bytes = titleImage;
    return bytes != null ? XbxImageConverter.convertToBmp(bytes, unswizzle: false) : null;
  }

  /// Returns the TitleMeta.xbx bytes, if present.
  Uint8List? get titleMeta => _readFile('TitleMeta.xbx');

  Uint8List? _readFile(String filename) {
    final entries = _mu._image.listDirectory(_entry.firstCluster);
    final search = filename.toUpperCase();
    final file = entries.where((e) => e.filename.toUpperCase() == search).toList();
    if (file.isEmpty) return null;
    return _mu._image.readChain(file.first.firstCluster, file.first.fileSize);
  }
}

class XboxSave {
  final XboxTitle parent;
  final FatxDirEntry _entry;
  final String folderName;
  late final String name;

  XboxSave._(this.parent, this._entry) : folderName = _entry.filename {
    final metaBytes = _readFile('SaveMeta.xbx');
    name = (metaBytes != null ? XbxMeta.parseName('SaveMeta.xbx', metaBytes) : null) ?? folderName;
  }

  /// Total size of all files in this specific save.
  int get size => parent._mu._image.calculateDirectorySize(_entry.firstCluster);

  /// Last modification time of this specific save.
  DateTime get modifiedAt => _entry.modifiedAt;

  /// Exports this specific save to a ZIP buffer (Thick Export with Game context).
  Uint8List exportZip() {
    final result = FatxSearchResult(
      gameCluster: parent._entry.firstCluster,
      saveCluster: _entry.firstCluster,
      gameName: parent.name,
      saveName: name,
    );
    final exporter = FatxExporter(parent._mu._image);
    return exporter.exportGameOrSave(result);
  }

  /// Returns the SaveImage.xbx bytes, if present (checks save folder then parent title folder).
  Uint8List? get saveImage => _readFile('SaveImage.xbx') ?? parent._readFile('SaveImage.xbx');

  /// Returns the SaveImage.xbx converted to BMP, if present.
  Uint8List? get saveImageBmp {
    final bytes = saveImage;
    return bytes != null ? XbxImageConverter.convertToBmp(bytes, unswizzle: false) : null;
  }

  Uint8List? _readFile(String filename) {
    final entries = parent._mu._image.listDirectory(_entry.firstCluster);
    final search = filename.toUpperCase();
    final file = entries.where((e) => e.filename.toUpperCase() == search).toList();
    if (file.isEmpty) return null;
    return parent._mu._image.readChain(file.first.firstCluster, file.first.fileSize);
  }
}
