import 'dart:typed_data';

/// Xbox FATX constants for an 8MB Memory Unit (MU).
class FatxConfig {
  static const int muSize = 8388608; // 8MB
  static const int superblockOffset = 0x0000;
  static const int fatOffset = 0x1000;
  static const int dataOffset = 0x2000;
  static const int bytesPerSector = 512;
  static const int clusterSizeReal = 16384; // 32 sectors (16KB) - The "Truth"
  static const int sectorsPerClusterReported = 4; // 4 sectors (2KB) - The "Lie"
  static const int volumeIdFixed = 0x00000029;
}

/// File Allocation Table (FAT16) management.
class FatxTable {
  final Uint8List _bytes;
  static const int fatEntrySize = 2; // Uint16

  FatxTable(this._bytes) {
    if (_bytes.length != 4096) throw ArgumentError('FAT area must be 4KB');
  }

  /// Sets Entry 0 to Media Byte 0xF8FF.
  void initialize() {
    final view = ByteData.sublistView(_bytes);
    // Spec says 0xF8FF, but XEMU_Blank_card.bin shows bytes [F8, FF]
    // which is 0xFFF8 in little-endian.
    view.setUint16(0, 0xFFF8, Endian.little);
  }

  int getEntry(int index) {
    final view = ByteData.sublistView(_bytes);
    return view.getUint16(index * fatEntrySize, Endian.little);
  }

  void setEntry(int index, int value) {
    final view = ByteData.sublistView(_bytes);
    view.setUint16(index * fatEntrySize, value, Endian.little);
  }

  /// Finds the next free cluster (starting from index 2).
  int allocateCluster() {
    // 8MB / 16KB real cluster size = 512 clusters.
    // Index 1 is the Root Directory. Indices 2-512 are Data.
    for (var i = 2; i <= 512; i++) {
      if (getEntry(i) == 0x0000) {
        setEntry(i, 0xFFFF); // Mark as EOF
        return i;
      }
    }
    throw Exception('Disk full');
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

  // TODO: Implement unpackDate/Time if needed for ls/export.
}

/// Hybrid cluster mapping logic.
class FatxMapper {
  /// Returns the byte offset for a given cluster index (1-based).
  static int clusterToOffset(int clusterIndex) {
    if (clusterIndex < 1) throw ArgumentError('Cluster index must be >= 1');
    return FatxConfig.dataOffset + (clusterIndex - 1) * FatxConfig.clusterSizeReal;
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
