import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_twain_scanner/flutter_twain_scanner.dart';

class ScannerService {
  FlutterTwainScanner? _scanner;

  bool _isScanning = false;

  /// هل توجد عملية سحب تعمل حاليًا؟
  bool get isScanning => _isScanning;

  /// إعادة إنشاء الاتصال بمكتبة TWAIN.
  Future<void> _resetScanner() async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'السحب من جهاز الأرشفة متاح على Windows فقط.',
      );
    }

    try {
      debugPrint('إعادة تهيئة جهاز الأرشفة...');

      await _closeCanonApplications();

      await Future<void>.delayed(
        const Duration(milliseconds: 1200),
      );

      _scanner = FlutterTwainScanner();

      debugPrint('تمت تهيئة جهاز الأرشفة.');
    } catch (error, stackTrace) {
      debugPrint(
        'تعذر إعادة تهيئة جهاز الأرشفة: $error',
      );
      debugPrintStack(stackTrace: stackTrace);

      throw Exception(
        'تعذر تهيئة جهاز الأرشفة.',
      );
    }
  }

  /// إغلاق برامج Canon التي قد تحجز جهاز السكانر
  /// وتمنع التطبيق من استخدام TWAIN.
  Future<void> _closeCanonApplications() async {
    if (!Platform.isWindows) {
      return;
    }

    const processNames = <String>[
      'TouchDR.exe',
      'CaptureOnTouch.exe',
    ];

    for (final processName in processNames) {
      try {
        final result = await Process.run(
          'taskkill',
          <String>[
            '/IM',
            processName,
            '/F',
          ],
          runInShell: false,
        ).timeout(
          const Duration(seconds: 5),
        );

        if (result.exitCode == 0) {
          debugPrint(
            'تم إغلاق البرنامج المتعارض: $processName',
          );
        }
      } on TimeoutException {
        debugPrint(
          'انتهت مهلة إغلاق البرنامج: $processName',
        );
      } catch (error) {
        /*
         * عدم وجود البرنامج أو عدم عمله ليس خطأً يمنع
         * عملية السحب، لذلك نسجل الحالة فقط.
         */
        debugPrint(
          'لم يتم إغلاق $processName: $error',
        );
      }
    }
  }

  /// جلب قائمة أجهزة TWAIN المتاحة.
  Future<List<String>> getAvailableScanners() async {
    if (_isScanning) {
      throw StateError(
        'توجد عملية سحب تعمل حاليًا.',
      );
    }

    try {
      await _resetScanner();

      final scanner = _scanner;

      if (scanner == null) {
        throw StateError(
          'لم تتم تهيئة جهاز الأرشفة.',
        );
      }

      final List<String> sources =
          await scanner.getDataSources().timeout(
        const Duration(seconds: 20),
      );

      final cleanedSources = sources
          .map((source) => source.trim())
          .where((source) => source.isNotEmpty)
          .toSet()
          .toList(growable: false);

      debugPrint(
        'أجهزة الأرشفة المتاحة: $cleanedSources',
      );

      if (cleanedSources.isEmpty) {
        throw Exception(
          'لم يتم العثور على جهاز أرشفة. '
          'تأكدي من تشغيل الجهاز وتثبيت تعريف TWAIN.',
        );
      }

      return cleanedSources;
    } on TimeoutException {
      throw Exception(
        'تأخر جهاز الأرشفة في الاستجابة.',
      );
    } catch (error) {
      debugPrint(
        'تعذر جلب أجهزة الأرشفة: $error',
      );

      if (error is Exception) {
        rethrow;
      }

      throw Exception(
        'تعذر جلب أجهزة الأرشفة.',
      );
    }
  }

  /// سحب ورقة واحدة أو عدة أوراق من المغذي.
  ///
  /// الملفات الناتجة تكون صورًا مؤقتة فقط.
  /// سيقوم DocumentStorageService بتحويلها إلى PDF،
  /// ثم حذف الصور بعد نجاح إنشاء PDF والتحقق منه.
  Future<List<String>> scanFromScanner(
    int sourceIndex,
  ) async {
    if (sourceIndex < 0) {
      throw ArgumentError.value(
        sourceIndex,
        'sourceIndex',
        'رقم جهاز الأرشفة غير صحيح.',
      );
    }

    if (_isScanning) {
      throw StateError(
        'توجد عملية سحب تعمل حاليًا. '
        'انتظري حتى تنتهي قبل بدء عملية جديدة.',
      );
    }

    _isScanning = true;

    try {
      debugPrint(
        'بدء السحب من جهاز الأرشفة رقم $sourceIndex...',
      );

      await _resetScanner();

      final scanner = _scanner;

      if (scanner == null) {
        throw StateError(
          'لم تتم تهيئة جهاز الأرشفة.',
        );
      }

      /*
       * المدة خمس دقائق حتى تسمح بسحب عدد كبير من
       * الأوراق من المغذي دون إنهاء العملية مبكرًا.
       */
      final List<String> scannedFiles =
          await scanner.scanDocument(sourceIndex).timeout(
        const Duration(minutes: 5),
      );

      if (scannedFiles.isEmpty) {
        throw Exception(
          'انتهت عملية السحب دون استلام أي صورة.',
        );
      }

      final verifiedFiles = await _verifyScannedFiles(
        scannedFiles,
      );

      if (verifiedFiles.isEmpty) {
        throw Exception(
          'لم يتم العثور على صور صالحة بعد السحب.',
        );
      }

      debugPrint(
        'اكتمل السحب بنجاح. عدد الصفحات: '
        '${verifiedFiles.length}',
      );

      return verifiedFiles;
    } on TimeoutException {
      debugPrint(
        'انتهت مهلة السحب من جهاز الأرشفة.',
      );

      throw Exception(
        'استغرقت عملية السحب وقتًا طويلًا. '
        'تأكدي من الجهاز ثم حاولي مجددًا.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'حدث خطأ أثناء السحب: $error',
      );
      debugPrintStack(stackTrace: stackTrace);

      try {
        _scanner = FlutterTwainScanner();
      } catch (_) {
        _scanner = null;
      }

      if (error is Exception) {
        rethrow;
      }

      throw Exception(
        'فشل السحب من جهاز الأرشفة.',
      );
    } finally {
      _isScanning = false;
    }
  }

  /// التحقق من أن الملفات التي أعادها جهاز الأرشفة:
  /// موجودة، غير فارغة، وبامتدادات صور مدعومة.
  Future<List<String>> _verifyScannedFiles(
    List<String> scannedFiles,
  ) async {
    const allowedExtensions = <String>{
      'jpg',
      'jpeg',
      'png',
      'bmp',
      'tif',
      'tiff',
    };

    const maximumImageSizeBytes =
        100 * 1024 * 1024;

    final verifiedFiles = <String>[];
    final usedPaths = <String>{};

    for (final rawPath in scannedFiles) {
      final path = rawPath.trim();

      if (path.isEmpty) {
        continue;
      }

      final normalizedPath = path.toLowerCase();

      if (!usedPaths.add(normalizedPath)) {
        continue;
      }

      final file = File(path);

      if (!await file.exists()) {
        debugPrint(
          'تم تجاهل صورة غير موجودة: $path',
        );
        continue;
      }

      final fileSize = await file.length();

      if (fileSize <= 0 ||
          fileSize > maximumImageSizeBytes) {
        debugPrint(
          'تم تجاهل صورة ذات حجم غير صالح: $path',
        );
        continue;
      }

      final extension = _getExtension(path);

      if (!allowedExtensions.contains(extension)) {
        debugPrint(
          'تم تجاهل امتداد غير مدعوم: $path',
        );
        continue;
      }

      verifiedFiles.add(file.absolute.path);
    }

    return List<String>.unmodifiable(
      verifiedFiles,
    );
  }

  /// إبقاء هذه الدالة للتوافق مع الصفحات القديمة.
  ///
  /// تنسخ الصور إلى مجلد مؤقت فقط، ولا تعتبر حفظًا
  /// نهائيًا. الحفظ النهائي سيكون بصيغة PDF.
  Future<List<String>>
      moveScannedFilesToDocumentFolder({
    required List<String> scannedFiles,
    required String targetFolderPath,
  }) async {
    final targetDirectory = Directory(
      targetFolderPath,
    );

    if (!await targetDirectory.exists()) {
      await targetDirectory.create(
        recursive: true,
      );
    }

    final targetRealPath =
        targetDirectory.absolute.path;

    final finalPaths = <String>[];

    try {
      for (var index = 0;
          index < scannedFiles.length;
          index++) {
        final sourceFile = File(
          scannedFiles[index],
        );

        if (!await sourceFile.exists()) {
          continue;
        }

        final extension = _getExtension(
          sourceFile.path,
        );

        final newName =
            'scan_${(index + 1).toString().padLeft(4, '0')}'
            '.$extension';

        final newPath = _joinWindowsPath(
          targetRealPath,
          newName,
        );

        final copiedFile = await sourceFile.copy(
          newPath,
        );

        finalPaths.add(
          copiedFile.absolute.path,
        );
      }

      if (finalPaths.isEmpty) {
        throw Exception(
          'تعذر تجهيز الصور المسحوبة.',
        );
      }

      return List<String>.unmodifiable(
        finalPaths,
      );
    } catch (_) {
      /*
       * إذا فشلت عملية النسخ في المنتصف، نحذف النسخ
       * الجديدة فقط ولا نحذف الصور الأصلية.
       */
      for (final copiedPath in finalPaths) {
        try {
          final copiedFile = File(copiedPath);

          if (await copiedFile.exists()) {
            await copiedFile.delete();
          }
        } catch (_) {
          // نتابع تنظيف بقية الملفات.
        }
      }

      rethrow;
    }
  }

  String _joinWindowsPath(
    String folderPath,
    String fileName,
  ) {
    final cleanFolderPath = folderPath.replaceAll(
      RegExp(r'[\\/]+$'),
      '',
    );

    return '$cleanFolderPath\\$fileName';
  }

  String _getExtension(String path) {
    final normalizedPath = path
        .split('?')
        .first
        .split('#')
        .first;

    final lastSeparator = normalizedPath.lastIndexOf(
      RegExp(r'[\\/]'),
    );

    final lastDot = normalizedPath.lastIndexOf('.');

    if (lastDot <= lastSeparator ||
        lastDot == normalizedPath.length - 1) {
      return 'jpg';
    }

    return normalizedPath
        .substring(lastDot + 1)
        .toLowerCase();
  }
}