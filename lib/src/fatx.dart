import 'dart:typed_data';
import 'storage.dart';

/// Xbox FATX constants and dynamic configuration.
class FatxConfig {
  final int muSize;
  final int clusterSizeReal;
  final int sectorsPerClusterReported;

  static const int superblockOffset = 0x0000;
  static const int fatOffset = 0x1000;
  static const int dataOffset = 0x2000;
  static const int bytesPerSector = 512;
  static const int volumeIdFixed = 0x00000029;

  FatxConfig({required this.muSize, required this.clusterSizeReal, required this.sectorsPerClusterReported});

  /// Calculates the appropriate geometry for a given MU size.
  factory FatxConfig.forSize(int size) {
    // We target a 4KB FAT (2048 entries) starting at 0x1000 and Data at 0x2000.
    final usableBytes = size - dataOffset;
    
    // Determine cluster size such that we don't exceed 2048 clusters.
    // 8MB, 16MB, 32MB -> 16KB clusters.
    // 64MB -> 32KB clusters.
    int real;
    int reported;

    if (usableBytes <= 2048 * 16384) {
      real = 16384;
      reported = 4;
    } else if (usableBytes <= 2048 * 32768) {
      real = 32768;
      reported = 8;
    } else {
      real = 65536;
      reported = 16;
    }

    return FatxConfig(
      muSize: size,
      clusterSizeReal: real,
      sectorsPerClusterReported: reported,
    );
  }

  /// Detects the geometry of an existing FATX image.
  factory FatxConfig.detect(FatxStorage storage) {
    final bytes = storage.read(0, 16);
    final view = ByteData.sublistView(bytes);
    
    final sig = String.fromCharCodes(bytes.sublist(0, 4));
    if (sig != 'FATX') throw Exception('Not a valid FATX image (Invalid signature)');

    final reportedSectors = view.getUint32(8, Endian.little);
    
    // The "Hybrid Paradox": Real cluster size is 8x the reported size for MUs.
    final real = reportedSectors * 8 * bytesPerSector;

    return FatxConfig(
      muSize: storage.length,
      clusterSizeReal: real,
      sectorsPerClusterReported: reportedSectors,
    );
  }
}

/// File Allocation Table (FAT16) management.
class FatxTable {
  final FatxStorage storage;
  final FatxConfig config;
  static const int fatEntrySize = 2; // Uint16

  FatxTable(this.storage, this.config);

  /// Sets Entry 0 to Media Byte 0xF8FF.
  void initialize() {
    setEntry(0, 0xFFF8); // Little-endian [F8, FF]
  }

  int getEntry(int index) {
    final bytes = storage.read(FatxConfig.fatOffset + index * fatEntrySize, fatEntrySize);
    final view = ByteData.sublistView(bytes);
    return view.getUint16(0, Endian.little);
  }

  void setEntry(int index, int value) {
    final bytes = Uint8List(2);
    final view = ByteData.view(bytes.buffer);
    view.setUint16(0, value, Endian.little);
    storage.write(FatxConfig.fatOffset + index * fatEntrySize, bytes);
  }

  /// Finds the next free cluster (starting from index 2).
  int allocateCluster() {
    // Total clusters = (StorageSize - DataOffset) / ClusterSize
    final usableBytes = storage.length - FatxConfig.dataOffset;
    final maxClusters = (usableBytes / config.clusterSizeReal).floor();
    
    // FAT size is fixed at 4KB for our current implementation of MUs.
    const limit = 2048; 
    final searchLimit = maxClusters > limit ? limit : maxClusters;

    for (var i = 2; i <= searchLimit; i++) {
      if (getEntry(i) == 0x0000) {
        setEntry(i, 0xFFFF); // Mark as EOF
        return i;
      }
    }
    throw Exception('Disk full');
  }

  /// Counts the number of clusters marked as free (0x0000).
  int countFreeClusters() {
    final usableBytes = storage.length - FatxConfig.dataOffset;
    final maxClusters = (usableBytes / config.clusterSizeReal).floor();
    const limit = 2048;
    final searchLimit = maxClusters > limit ? limit : maxClusters;
    
    var count = 0;
    for (var i = 2; i <= searchLimit; i++) {
      if (getEntry(i) == 0x0000) {
        count++;
      }
    }
    return count;
  }

  /// Frees a cluster chain starting from [startCluster].
  void freeChain(int startCluster) {
    if (startCluster < 2) return;
    var current = startCluster;
    while (current != 0xFFFF && current != 0x0000) {
      final next = getEntry(current);
      setEntry(current, 0x0000);
      current = next;
    }
  }
}

/// Binary bit-packing for FATX timestamps.
class FatxTimeUtils {
  /// Packs a DateTime into a 16-bit FATX date.
  /// (Year - 2000) << 9 | Month << 5 | Day
  static int packDate(DateTime dt) {
    return ((dt.year - 2000) & 0x7F) << 9 | (dt.month & 0x0F) << 5 | (dt.day & 0x1F);
  }

