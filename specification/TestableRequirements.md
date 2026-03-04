# Testable Requirements: FATX MU Implementation

This document defines the acceptance criteria for a valid pure-Dart FATX implementation.

## 1. Functional Requirements

| ID | Name | Description |
| :--- | :--- | :--- |
| **TR-1** | Formatting Signature | A newly formatted image MUST contain `FATX` at offset `0x00`. |
| **TR-2** | Volume ID | A newly formatted 8MB image MUST have the bytes `29 00 00 00` at offset `0x04`. |
| **TR-3** | Hybrid Offsets | Cluster 2 MUST start at exactly `0x6000` (8KB Superblock/FAT + 16KB Cluster 1). |
| **TR-4** | Zero Initialization | New directory clusters MUST be initialized with `0x00` bytes. |
| **TR-5** | End-of-Directory | The reader MUST recognize both `0x00` and `0xFF` as directory terminators. |
| **TR-6** | Path Normalization | Importing `UDATA/TitleID/file` MUST strip `UDATA/` and place `TitleID` at the FATX root. |
| **TR-7** | ZIP Compatibility | Exporting a directory MUST prepend `UDATA/` to all entries in the resulting ZIP. |
| **TR-8** | Hidden Attribute | Any file ending in `.xbx` MUST have the attribute bit `0x04` set in its directory entry. |
| **TR-9** | Filename Limits | The implementation MUST reject or truncate filenames longer than 42 characters. |
| **TR-10** | FAT16 Chaining | Files > 16,384 bytes MUST correctly link multiple clusters in the FAT area (`0x1000`). |
| **TR-11** | Integrity Comparison | A comparison between two images MUST pass if they are bit-identical, ignoring Volume IDs and Timestamps. |

## 2. Test Data Assets
The following files in `test/test_files` should be used for verification:
- `XEMU_Blank_card.bin`: Reference for TR-1, TR-2, TR-4.
- `XEMU_Created_default_roster.bin`: Reference for TR-3, TR-8, TR-10.
- `test_import_minimal.zip`: Source for TR-6 and TR-8 verification.

## 3. Diagnostic Comparison Tool
Any implementation MUST include a Dart utility to verify parity.

### Requirements for Comparison Tool:
1. Load two 8MB `.bin` files into memory.
2. Zero-out the Volume ID (offsets 4-7) in both buffers.
3. Zero-out all Timestamp fields in every 64-byte directory entry discovered.
4. Compare the resulting buffers.
5. Print "PASS" if identical, or provide the offset of the first mismatch.
