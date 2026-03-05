import 'dart:io';
import 'dart:typed_data';
import 'storage.dart';

/// File-based storage implementation for large drives and raw device access.
class FileStorage implements FatxStorage {
  final RandomAccessFile _file;
  final int _length;

  FileStorage(this._file, this._length);

  factory FileStorage.open(File file, {bool writeAccess = true}) {
    // Note: FileMode.append allows writing anywhere without truncating.
    final mode = writeAccess ? FileMode.append : FileMode.read;
    final raf = file.openSync(mode: mode);
    return FileStorage(raf, file.lengthSync());
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
