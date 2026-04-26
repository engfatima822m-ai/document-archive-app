import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_twain_scanner/flutter_twain_scanner.dart';

class ScannerService {
  FlutterTwainScanner? _scanner;

  /// 🔹 إعادة تهيئة السكانر (حل مشكلة التعليق)
  Future<void> _resetScanner() async {
    try {
      debugPrint('🔄 إعادة تهيئة السكانر...');

      // قتل أي برنامج Canon مفتوح (احتياط)
      await Process.run('taskkill', ['/IM', 'TouchDR.exe', '/F']);
      await Process.run('taskkill', ['/IM', 'CaptureOnTouch.exe', '/F']);

      // انتظار بسيط
      await Future.delayed(const Duration(seconds: 2));

      // إعادة إنشاء instance جديد
      _scanner = FlutterTwainScanner();

    } catch (e) {
      debugPrint('⚠️ خطأ أثناء إعادة التهيئة: $e');
    }
  }

  /// 🔹 جلب الأجهزة
  Future<List<String>> getAvailableScanners() async {
    try {
      await _resetScanner();

      final sources = await _scanner!.getDataSources();
      debugPrint('Available scanners: $sources');
      return sources;
    } catch (e) {
      throw Exception('تعذر جلب أجهزة السكانر: $e');
    }
  }

  /// 🔥 السحب من السكانر (نسخة محسنة بدون تعليق)
  Future<List<String>> scanFromScanner(int sourceIndex) async {
    try {
      debugPrint('🚀 بدء السحب من السكانر...');
      debugPrint('sourceIndex = $sourceIndex');

      // 🧨 أهم خطوة: إعادة تهيئة قبل كل سحب
      await _resetScanner();

      final List<String> scannedFiles = await _scanner!
          .scanDocument(sourceIndex)
          .timeout(const Duration(seconds: 60));

      debugPrint('✅ انتهى السحب');
      debugPrint('scannedFiles = $scannedFiles');

      if (scannedFiles.isEmpty) {
        throw Exception('تم السحب ولكن لم يتم إرجاع أي ملفات.');
      }

      return scannedFiles;

    } on TimeoutException {
      debugPrint('⏱ Timeout: المكتبة علقت');
      throw Exception('انتهت مهلة السحب. حاول مرة أخرى.');

    } catch (e) {
      debugPrint('❌ Scanner error: $e');

      // 🔥 إعادة تهيئة بعد الخطأ حتى ما يعلق
      await _resetScanner();

      throw Exception('فشل السحب من جهاز السكانر: $e');
    }
  }

  /// 🔹 نقل الصور
  Future<List<String>> moveScannedFilesToDocumentFolder({
    required List<String> scannedFiles,
    required String targetFolderPath,
  }) async {
    final List<String> finalPaths = [];

    for (int i = 0; i < scannedFiles.length; i++) {
      final sourceFile = File(scannedFiles[i]);

      if (!await sourceFile.exists()) continue;

      final extension = _getExtension(scannedFiles[i]);
      final newName =
          'image_${(i + 1).toString().padLeft(3, '0')}.$extension';
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