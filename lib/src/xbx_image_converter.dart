import 'dart:typed_data';
import 'dart:math';

class XbxImageConverter {
  /// Converts an XPR0 (.xbx) image to a BMP.
  /// Returns null if the format is unsupported or invalid.
  static Uint8List? convertToBmp(Uint8List xbxData, {bool unswizzle = false}) {
    if (xbxData.length < 20) return null;
    
    // Check for XPR0 magic
    if (xbxData[0] != 0x58 || xbxData[1] != 0x50 || xbxData[2] != 0x52 || xbxData[3] != 0x30) {
      return null; 
    }

    // XPR0 Header:
    // 0x04: Total size (Little Endian)
    // 0x08: Header size / Data start (Little Endian)
    final bd = ByteData.view(xbxData.buffer, xbxData.offsetInBytes, xbxData.length);
    int dataOffset = bd.getUint32(8, Endian.little);
    
    if (dataOffset >= xbxData.length) return null;

    // Detect format from Resource Descriptor (Offset 0x18 in XPR0)
    // 0x0C = DXT1, 0x0E = DXT3, 0x0F = DXT5
    int formatByte = xbxData[0x19];
    bool isDxt1 = formatByte == 0x0C;
    bool isDxt3 = formatByte == 0x0E;

    int width = 128;
    int height = 128;

    int remaining = xbxData.length - dataOffset;
    
    if (remaining >= 16384) {
      width = 128;
      height = 128;
    } else if (remaining >= 8192) {
      // Could be 128x128 DXT1 or 64x64 DXT3/5
      if (isDxt1) {
        width = 128; height = 128;
      } else {
        width = 64; height = 64;
      }
    } else if (remaining >= 2048) {
      width = 64;
      height = 64;
    } else {
      return null;
    }

    final rawPixels = xbxData.sublist(dataOffset);
    Uint8List rgba;
    
    if (isDxt3) {
      rgba = _decodeDXT3(rawPixels, width, height);
    } else if (isDxt1) {
      rgba = _decodeDXT1(rawPixels, width, height);
    } else {
      // Fallback for other 32-bit formats if detected
      rgba = Uint8List(width * height * 4);
      final count = width * height * 4;
      for (var i = 0; i < count && i < rawPixels.length; i += 4) {
        rgba[i] = rawPixels[i + 2]; // R
        rgba[i+1] = rawPixels[i + 1]; // G
        rgba[i+2] = rawPixels[i]; // B
        rgba[i+3] = rawPixels[i + 3]; // A
      }
    }

    if (unswizzle) {
      rgba = _unswizzle(rgba, width, height);
    }

    return _createBmp(rgba, width, height);
  }

  /// Decodes DXT3 (BC2) texture data.
  static Uint8List _decodeDXT3(Uint8List data, int width, int height) {
    final rgba = Uint8List(width * height * 4);
    var offset = 0;

    for (var y = 0; y < height; y += 4) {
      for (var x = 0; x < width; x += 4) {
        if (offset + 16 > data.length) break;

        // DXT3 Alpha block (64-bits: 16 * 4-bit values)
        final alphaBytes = data.sublist(offset, offset + 8);
        offset += 8;

        // DXT1 Color block (same as DXT1 but always 4-color)
        final color0 = data[offset] | (data[offset + 1] << 8);
        final color1 = data[offset + 2] | (data[offset + 3] << 8);
        final indices = data[offset + 4] | (data[offset + 5] << 8) | (data[offset + 6] << 16) | (data[offset + 7] << 24);
        offset += 8;

        final colors = _expandDXT1Colors(color0, color1, force4Color: true);

        for (var i = 0; i < 16; i++) {
          final idx = (indices >> (i * 2)) & 0x03;
          final px = x + (i % 4);
          final py = y + (i ~/ 4);
          
          if (px < width && py < height) {
            final destIdx = (py * width + px) * 4;
            rgba[destIdx] = colors[idx * 4];     // R
            rgba[destIdx + 1] = colors[idx * 4 + 1]; // G
            rgba[destIdx + 2] = colors[idx * 4 + 2]; // B
            
            // Extract 4-bit alpha and expand to 8-bit (e.g. 0xA -> 0xAA)
            final alpha4 = (alphaBytes[i ~/ 2] >> ((i % 2) * 4)) & 0x0F;
            rgba[destIdx + 3] = (alpha4 << 4) | alpha4;
          }
        }
      }
    }
    return rgba;
  }

