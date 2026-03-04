# Xbox Memory Unit Tool (`xbmut`)

A pure Dart implementation for managing 8MB OG Xbox FATX Memory Unit (MU) images. This tool is designed for compatibility with **Xemu**.

## Key Features
- **Create 8MB XBOX Memory Unit files**: (Usable in XEMU).
- **List contents of Memory Units** 
- **Export contents of Memory Units**
- **Import Gamesaves into Memory Units**

---

## CLI Usage

### Compile
If you have the Dart SDK installed:
```bash
dart compile exe bin/xbox_memory_unit_tool.dart -o xbmut
```

### Commands
- `format <image_path>`: Produce a valid, blank 8MB image file.
- `ls <image_path> [dir_path]`: Recursive listing with metadata (names, sizes).
- `import <image_path> <zip_path>`: Import a save ZIP (automatically normalizes `UDATA/` paths).
- `export <image_path> <path> [zip]`: Export a directory to ZIP (supports friendly name-based paths).

### Examples
- **Create a fresh card**: `xbmut format card.bin`
- **List with names**: `xbmut ls card.bin`
- **Import a save**: `xbmut import card.bin MySave.zip`
- **Export by game name**: `xbmut export card.bin "NFL 2K5"`
- **Export specific save**: `xbmut export card.bin "NFL 2K5/Roster1"`

---

# Library API

The library provides a high-level, idiomatic Dart API for managing Xbox Memory Unit images. It abstracts away FATX clusters into a semantic hierarchy of **Titles** and **Saves**.

## Usage Examples

### 1. Formatting a New Memory Unit
```dart
import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';

void main() {
  XboxMemoryUnit mu = XboxMemoryUnit.format();
  // mu.bytes contains the raw 8MB Uint8List
}
```

### 2. Full Workflow: Create, Import, and Save
```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';

void main() {
  // 1. Create a fresh memory unit
  XboxMemoryUnit mu = XboxMemoryUnit.format();

  // 2. Read your save ZIP
  Uint8List zipBytes = File('nfl2k5_roster.zip').readAsBytesSync();

  // 3. Import the save into the memory unit
  mu.importZip(zipBytes);

  // 4. Save the final 8MB image to the filesystem
  File('xemu_mu.bin').writeAsBytesSync(mu.bytes);
}
```

### 3. Loading and Listing Content
```dart
Uint8List bytes = File('card.bin').readAsBytesSync();
XboxMemoryUnit mu = XboxMemoryUnit.fromBytes(bytes);

for (XboxTitle title in mu.titles) {
  print('Game: ${title.name} (${title.id})');
  for (XboxSave save in title.saves) {
    print('  - Save: ${save.name}');
  }
}
```

### 4. Exporting a Specific Save (Thick Export)
```dart
// Export by friendly path: "Game Name/Save Name"
Uint8List zipBytes = mu.export("ESPN NFL 2K5/Roster1");
File('Roster1.zip').writeAsBytesSync(zipBytes);
```

### 5. Accessing Metadata and Images
```dart
XboxTitle? title = mu.findTitleByName("ESPN NFL 2K5");
if (title != null && title.titleImage != null) {
  // Display game icon (TitleImage.xbx)
}
```

---

## Technical Details (FATX MU)
- **Superblock**: Offset `0x0000`, Signature `FATX`.
- **FAT Area**: Offset `0x1000`, FAT16 (2 bytes per entry).
- **Data Area**: Offset `0x2000`, Cluster 1 (Root).
- **Hybrid Paradox**:
  - `Superblock.SectorsPerCluster`: 4 (2KB)
  - `Actual Data Alignment`: 32 sectors per cluster (16KB)
- **Encoding**: All multi-byte integers are Little-Endian. Metadata files (`.xbx`) use UTF-16 LE with BOM.

---
Written with gemini cli, check specification folder for initial specification used.