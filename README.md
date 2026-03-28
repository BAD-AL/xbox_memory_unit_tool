# Xbox Memory Unit Tool (`xbmut`)

A pure Dart implementation for managing Xbox FATX Memory Unit (MU) and USB images. This tool is designed for compatibility with **Xemu** and  OG Xbox memory unit image files.

Web interface: https://BAD-AL.github.io/xbmut_web/

<a href="https://https://BAD-AL.github.io/xbmut_web/">
  <img src="https://raw.githubusercontent.com/BAD-AL/xbmut_web/main/Welcome.png" alt="Welcome screen" width="400">
</a>

Web interface project: https://github.com/BAD-AL/xbmut_web 

## Key Features
- **Create Xbox Memory Unit files**: (Usable in XEMU).
- **List contents**: View games, saves, sizes, and timestamps.
- **Export content**: Selective export or full card backup to ZIP.
- **Import Gamesaves**: Automatic normalization of `UDATA/` paths.
- **Delete Content**: Recursive deletion of games and saves.
- **Physical Drive Support**: Optimized for large images and raw device access.

---

## CLI Usage

### Compile
If you have the Dart SDK installed:
```bash
dart compile exe bin/xbox_memory_unit_tool.dart -o xbmut
```

### Commands
- `format <image_path>`: Produce a valid, blank 8MB image file.
- `ls <image_path> [-s] [-t]`: List games and saves. 
    - `-s, --size`: Show recursive sizes of games and saves.
    - `-t, --time`: Show modification timestamps.
- `import <image_path> <zip_path>`: Import a save ZIP.
- `export <image_path> <path> [zip_path]`: Export content to ZIP.
    - Use `<path>` like `"Game Name/Save Name"` for selective export.
    - Use `all` as `<path>` to export the entire card as one ZIP.
    - Use `all-individual` as `<path>` to export every save to its own ZIP.
- `extract-image <image_path> <path> [out_dir/file]`: Extract and convert icons (.xbx) to .bmp.
    - Supports DXT1/DXT3 decoding and unswizzling.
    - Use `all` as `<path>` to batch convert every icon on the card.
- `rm <image_path> <path>`: Delete a game or save by friendly path.

### Examples
- **Create a fresh card**: `xbmut format card.bin`
- **List with metadata**: `xbmut ls card.bin --size --time`
- **Import a save**: `xbmut import card.bin MySave.zip`
- **Export selective**: `xbmut export card.bin "NFL 2K5/Roster1"`
- **Full backup**: `xbmut export card.bin all backup.zip`
- **Batch export**: `xbmut export card.bin all-individual ./my_saves/`
- **Extract icons**: `xbmut extract-image card.bin "NFL 2K5" roster_logo.bmp`
- **Extract all icons**: `xbmut extract-image card.bin all ./icons/`
- **Delete a save**: `xbmut rm card.bin "NFL 2K5/Roster1"`

---

## Physical Hardware (Linux)

You can use `xbmut` to manage physical Xbox-formatted USB sticks or Memory Units.

### 1. Identify the Device
```bash
lsblk
# Look for your device (e.g. /dev/sdc, usually 8MB or 32MB)
```

### 2. Read contents via Pipe
Due to some runtime restrictions on raw block devices, the most reliable way to read a physical drive is via a pipe:
```bash
sudo cat /dev/sdc | ./xbmut ls - --size
```

### 3. Creating a Raw Dump
It is always safer to work with an image file:
```bash
sudo dd if=/dev/sdc of=mu_dump.bin bs=1M
./xbmut ls mu_dump.bin
```

### 4. Modifying and Writing Back (Round-trip)
You can modify a dump and then write it back to the physical device:

1. **Dump the card**: `sudo dd if=/dev/sdc of=mu_backup.bin bs=1M`
2. **Modify the dump** (e.g., import a save): `./xbmut import mu_backup.bin MySave.zip`
3. **Write back to the card**: `sudo dd if=mu_backup.bin of=/dev/sdc bs=1M`

**Warning:** Writing back to a physical device is a destructive operation. Ensure you have the correct device path (e.g., `/dev/sdc`) and a backup of your original dump.

---

# Library API

The library provides a high-level, idiomatic Dart API. It abstracts away FATX clusters into a semantic hierarchy of **Titles** and **Saves**.

## Usage Examples

### 1. Accessing Free Space and Sizes
```dart
XboxMemoryUnit mu = XboxMemoryUnit.fromBytes(bytes);
print('Free space: ${mu.freeBytes} bytes');

for (var title in mu.titles) {
  print('${title.name} - Size: ${title.size} bytes');
  print('Last Modified: ${title.modifiedAt}');
}
```

### 2. Exporting Everything
```dart
Uint8List fullBackup = mu.exportAll();
File('everything.zip').writeAsBytesSync(fullBackup);
```

### 3. Deleting Content
```dart
mu.delete("NFL 2K5/OldSave");
```

### 4. Extracting Images (TitleImage / SaveImage)
```dart
var title = mu.findTitle("ESPN NFL 2K5");
Uint8List? bmp = title?.titleImageBmp; // Converted DXT1/DXT3 -> BMP
if (bmp != null) File('logo.bmp').writeAsBytesSync(bmp);
```

---
### 5. OG XBOX physical memory units
You can dump your memory unit to an image file for xbmut to interact with it (***Linux***). You may also be able to do this on ***Mac***, but the commands could differ.
```bash
# To read contents of a memory Unit (Linux).
# list the block devices to find the correct one (check SIZE to figure out which device it is)
lsblk

# copy the (in this case '/dev/sdd') image to file 'MEMORY_UNIT.bin'
sudo dd if=/dev/sdd of=MEMORY_UNIT_dump.bin bs=1M 

# lsit the contents of 'MEMORY_UNIT.bin' with xbmut 
xbmut ls MEMORY_UNIT.bin 
````
----

## Technical Details (FATX MU)
- **Superblock**: Offset `0x0000`, Signature `FATX`.
- **FAT Area**: Offset `0x1000`, FAT16 (2 bytes per entry).
- **Data Area**: Offset `0x2000`, Cluster 1 (Root).
- **Hybrid Paradox**:
  - `Superblock.SectorsPerCluster`: 4 (2KB)
  - `Actual Data Alignment`: 32 sectors per cluster (16KB)
- **Encoding**: Metadata files (`.xbx`) use UTF-16 LE with BOM. Timestamps are bit-packed FATX format (2000 epoch).

---
Written with gemini cli. 
Specification based on inspection of XEMU images and https://github.com/mborgerson/fatx
