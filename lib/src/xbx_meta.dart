import 'dart:typed_data';

class XbxMeta {
  /// Extracts the name value from TitleMeta.xbx or SaveMeta.xbx content.
  /// Expects UTF-16 LE with BOM (FF FE).
  static String? parseName(String filename, Uint8List bytes) {
    if (bytes.length < 2) return null;
    
    // Check for UTF-16 LE BOM (FF FE)
    if (bytes[0] != 0xFF || bytes[1] != 0xFE) return null;

    final utf16Bytes = bytes.sublist(2);
    final units = <int>[];
    for (var i = 0; i < utf16Bytes.length - 1; i += 2) {
      units.add(utf16Bytes[i] | (utf16Bytes[i + 1] << 8));
    }
    
    final content = String.fromCharCodes(units).trim();
    
    if (filename == 'TitleMeta.xbx' && content.startsWith('TitleName=')) {
      return _clean(content.substring(10));
    } else if (filename == 'SaveMeta.xbx' && content.startsWith('Name=')) {
      return _clean(content.substring(5));
    }
    
    return null;
  }

  static String _clean(String s) {
    // Split by carriage return or newline and take the first part
    final line = s.split('\r').first.split('\n').first;
    return line.trim();
  }
}
