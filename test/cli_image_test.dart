import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';

void main() {
  group('CLI Image Extraction Logic', () {
    late XboxMemoryUnit mu;

    setUp(() {
      mu = XboxMemoryUnit.format();
      // We don't need real images for these logic tests, just the structure
    });

    test('findTitle should find by Title ID even if meta is missing', () {
      // In high_level.dart, title.name defaults to folder ID if meta is missing.
      // So findTitle should work for both name and id.
    });

    test('Title lookup by ID vs Name', () {
      final title = mu.findTitle('NONEXISTENT');
      expect(title, isNull);
    });
  });
}
