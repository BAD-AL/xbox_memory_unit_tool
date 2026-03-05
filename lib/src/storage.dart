import 'dart:typed_data';

/// Abstract storage interface for FATX operations.
/// Decouples the filesystem logic from the underlying byte source.
abstract class FatxStorage {
  int get length;
  
  /// Reads a chunk of data from the storage.
  Uint8List read(int offset, int length);
  
  /// Writes a chunk of data to the storage.
  void write(int offset, Uint8List data);

  /// Ensures all pending writes are flushed to the underlying medium.
  void flush();
}

/// In-memory storage implementation (Web-compatible and for .bin files).
class MemoryStorage implements FatxStorage {
  final Uint8List _bytes;

  MemoryStorage(this._bytes);

  @override
  int get length => _bytes.length;

  @override
  Uint8List read(int offset, int length) {
    if (offset + length > _bytes.length) {
      throw RangeError('Read beyond storage bounds');
    }
    // Returns a view to avoid unnecessary copies
    return Uint8List.sublistView(_bytes, offset, offset + length);
  }

  @override
  void write(int offset, Uint8List data) {
    if (offset + data.length > _bytes.length) {
      throw RangeError('Write beyond storage bounds');
    }
    _bytes.setRange(offset, offset + data.length, data);
  }

  @override
  void flush() {
    // No-op for memory storage
  }

  Uint8List get bytes => _bytes;
}
