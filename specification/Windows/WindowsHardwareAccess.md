# Windows Hardware Access Specification

This document details the low-level Win32 requirements for accessing physical Xbox Memory Units and USB drives on Windows.

## 1. Opening the Device
To access a physical drive (e.g., `\.\PhysicalDrive1`), the application MUST use the Win32 `CreateFile` function via P/Invoke.

### Required Flags:
- `dwDesiredAccess`: `GENERIC_READ | GENERIC_WRITE`
- `dwShareMode`: `FILE_SHARE_READ | FILE_SHARE_WRITE`
- `dwCreationDisposition`: `OPEN_EXISTING`
- `dwFlagsAndAttributes`: `FILE_ATTRIBUTE_NORMAL | FILE_FLAG_NO_BUFFERING` (Optional, but safer for raw blocks).

## 2. Volume Management (The Lock/Dismount Dance)
Windows will often prevent writes to raw sectors if the volume is currently "mounted" by the OS (even if the filesystem is unrecognized).

The following `DeviceIoControl` (IOCTL) codes MUST be sent to the drive handle before write operations:
1.  **`FSCTL_LOCK_VOLUME` (0x00090018)**: Prevents other applications from accessing the drive.
2.  **`FSCTL_DISMOUNT_VOLUME` (0x00090020)**: Forces the OS to drop its own handles to the filesystem.

## 3. Sector Alignment Constraints
When accessing `\.\PhysicalDriveX`, Windows enforces strict alignment:
- **Offset Alignment:** The seek pointer (offset) MUST be a multiple of the sector size (usually 512 bytes).
- **Buffer Alignment:** The number of bytes read or written MUST be a multiple of the sector size.

### FATX Handling:
Since FATX uses 16KB clusters (32 sectors), all cluster-based I/O is naturally aligned. However, the 4KB Superblock and 4KB FAT area also meet the 512-byte requirement.

## 4. Administrative Privileges
The application MUST include a manifest file requiring `highestAvailable` or `requireAdministrator` execution level. Raw device access is impossible without Elevation.

## 5. .NET Wrapper Implementation
It is recommended to wrap the Win32 `SafeFileHandle` in a `System.IO.FileStream` after the Handle is successfully acquired and the Volume is locked. This allows the use of standard .NET Stream methods for the logic layer.
