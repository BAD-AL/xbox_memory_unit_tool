# Project Checklist: Xbox Memory Unit Tool (xbmut)

- [x] **Phase 1: Foundations**
    - [x] Update `pubspec.yaml` with `archive` and `args` packages.
    - [x] Define core FATX constants and binary structures (Superblock, DirEntry).
    - [x] Implement bit-packing utilities for FATX date/time.
- [x] **Phase 2: Core Filesystem Logic**
    - [x] Implement `format` logic (8MB image creation).
    - [x] Implement FAT16 chain traversal and cluster-to-offset mapping.
    - [x] Implement Directory Entry parser/serializer.
- [x] **Phase 3: CLI Commands**
    - [x] `format <image_path>`: Produce valid MU image.
    - [x] `ls <image_path> [dir_path]`: Recursive listing.
    - [x] `export <image_path> <src_dir> <zip>`: FATX to ZIP.
    - [x] `import <image_path> <zip_path>`: ZIP to FATX.
- [x] **Phase 4: Validation**
    - [x] Verify parity against `XEMU_Blank_card.bin`.
    - [x] Verify parity against `XEMU_Created_default_roster.bin`.
    - [x] Verify ZIP round-tripping with `test_import_minimal.zip`.

*Status: Completed*
