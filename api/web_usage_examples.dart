import 'dart:typed_data';
import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';

/// This file contains examples of how to use the `xbox_memory_unit_tool` library
/// in a web-based environment. In a web app, you'll typically be working with
/// [Uint8List] buffers representing file content from file uploads or for downloads.

/// 1. CREATE: How to create a new, formatted 8MB Xbox Memory Unit image.
///
/// This is useful when a user wants to start with a fresh memory card.
Uint8List createNewMemoryUnit() {
  // XboxMemoryUnit.format() creates an 8MB buffer formatted with FATX.
  final mu = XboxMemoryUnit.format();
  
  // Return the raw bytes of the new memory unit.
  // In a web app, you would then trigger a browser download for these bytes.
  return mu.bytes;
}

/// 2. LS: How to list the contents of an existing Memory Unit.
///
/// Takes the raw [muBytes] (e.g., from a file upload) and returns a human-readable list.
void listMemoryUnitContents(Uint8List muBytes) {
  // Load the MU from the uploaded bytes.
  final mu = XboxMemoryUnit.fromBytes(muBytes);
  
  print('Memory Unit Contents:');
  print('Total Size: ${mu.totalBytes} bytes');
  print('Free Space: ${mu.freeBytes} bytes');
  print('---');

  // mu.titles returns a list of XboxTitle objects representing games/titles on the card.
  for (final title in mu.titles) {
    print('Game: ${title.name} (ID: ${title.id})');
    print('  Total Size: ${title.size} bytes');
    print('  Last Modified: ${title.modifiedAt}');
    
    // Each title has a list of XboxSave objects.
    for (final save in title.saves) {
      print('    - Save: ${save.name} (${save.folderName})');
      print('      Size: ${save.size} bytes');
      print('      Modified: ${save.modifiedAt}');

      // Metadata: Titles and Saves often contain binary image data (SaveImage.xbx, TitleImage.xbx).
      // These can be converted to data URIs or blobs for display in the browser.
      if (save.saveImage != null) {
        print('      Has Save Image: ${save.saveImage!.length} bytes');
        
        // Convert to BMP for web display
        final bmpBytes = save.saveImageBmp;
        if (bmpBytes != null) {
          print('      Save Image converted to BMP: ${bmpBytes.length} bytes');
        }
      }
    }
  }
}

/// 3. IMAGES: How to extract and display Title/Save icons in a web browser.
///
/// Converts binary .xbx data into a standard BMP format that browsers can handle.
Uint8List? getTitleImage(Uint8List muBytes, String titleName) {
  final mu = XboxMemoryUnit.fromBytes(muBytes);
  final title = mu.findTitle(titleName);
  
  // The library unswizzles and decodes DXT1/DXT3 compression.
  // Returns a standard 32-bit BMP Uint8List.
  return title?.titleImageBmp;
}

/// 4. IMPORT: How to import a save (ZIP) into an existing Memory Unit.
///
/// Takes the [muBytes] of the card and [saveZipBytes] of the save to import.
/// Returns the updated MU bytes.
Uint8List importSaveIntoMemoryUnit(Uint8List muBytes, Uint8List saveZipBytes) {
  // 1. Load the MU.
  final mu = XboxMemoryUnit.fromBytes(muBytes);
  
  // 2. Import the ZIP. The library handles unpacking and placing files
  // in the correct FATX directory structure.
  mu.importZip(saveZipBytes);
  
  // 3. Return the updated MU bytes.
  return mu.bytes;
}

/// 4. EXPORT SAVE: How to export a specific save from a Memory Unit as a ZIP.
///
/// Takes the [muBytes] and a friendly path (e.g., "NFL 2K5/Roster1").
/// Returns the ZIP bytes of the save.
Uint8List exportSaveAsZip(Uint8List muBytes, String savePath) {
  // 1. Load the MU.
  final mu = XboxMemoryUnit.fromBytes(muBytes);
  
  // 2. Export the save. The path can be "Game Name/Save Name" 
  // or "GameFolderName/SaveFolderName" (e.g. "45530001/000000000001").
  // Using "all" as the path will export the entire MU content to a ZIP.
  final zipBytes = mu.export(savePath);
  
  return zipBytes;
}

/// 5. SAVE MU IMAGE: How to obtain the raw image for saving to disk.
///
/// If you've performed operations like `delete` or `importZip`, 
/// you need to get the final bytes to save the file.
Uint8List getModifiedImage(XboxMemoryUnit mu) {
  // mu.bytes returns the current state of the memory unit as a Uint8List.
  return mu.bytes;
}

/// Example of a combined workflow:
/// Upload MU -> Delete a Save -> Import a new Save -> Download modified MU.
Uint8List swapSaves(Uint8List muBytes, String saveToDelete, Uint8List newSaveZip) {
  final mu = XboxMemoryUnit.fromBytes(muBytes);
  
  // Delete the old save.
  mu.delete(saveToDelete);
  
  // Import the new save.
  mu.importZip(newSaveZip);
  
  // Return the result for download.
  return mu.bytes;
}
