import 'dart:typed_data';
import 'fatx.dart';
import 'storage.dart';

// FatxImage - refers to a XBOX/XEMU 'memory unit' or USB drive.

class FatxImage {
  final FatxStorage storage;
  late final FatxTable fat;
  late final FatxConfig config;

  FatxImage(this.storage) {
    if (storage.length < 1024 * 1024) {
      throw ArgumentError('Storage must be at least 1MB');
    }
    config = FatxConfig.detect(storage);
    fat = FatxTable(storage, config);
  }

  /// Returns the cluster chain for a given start cluster.
  List<int> getClusterChain(int startCluster) {
    if (startCluster == 0) return [];
    final chain = <int>[startCluster];
    var current = startCluster;
    while (true) {
      final next = fat.getEntry(current);
      if (next == 0xFFFF || next == 0x0000 || next == 0xFFF7) break;
      chain.add(next);
      current = next;
    }
    return chain;
  }

  /// Reads all data for a given cluster chain.
  Uint8List readChain(int startCluster, int size) {
    final chain = getClusterChain(startCluster);
    final totalCapacity = chain.length * config.clusterSizeReal;
    
    final result = Uint8List(totalCapacity);
    for (var i = 0; i < chain.length; i++) {
      final offset = FatxMapper.clusterToOffset(chain[i], config);
      final clusterData = storage.read(offset, config.clusterSizeReal);
      result.setRange(i * config.clusterSizeReal, (i + 1) * config.clusterSizeReal, clusterData);
    }

    return result.sublist(0, size > totalCapacity ? totalCapacity : size);
  }

  /// Lists entries in a directory (starting cluster).
  List<FatxDirEntry> listDirectory(int cluster) {
    final entries = <FatxDirEntry>[];
    final chain = getClusterChain(cluster);

    for (final c in chain) {
      final offset = FatxMapper.clusterToOffset(c, config);
      final clusterData = storage.read(offset, config.clusterSizeReal);
      
      for (var i = 0; i < config.clusterSizeReal; i += FatxDirEntry.entrySize) {
        final entryBytes = clusterData.sublist(i, i + FatxDirEntry.entrySize);
        final entry = FatxDirEntry.fromBytes(entryBytes);
        
        if (entry.isEnd) return entries;
        if (!entry.isDeleted) {
          entries.add(entry);
        }
      }
    }
    return entries;
  }

  /// Writes a cluster of data.
  void writeCluster(int clusterIndex, Uint8List data) {
    if (data.length != config.clusterSizeReal) {
      throw ArgumentError('Must write exactly ${config.clusterSizeReal} bytes');
    }
    final offset = FatxMapper.clusterToOffset(clusterIndex, config);
    storage.write(offset, data);
  }

  /// Adds a directory entry to a directory (cluster).
  void addEntry(int dirCluster, FatxDirEntry newEntry) {
    final chain = getClusterChain(dirCluster);
    for (final c in chain) {
      final offset = FatxMapper.clusterToOffset(c, config);
      final clusterData = storage.read(offset, config.clusterSizeReal);

      for (var i = 0; i < config.clusterSizeReal; i += FatxDirEntry.entrySize) {
        final entryOffset = offset + i;
        final entryBytes = clusterData.sublist(i, i + FatxDirEntry.entrySize);
        final entry = FatxDirEntry.fromBytes(entryBytes);

        if (entry.isEnd || entry.isDeleted) {
          storage.write(entryOffset, newEntry.toBytes());
          return;
        }
      }
    }

    // If no empty entries, extend the directory chain by allocating a new cluster.
    final lastCluster = chain.last;
    final newCluster = fat.allocateCluster(); // Allocates and marks as 0xFFFF
    
    // Link the previous last cluster to the new cluster
    fat.setEntry(lastCluster, newCluster);
    
    // Initialize new cluster with 0xFF (XEMU/FATX standard for empty directory space)
    final padding = Uint8List(config.clusterSizeReal)
      ..fillRange(0, config.clusterSizeReal, 0xFF);
    writeCluster(newCluster, padding);
    
    // Write the new entry to the first slot of the new cluster
    final entryOffset = FatxMapper.clusterToOffset(newCluster, config);
    storage.write(entryOffset, newEntry.toBytes());
  }

  /// Deletes an entry by marking its first byte as 0xE5 and freeing its FAT chain.
  void deleteEntry(int parentCluster, String filename) {
    final chain = getClusterChain(parentCluster);
    for (final c in chain) {
      final offset = FatxMapper.clusterToOffset(c, config);
      final clusterData = storage.read(offset, config.clusterSizeReal);

      for (var i = 0; i < config.clusterSizeReal; i += FatxDirEntry.entrySize) {
        final entryOffset = offset + i;
        final entry = FatxDirEntry.fromBytes(clusterData.sublist(i, i + FatxDirEntry.entrySize));

        if (entry.isEnd) return;
        if (entry.filename.toUpperCase() == filename.toUpperCase() && !entry.isDeleted) {
          // 1. If it's a directory, recursively delete all entries inside first
          if (entry.isDirectory && entry.firstCluster != 0) {
            final children = listDirectory(entry.firstCluster);
            for (final child in children) {
              deleteEntry(entry.firstCluster, child.filename);
            }
          }

          // 2. Free the FAT chain for this file/directory itself
          if (entry.firstCluster != 0) {
            fat.freeChain(entry.firstCluster);
          }

          // 3. Mark the entry as deleted (0xE5) in the parent directory
          final marker = Uint8List(1)..[0] = FatxDirEntry.deletedMarker;
          storage.write(entryOffset, marker);
          return;
        }
      }
    }
    throw Exception('Entry not found: $filename');
  }

  /// Recursively calculates the total size of all files in a directory.
  int calculateDirectorySize(int cluster) {
    if (cluster == 0) return 0;
    var total = 0;
    final entries = listDirectory(cluster);
    for (final entry in entries) {
      if (entry.isDirectory) {
        total += calculateDirectorySize(entry.firstCluster);
      } else {
        total += entry.fileSize;
      }
    }
    return total;
  }
}
