import 'dart:typed_data';
import 'fatx.dart';

// FatxImage - refers to a 8MB XBOX/XEMU 'memory unit' file.

class FatxImage {
  final Uint8List bytes;
  late final FatxTable fat;

  FatxImage(this.bytes) {
    if (bytes.length != FatxConfig.muSize) {
      throw ArgumentError('Image must be exactly ${FatxConfig.muSize} bytes');
    }
    final fatArea = Uint8List.sublistView(bytes, FatxConfig.fatOffset, FatxConfig.fatOffset + 4096);
    fat = FatxTable(fatArea);
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
    final totalBytes = chain.length * FatxConfig.clusterSizeReal;
    final result = Uint8List(totalBytes);
    
    for (var i = 0; i < chain.length; i++) {
      final offset = FatxMapper.clusterToOffset(chain[i]);
      result.setRange(i * FatxConfig.clusterSizeReal, (i + 1) * FatxConfig.clusterSizeReal, bytes.sublist(offset, offset + FatxConfig.clusterSizeReal));
    }

    return result.sublist(0, size > totalBytes ? totalBytes : size);
  }

  /// Lists entries in a directory (starting cluster).
  List<FatxDirEntry> listDirectory(int cluster) {
    final entries = <FatxDirEntry>[];
    final chain = getClusterChain(cluster);

    for (final c in chain) {
      final offset = FatxMapper.clusterToOffset(c);
      final clusterData = bytes.sublist(offset, offset + FatxConfig.clusterSizeReal);
      
      for (var i = 0; i < FatxConfig.clusterSizeReal; i += FatxDirEntry.entrySize) {
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

  /// Writes a 16KB cluster of data.
  void writeCluster(int clusterIndex, Uint8List data) {
    if (data.length != FatxConfig.clusterSizeReal) {
      throw ArgumentError('Must write exactly ${FatxConfig.clusterSizeReal} bytes');
    }
    final offset = FatxMapper.clusterToOffset(clusterIndex);
    bytes.setRange(offset, offset + FatxConfig.clusterSizeReal, data);
  }

  /// Adds a directory entry to a directory (cluster).
  void addEntry(int dirCluster, FatxDirEntry newEntry) {
    final chain = getClusterChain(dirCluster);
    for (final c in chain) {
      final offset = FatxMapper.clusterToOffset(c);
      for (var i = 0; i < FatxConfig.clusterSizeReal; i += FatxDirEntry.entrySize) {
        final entryOffset = offset + i;
        final entryBytes = bytes.sublist(entryOffset, entryOffset + FatxDirEntry.entrySize);
        final entry = FatxDirEntry.fromBytes(entryBytes);

        if (entry.isEnd || entry.isDeleted) {
          bytes.setRange(entryOffset, entryOffset + FatxDirEntry.entrySize, newEntry.toBytes());
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
    final padding = Uint8List(FatxConfig.clusterSizeReal)
      ..fillRange(0, FatxConfig.clusterSizeReal, 0xFF);
    writeCluster(newCluster, padding);
    
    // Write the new entry to the first slot of the new cluster
    final entryOffset = FatxMapper.clusterToOffset(newCluster);
    bytes.setRange(entryOffset, entryOffset + FatxDirEntry.entrySize, newEntry.toBytes());
  }
}
