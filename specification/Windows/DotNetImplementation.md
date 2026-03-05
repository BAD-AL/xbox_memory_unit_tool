# .NET Framework Implementation Spec (C#)

This document specifies the internal architecture and API design for the .NET implementation of `xbmut`.

## 1. Target Environment
- **Framework:** .NET Framework 4.7.2+ (Recommended for best `Task` support).
- **Language:** C# 7.3+.

## 2. Core API Design
The API should mirror the Dart high-level API but follow C# naming conventions and idiomatic patterns (Properties, `IEnumerable`, `Task`).

### `IFatxStorage` Interface
```csharp
public interface IFatxStorage : IDisposable
{
    long Length { get; }
    byte[] Read(long offset, int count);
    void Write(long offset, byte[] data);
    void Flush();
}
```

### `XboxMemoryUnit` Class
```csharp
public class XboxMemoryUnit : IDisposable
{
    // Factories
    public static XboxMemoryUnit OpenFile(string path);
    public static XboxMemoryUnit OpenPhysicalDrive(int driveNumber);
    public static XboxMemoryUnit Format(int size = 8388608);

    // Properties
    public IEnumerable<XboxTitle> Titles { get; }
    public long FreeBytes { get; }
    public long TotalBytes { get; }

    // Methods
    public void ImportZip(byte[] zipData);
    public void Delete(string friendlyPath);
    public byte[] Export(string friendlyPath);
    public void Flush();
}
```

### `XboxTitle` and `XboxSave` Classes
```csharp
public class XboxTitle
{
    public string Id { get; }
    public string Name { get; }
    public long Size { get; }
    public DateTime ModifiedAt { get; }
    public IEnumerable<XboxSave> Saves { get; }
}

public class XboxSave
{
    public string Name { get; }
    public string FolderName { get; }
    public long Size { get; }
    public DateTime ModifiedAt { get; }
}
```

## 3. Implementation Details
- **Binary I/O:** Use `System.IO.BinaryReader` and `BinaryWriter` for low-level FAT math.
- **Async Support:** While MUs are small enough for sync I/O, `Task`-based async methods should be provided for compatibility with modern C# UI frameworks.
- **ZIP Handling:** Use `System.IO.Compression.ZipArchive` (available in .NET 4.5+).
- **Encoding:** Use `System.Text.Encoding.Unicode` (UTF-16 LE) for metadata parsing.
- **Bit Math:** Use bitwise operators to unpack the 16-bit FATX timestamps.
    - `Year = (date >> 9) + 2000`
    - `Month = (date >> 5) & 0x0F`
    - `Day = date & 0x1F`