  /// Decodes DXT1 (BC1) texture data.
  static Uint8List _decodeDXT1(Uint8List data, int width, int height) {
    final rgba = Uint8List(width * height * 4);
    var offset = 0;

    for (var y = 0; y < height; y += 4) {
      for (var x = 0; x < width; x += 4) {
        if (offset + 8 > data.length) break;

        final color0 = data[offset] | (data[offset + 1] << 8);
        final color1 = data[offset + 2] | (data[offset + 3] << 8);
        final indices = data[offset + 4] | (data[offset + 5] << 8) | (data[offset + 6] << 16) | (data[offset + 7] << 24);
        offset += 8;

        final colors = _expandDXT1Colors(color0, color1);

        for (var i = 0; i < 16; i++) {
          final idx = (indices >> (i * 2)) & 0x03;
          final px = x + (i % 4);
          final py = y + (i ~/ 4);
          
          if (px < width && py < height) {
            final destIdx = (py * width + px) * 4;
            rgba[destIdx] = colors[idx * 4];     // R
            rgba[destIdx + 1] = colors[idx * 4 + 1]; // G
            rgba[destIdx + 2] = colors[idx * 4 + 2]; // B
            rgba[destIdx + 3] = 255;               // A
          }
        }
      }
    }
    return rgba;
  }

  static Uint8List _expandDXT1Colors(int c0, int c1, {bool force4Color = false}) {
    final colors = Uint8List(16);
    
    // RGB565 to RGB888
    void decode565(int c, int off) {
      colors[off] = ((c >> 11) & 0x1F) << 3;
      colors[off + 1] = ((c >> 5) & 0x3F) << 2;
      colors[off + 2] = (c & 0x1F) << 3;
    }

    decode565(c0, 0);
    decode565(c1, 4);

    if (c0 > c1 || force4Color) {
      colors[8] = ((2 * colors[0] + colors[4]) ~/ 3);
      colors[9] = ((2 * colors[1] + colors[5]) ~/ 3);
      colors[10] = ((2 * colors[2] + colors[6]) ~/ 3);

      colors[12] = ((colors[0] + 2 * colors[4]) ~/ 3);
      colors[13] = ((colors[1] + 2 * colors[5]) ~/ 3);
      colors[14] = ((colors[2] + 2 * colors[6]) ~/ 3);
    } else {
      colors[8] = ((colors[0] + colors[4]) ~/ 2);
      colors[9] = ((colors[1] + colors[5]) ~/ 2);
      colors[10] = ((colors[2] + colors[6]) ~/ 2);

      colors[12] = 0; colors[13] = 0; colors[14] = 0; // Transparent
    }
    return colors;
  }

  /// Unswizzles a texture using Morton order.
  static Uint8List _unswizzle(Uint8List swizzled, int width, int height) {
    final unswizzled = Uint8List(swizzled.length);
    final bpp = 4; // Assuming 32-bit RGBA for the buffer

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final swizzledOffset = _getSwizzleOffset(x, y, width, height) * bpp;
        final linearOffset = (y * width + x) * bpp;
        
        if (swizzledOffset + 4 <= swizzled.length) {
          unswizzled.setRange(linearOffset, linearOffset + 4, swizzled.sublist(swizzledOffset, swizzledOffset + 4));
        }
      }
    }
    return unswizzled;
  }

  static int _getSwizzleOffset(int x, int y, int width, int height) {
    int addr = 0;
    int mask = 1;
    for (int i = 1; i < (width > height ? width : height); i <<= 1) {
      if (i < width) {
        if ((x & i) != 0) addr |= mask;
        mask <<= 1;
      }
      if (i < height) {
        if ((y & i) != 0) addr |= mask;
        mask <<= 1;
      }
    }
    return addr;
  }

  /// Creates a simple 32-bit BMP from RGBA data.
  static Uint8List _createBmp(Uint8List rgba, int width, int height) {
    final size = 54 + rgba.length;
    final bmp = Uint8List(size);
    final bd = ByteData.view(bmp.buffer);

    // File Header
    bmp[0] = 0x42; bmp[1] = 0x4D; // BM
    bd.setUint32(2, size, Endian.little);
    bd.setUint32(10, 54, Endian.little); // Offset to data

    // DIB Header
    bd.setUint32(14, 40, Endian.little); // Size of DIB
    bd.setUint16(18, width, Endian.little);
    bd.setUint32(22, -height, Endian.little); // Top-down
    bd.setUint16(26, 1, Endian.little); // Planes
    bd.setUint16(28, 32, Endian.little); // BPP
    bd.setUint32(34, rgba.length, Endian.little);

    // Pixel data (BMP expects BGRA)
    for (var i = 0; i < rgba.length; i += 4) {
      final r = rgba[i];
      final g = rgba[i + 1];
      final b = rgba[i + 2];
      final a = rgba[i + 3];
      
      bmp[54 + i] = b;
      bmp[54 + i + 1] = g;
      bmp[54 + i + 2] = r;
      bmp[54 + i + 3] = a;
    }

    return bmp;
  }
}