  /// Packs a DateTime into a 16-bit FATX time.
  /// Hour << 11 | Minute << 5 | (Second / 2)
  static int packTime(DateTime dt) {
    return (dt.hour & 0x1F) << 11 | (dt.minute & 0x3F) << 5 | (dt.second ~/ 2 & 0x1F);
  }

  /// Unpacks a 16-bit FATX date and time into a DateTime object.
  static DateTime unpack(int date, int time) {
    final day = date & 0x1F;
    final month = (date >> 5) & 0x0F;
    final year = ((date >> 9) & 0x7F) + 2000;

    final sec = (time & 0x1F) * 2;
    final min = (time >> 5) & 0x3F;
    final hour = (time >> 11) & 0x1F;

    // Safety check for invalid dates (common in corrupted/empty entries)
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return DateTime(2000, 1, 1);
    }

    return DateTime(year, month, day, hour, min, sec);
  }
}

/// Hybrid cluster mapping logic.
class FatxMapper {
  /// Returns the byte offset for a given cluster index (1-based).
  static int clusterToOffset(int clusterIndex, FatxConfig config) {
    if (clusterIndex < 1) throw ArgumentError('Cluster index must be >= 1');
    return FatxConfig.dataOffset + (clusterIndex - 1) * config.clusterSizeReal;
  }
}

/// 64-byte FATX Directory Entry.
class FatxDirEntry {
  static const int entrySize = 64;
  static const int deletedMarker = 0xE5;
  static const int attrReadOnly = 0x01;
  static const int attrHidden = 0x02;
  static const int attrSystem = 0x04;
  static const int attrDirectory = 0x10;

  int filenameLength = 0;
  int attributes = 0;
  String filename = '';
  int firstCluster = 0;
  int fileSize = 0;
  
  // Timestamps
  int creationTime = 0;
  int creationDate = 0;
  int modificationTime = 0;
  int modificationDate = 0;
  int accessTime = 0;
  int accessDate = 0;

  bool get isDirectory => (attributes & attrDirectory) != 0;
  bool get isDeleted => filenameLength == deletedMarker;
  bool get isEnd => filenameLength == 0x00 || filenameLength == 0xFF;

  DateTime get modifiedAt => FatxTimeUtils.unpack(modificationDate, modificationTime);
  DateTime get createdAt => FatxTimeUtils.unpack(creationDate, creationTime);
  DateTime get accessedAt => FatxTimeUtils.unpack(accessDate, accessTime);

  FatxDirEntry();

  /// Parses a 64-byte buffer into a FatxDirEntry.
  factory FatxDirEntry.fromBytes(Uint8List bytes) {
    final entry = FatxDirEntry();
    final view = ByteData.sublistView(bytes);

    entry.filenameLength = view.getUint8(0);
    if (entry.isEnd || entry.isDeleted) return entry;

    entry.attributes = view.getUint8(1);
    
    // Filename is 42 chars, null padded ASCII
    final nameBytes = bytes.sublist(2, 2 + 42);
    final validLen = entry.filenameLength > 42 ? 42 : entry.filenameLength;
    entry.filename = String.fromCharCodes(nameBytes.sublist(0, validLen));

    entry.firstCluster = view.getUint32(44, Endian.little);
    entry.fileSize = view.getUint32(48, Endian.little);
    
    entry.creationTime = view.getUint16(52, Endian.little);
    entry.creationDate = view.getUint16(54, Endian.little);
    entry.modificationTime = view.getUint16(56, Endian.little);
    entry.modificationDate = view.getUint16(58, Endian.little);
    entry.accessTime = view.getUint16(60, Endian.little);
    entry.accessDate = view.getUint16(62, Endian.little);

    return entry;
  }

  /// Serializes the entry into a 64-byte buffer.
  Uint8List toBytes() {
    final bytes = Uint8List(64);
    final view = ByteData.sublistView(bytes);

    // Ensure filename length is current
    final actualLength = filename.length > 42 ? 42 : filename.length;
    view.setUint8(0, actualLength);
    view.setUint8(1, attributes);
    
    // Filename (truncated to 42 chars)
    final nameCodes = filename.codeUnits;
    for (var i = 0; i < 42; i++) {
      view.setUint8(2 + i, i < nameCodes.length ? nameCodes[i] : 0xFF);
    }

    view.setUint32(44, firstCluster, Endian.little);
    view.setUint32(48, fileSize, Endian.little);
    
    view.setUint16(52, creationTime, Endian.little);
    view.setUint16(54, creationDate, Endian.little);
    view.setUint16(56, modificationTime, Endian.little);
    view.setUint16(58, modificationDate, Endian.little);
    view.setUint16(60, accessTime, Endian.little);
    view.setUint16(62, accessDate, Endian.little);

    return bytes;
  }
}
