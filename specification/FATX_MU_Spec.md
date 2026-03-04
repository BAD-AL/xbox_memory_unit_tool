# Technical Specification: Xbox FATX Memory Unit (MU) Implementation

## 1. Introduction
This specification defines the requirements for a pure Dart implementation of the Xbox FATX filesystem, specifically optimized for 8MB Memory Unit (MU) images.

## 2. Filesystem Layout (8MB Standard)
The image must be exactly **8,388,608 bytes**.

| Offset | Size | Name | Purpose |
| :--- | :--- | :--- | :--- |
| `0x0000` | 4 KB | Superblock | Filesystem header and metadata |
| `0x1000` | 4 KB | FAT Area | File Allocation Table (FAT16) |
| `0x2000` | Variable | Data Area | Clusters containing files and folders |

### 2.1 The "Hybrid" Cluster Paradox
For 8MB Memory Units to be visible in Xemu and games like NFL 2K5, the filesystem must implement a specific contradiction:
1.  **Reported Cluster Size**: The Superblock MUST state **4 sectors per cluster (2KB)**.
2.  **Actual Data Alignment**: All internal offset calculations MUST use **32 sectors per cluster (16KB)**.

**Formula for Byte Offset of Cluster N**:
`Offset = 0x2000 + (N - 1) * 16384`

## 3. Binary Structures

### 3.0 Binary Conventions
- **Endianness**: All multi-byte integers (Uint16, Uint32) MUST be read and written as **Little-Endian**.
- **Deleted Marker**: If the first byte of a directory entry is `0xE5`, the entry is deleted and MUST be ignored during listing.

### 3.1 Superblock (Offset 0x0000)
| Offset | Type | Value | Name |
| :--- | :--- | :--- | :--- |
| 0 | String(4) | `FATX` | Signature |
| 4 | Uint32 | `0x00000029` | Volume ID (Fixed for MU) |
| 8 | Uint32 | `0x00000004` | Sectors Per Cluster (The "Lie") |
| 12 | Uint32 | `0x00000001` | Root Directory Cluster |
| 16 | Uint16 | `0x0000` | Unknown/Reserved |
| 18 | Padding | `0xFF`... | Padding to 4096 bytes |

### 3.2 Directory Entry (64 bytes)
| Offset | Type | Name | Description |
| :--- | :--- | :--- | :--- |
| 0 | Uint8 | Filename Length | Number of characters (1-42) |
| 1 | Uint8 | Attributes | See 3.2.1 |
| 2 | String(42) | Filename | Null-padded ASCII |
| 44 | Uint32 | First Cluster | Starting cluster index |
| 48 | Uint32 | File Size | Size in bytes |
| 52 | Uint16 | Creation Time | FATX encoded time |
| 54 | Uint16 | Creation Date | FATX encoded date |
| 56 | Uint16 | Mod Time | FATX encoded time |
| 58 | Uint16 | Mod Date | FATX encoded date |
| 60 | Uint16 | Access Time | FATX encoded time |
| 62 | Uint16 | Access Date | FATX encoded date |

#### 3.2.1 Attributes Bitmask
- `0x01`: Read Only
- `0x02`: Hidden
- `0x04`: System (**Note**: Our research shows `.xbx` files must have bit `0x04` or `0x02` for dashboard visibility).
- `0x10`: Directory

## 4. Logical Implementation

### 4.1 File Allocation Table (FAT16)
- Each entry is **2 bytes** (Uint16).
- **Entry 0**: Media Byte (Reserved). Write `0xF8FF`.
- **Entry 1**: Corresponds to the Root Directory cluster.
- **Values**:
  - `0x0000`: Available cluster.
  - `0xFFFF`: End of cluster chain.
  - `Other`: The index of the next cluster in the chain.

### 4.2 Directory Traversal
1. Start at Cluster 1 (Root).
2. Read 64-byte chunks.
3. If byte 0 is `0x00` or `0xFF`, stop (End of Directory).
4. If byte 0 is `0xE5`, skip (Deleted file).
5. Extract metadata and repeat.

### 4.3 Formatting a New Image
1. Create an 8MB buffer filled with `0x00`.
2. Write the Superblock at `0x0000`.
3. Initialize FAT at `0x1000`:
   - Set Entry 0 to `0xF8FF`.
   - Set Entry 1 to `0xFFFF` (Empty root).
4. **Important**: All directory clusters (including Root) should be initialized with `0x00`, not `0xFF`.

## 5. ZIP Integration
- **Import**: 
  - If a path begins with `UDATA/`, strip it. 
  - Ensure the parent TitleID directory exists.
  - Apply `0x04` attribute to `.xbx` files.
- **Export**:
  - Prepend `UDATA/` to all paths.
  - Recursively bundle files into the `archive` package structure.

## 6. Dart Specific Snippets

### Bit-Packing Timestamps
```dart
int packDate(DateTime dt) {
  return ((dt.year - 2000) & 0x7F) << 9 | (dt.month & 0x0F) << 5 | (dt.day & 0x1F);
}

int packTime(DateTime dt) {
  return (dt.hour & 0x1F) << 11 | (dt.minute & 0x3F) << 5 | (dt.second ~/ 2 & 0x1F);
}
```

### Offset Calculation
```dart
int clusterToOffset(int clusterIndex) {
  const int clusterOffset = 0x2000;
  const int clusterSize = 16384; // 16KB Truth
  return clusterOffset + (clusterIndex - 1) * clusterSize;
}
```
