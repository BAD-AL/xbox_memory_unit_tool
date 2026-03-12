import 'dart:io';
import 'storage.dart';
import 'storage_io.dart';

/// Creates a [FatxStorage] from a physical file (Native implementation).
FatxStorage createFileStorage(dynamic file, {bool writeAccess = true}) {
  if (file is! File) {
    throw ArgumentError('Expected a dart:io File, but got ${file.runtimeType}');
  }
  return FileStorage.open(file, writeAccess: writeAccess);
}
