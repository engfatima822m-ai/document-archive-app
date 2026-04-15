import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_twain_scanner/flutter_twain_scanner.dart';

class ScannerService {
  final FlutterTwainScanner _scanner = FlutterTwainScanner();

  Future<List<String>> getAvailableScanners() async {
    try {
      final sources = await _scanner.getDataSources();
      debugPrint('Available scanners: $sources');
      return sources;
    } catch (e) {
      throw Exception('تعذر جلب أجهزة السكانر: $e');
    }
  }

  Future<List<String>> scanFromScanner(int sourceIndex) async {
    try {
      debugPrint('بدء السحب من السكانر...');
      debugPrint('sourceIndex = $sourceIndex');

      final List<String> scannedFiles = await _scanner
          .scanDocument(sourceIndex)
          .timeout(const Duration(seconds: 45));

      debugPrint('انتهى أمر السحب');
      debugPrint('scannedFiles = $scannedFiles');

      if (scannedFiles.isEmpty) {
        throw Exception('تم السحب ولكن لم يتم إرجاع أي ملفات.');
      }

      return scannedFiles;
    } on TimeoutException {
      debugPrint('Timeout: المكتبة علقت أثناء السحب');
      throw Exception('انتهت مهلة السحب. المكتبة لم تُرجع أي نتيجة.');
    } catch (e) {
      debugPrint('Scanner error: $e');
      throw Exception('فشل السحب من جهاز السكانر: $e');
    }
  }

  Future<List<String>> moveScannedFilesToDocumentFolder({
    required List<String> scannedFiles,
    required String targetFolderPath,
  }) async {
    final List<String> finalPaths = [];

    for (int i = 0; i < scannedFiles.length; i++) {
      final sourceFile = File(scannedFiles[i]);

      if (!await sourceFile.exists()) continue;

      final extension = _getExtension(scannedFiles[i]);
      final newName = 'image_${(i + 1).toString().padLeft(3, '0')}.$extension';
      final newPath = '$targetFolderPath\\$newName';

      final copied = await sourceFile.copy(newPath);
      finalPaths.add(copied.path);
    }

    return finalPaths;
  }

  String _getExtension(String path) {
    final parts = path.split('.');
    if (parts.length < 2) return 'jpg';
    return parts.last.toLowerCase();
  }
}