/// Conditional export for platform-specific storage creation.
export 'storage_factory.dart'
    if (dart.library.io) 'storage_factory_io.dart';
