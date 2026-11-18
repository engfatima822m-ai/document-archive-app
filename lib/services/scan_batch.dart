import 'dart:io';

class ScanBatch {
  final Directory _directory;
  final Map<String, FileStat> _baseline;

  ScanBatch._(this._directory, this._baseline);

  static Future<ScanBatch> start(Directory directory) async {
    await directory.create(recursive: true);
    final files = await _imageStats(directory);
    return ScanBatch._(directory, {
      for (final entry in files.entries) entry.key.toLowerCase(): entry.value,
    });
  }

  Future<List<String>> changedImages() async {
    final files = await _imageStats(_directory);
    final paths = files.entries.where((entry) {
      final current = entry.value;
      final previous = _baseline[entry.key.toLowerCase()];
      return current.size > 0 &&
          (previous == null ||
              current.modified != previous.modified ||
              current.changed != previous.changed ||
              current.size != previous.size);
    }).map((entry) => entry.key).toList();
    paths.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return paths;
  }

  static Future<Map<String, FileStat>> _imageStats(Directory directory) async {
    final files = <String, FileStat>{};
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;

      final path = entity.path.toLowerCase();
      if (!path.endsWith('.jpg') &&
          !path.endsWith('.jpeg') &&
          !path.endsWith('.png')) {
        continue;
      }

      final stat = await entity.stat();
      if (stat.type == FileSystemEntityType.file) {
        files[entity.path] = stat;
      }
    }
    return files;
  }
}
