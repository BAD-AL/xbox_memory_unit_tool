import 'storage.dart';

/// Creates a [FatxStorage] from a physical file.
/// This implementation throws on platforms that do not support dart:io.
FatxStorage createFileStorage(dynamic file, {bool writeAccess = true}) {
  throw UnsupportedError('Opening a physical file is not supported on this platform.');
}
