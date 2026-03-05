import 'dart:io';
import 'dart:typed_data';
import 'storage.dart';

/// File-based storage implementation for large drives and raw device access.
class FileStorage implements FatxStorage {
  final RandomAccessFile _file;
  final int _length;

  FileStorage(this._file, this._length);

  factory FileStorage.open(File file, {bool writeAccess = true}) {
    // FileMode.read is standard O_RDONLY.
    // FileMode.append is O_RDWR | O_APPEND | O_CREAT. 
    // Some block devices reject O_APPEND or O_CREAT.
    final mode = writeAccess ? FileMode.append : FileMode.read;
    final raf = file.openSync(mode: mode);
    try {
      final length = raf.lengthSync();
      return FileStorage(raf, length);
    } catch (e) {
      raf.closeSync();
      rethrow;
    }
  }

  @override
  int get length => _length;

  @override
  Uint8List read(int offset, int length) {
    _file.setPositionSync(offset);
    return _file.readSync(length);
  }

  @override
  void write(int offset, Uint8List data) {
    _file.setPositionSync(offset);
    _file.writeFromSync(data);
  }

  @override
  void flush() {
    _file.flushSync();
  }

  void close() {
    _file.closeSync();
  }
}
