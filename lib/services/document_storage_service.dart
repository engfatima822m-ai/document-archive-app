import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/attachment_model.dart';
import '../models/document_model.dart';
import 'api_service.dart';

class PreparedArchivePdf {
  final String absoluteFolderPath;
  final String relativeFolderPath;

  final String absolutePdfPath;
  final String relativePdfPath;

  final int fileSizeBytes;
  final String sha256Hash;
  final int pageCount;

  const PreparedArchivePdf({
    required this.absoluteFolderPath,
    required this.relativeFolderPath,
    required this.absolutePdfPath,
    required this.relativePdfPath,
    required this.fileSizeBytes,
    required this.sha256Hash,
    required this.pageCount,
  });
}

class ArchiveStorageException
    implements Exception {
  final String message;

  const ArchiveStorageException(
    this.message,
  );

  @override
  String toString() => message;
}

class DocumentStorageService {
  DocumentStorageService._();

  static const String baseArchivePath =
      r'D:\DocumentArchive';

  static const String scanTemporaryPath =
      r'C:\ScannedTemp';

  static const int maximumPages = 2000;

  static final Random _secureRandom =
      Random.secure();

  /*
  |--------------------------------------------------------------------------
  | إنشاء مجلد الأرشيف الرئيسي
  |--------------------------------------------------------------------------
  */

  static Future<void>
      ensureBaseFolderExists() async {
    final directory =
        Directory(baseArchivePath);

    if (!await directory.exists()) {
      await directory.create(
        recursive: true,
      );
    }
  }

  /*
  |--------------------------------------------------------------------------
  | إنشاء UUID بدون مكتبة إضافية
  |--------------------------------------------------------------------------
  */

  static String generateBatchId() {
    final bytes = List<int>.generate(
      16,
      (_) => _secureRandom.nextInt(256),
    );

    bytes[6] =
        (bytes[6] & 0x0F) | 0x40;

    bytes[8] =
        (bytes[8] & 0x3F) | 0x80;

    String hex(int value) =>
        value.toRadixString(16).padLeft(2, '0');

    final value =
        bytes.map(hex).join();

    return '${value.substring(0, 8)}-'
        '${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-'
        '${value.substring(16, 20)}-'
        '${value.substring(20, 32)}';
  }

  /*
  |--------------------------------------------------------------------------
  | تنظيف أسماء المجلدات والملفات
  |--------------------------------------------------------------------------
  */

  static String safePathPart(
    String value, {
    String fallback = 'document',
    int maximumLength = 80,
  }) {
    var clean = value.trim();

    clean = clean.replaceAll(
      RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
      '_',
    );

    clean = clean.replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    while (
        clean.endsWith('.') ||
        clean.endsWith(' ')) {
      clean = clean.substring(
        0,
        clean.length - 1,
      );
    }

    if (clean.isEmpty) {
      clean = fallback;
    }

    if (clean.length > maximumLength) {
      clean = clean.substring(
        0,
        maximumLength,
      );
    }

    final reserved = <String>{
      'CON',
      'PRN',
      'AUX',
      'NUL',
      'COM1',
      'COM2',
      'COM3',
      'COM4',
      'COM5',
      'COM6',
      'COM7',
      'COM8',
      'COM9',
      'LPT1',
      'LPT2',
      'LPT3',
      'LPT4',
      'LPT5',
      'LPT6',
      'LPT7',
      'LPT8',
      'LPT9',
    };

    final baseName = clean
        .split('.')
        .first
        .toUpperCase();

    if (reserved.contains(baseName)) {
      clean = '_$clean';
    }

    return clean;
  }

  static String _yearFromDate(
    String date,
  ) {
    final match = RegExp(
      r'^\d{4}',
    ).firstMatch(date.trim());

    return match?.group(0) ?? 'unknown';
  }

  static String buildMainRelativeFolder({
    required String documentNumber,
    required String documentDate,
  }) {
    final year =
        _yearFromDate(documentDate);

    final number = safePathPart(
      documentNumber,
      fallback: 'document',
      maximumLength: 60,
    );

    final uniqueId =
        generateBatchId();

    return 'documents/$year/'
        'document_${number}_$uniqueId';
  }

  static String
      buildAttachmentRelativeFolder({
    required int parentDocumentId,
    required String subDocumentNumber,
    required String subDocumentDate,
  }) {
    final year =
        _yearFromDate(subDocumentDate);

    final number = safePathPart(
      subDocumentNumber,
      fallback: 'attachment',
      maximumLength: 60,
    );

    final uniqueId =
        generateBatchId();

    return 'attachments/'
        '$parentDocumentId/'
        '$year/'
        'attachment_${number}_$uniqueId';
  }

  static String buildPdfFileName({
    required String number,
    required String title,
  }) {
    final safeNumber = safePathPart(
      number,
      fallback: 'document',
      maximumLength: 45,
    );

    final safeTitle = safePathPart(
      title,
      fallback: 'archive',
      maximumLength: 65,
    );

    return '${safeNumber}_$safeTitle.pdf';
  }

  /*
  |--------------------------------------------------------------------------
  | تحويل المسار النسبي إلى مسار Windows
  |--------------------------------------------------------------------------
  */

  static String absolutePathFromRelative(
    String relativePath,
  ) {
    final normalized = relativePath
        .trim()
        .replaceAll('\\', '/')
        .replaceAll(
          RegExp(r'^/+|/+$'),
          '',
        );

    if (normalized.isEmpty) {
      throw const ArchiveStorageException(
        'المسار النسبي فارغ.',
      );
    }

    final segments =
        normalized.split('/');

    if (segments.any(
      (segment) =>
          segment.isEmpty ||
          segment == '.' ||
          segment == '..',
    )) {
      throw const ArchiveStorageException(
        'المسار النسبي غير آمن.',
      );
    }

    return '$baseArchivePath\\'
        '${segments.join('\\')}';
  }

  /*
  |--------------------------------------------------------------------------
  | التحقق من صور السكانر
  |--------------------------------------------------------------------------
  */

  static bool _isSupportedImage(
    String filePath,
  ) {
    final lower =
        filePath.toLowerCase();

    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png');
  }

  static Future<List<File>>
      _validateSourceImages(
    List<String> sourceImagePaths,
  ) async {
    if (sourceImagePaths.isEmpty) {
      throw const ArchiveStorageException(
        'لا توجد صور لإنشاء ملف PDF.',
      );
    }

    if (
        sourceImagePaths.length >
        maximumPages) {
      throw const ArchiveStorageException(
        'عدد الصفحات يتجاوز الحد المسموح.',
      );
    }

    final files = <File>[];
    final usedPaths = <String>{};

    for (
      var index = 0;
      index < sourceImagePaths.length;
      index++
    ) {
      final sourcePath =
          sourceImagePaths[index].trim();

      if (sourcePath.isEmpty) {
        throw ArchiveStorageException(
          'مسار الصفحة رقم '
          '${index + 1} غير صحيح.',
        );
      }

      final file = File(sourcePath);

      if (!await file.exists()) {
        throw ArchiveStorageException(
          'الصفحة رقم '
          '${index + 1} غير موجودة.',
        );
      }

      if (!_isSupportedImage(sourcePath)) {
        throw ArchiveStorageException(
          'صيغة الصفحة رقم '
          '${index + 1} غير مدعومة.',
        );
      }

      final normalizedPath =
          file.absolute.path.toLowerCase();

      if (!usedPaths.add(normalizedPath)) {
        throw ArchiveStorageException(
          'الصفحة رقم '
          '${index + 1} مكررة.',
        );
      }

      final fileSize =
          await file.length();

      if (
          fileSize <= 0 ||
          fileSize > 52428800) {
        throw ArchiveStorageException(
          'حجم الصفحة رقم '
          '${index + 1} غير مسموح.',
        );
      }

      files.add(file);
    }

    return files;
  }

  /*
  |--------------------------------------------------------------------------
  | إنشاء PDF واحد من مجموعة صور
  |--------------------------------------------------------------------------
  */

  static Future<PreparedArchivePdf>
      createPdfFromImages({
    required List<String> sourceImagePaths,
    required String relativeFolderPath,
    required String pdfFileName,
  }) async {
    await ensureBaseFolderExists();

    final sourceFiles =
        await _validateSourceImages(
      sourceImagePaths,
    );

    final absoluteFolderPath =
        absolutePathFromRelative(
      relativeFolderPath,
    );

    final folderDirectory =
        Directory(absoluteFolderPath);

    if (await folderDirectory.exists()) {
      throw const ArchiveStorageException(
        'مجلد الأرشيف موجود مسبقًا.',
      );
    }

    await folderDirectory.create(
      recursive: true,
    );

    final safePdfName =
        safePathPart(
      pdfFileName
          .replaceFirst(
            RegExp(
              r'\.pdf$',
              caseSensitive: false,
            ),
            '',
          ),
      fallback: 'archive_document',
      maximumLength: 120,
    );

    final finalPdfName =
        '$safePdfName.pdf';

    final absolutePdfPath =
        '$absoluteFolderPath\\'
        '$finalPdfName';

    final temporaryPdfPath =
        '$absolutePdfPath.tmp';

    final relativePdfPath =
        '${relativeFolderPath.replaceAll('\\', '/')}/'
        '$finalPdfName';

    final pdf = pw.Document(
      compress: true,
    );

    try {
      for (
        var index = 0;
        index < sourceFiles.length;
        index++
      ) {
        final imageBytes =
            await sourceFiles[index]
                .readAsBytes();

        final image =
            pw.MemoryImage(imageBytes);

        pdf.addPage(
          pw.Page(
            pageFormat:
                PdfPageFormat.a4,
            margin:
                const pw.EdgeInsets.all(12),
            build: (_) {
              return pw.Center(
                child: pw.Image(
                  image,
                  fit: pw.BoxFit.contain,
                ),
              );
            },
          ),
        );
      }

      final pdfBytes =
          await pdf.save();

      if (pdfBytes.isEmpty) {
        throw const ArchiveStorageException(
          'تعذر إنشاء ملف PDF.',
        );
      }

      final temporaryFile =
          File(temporaryPdfPath);

      await temporaryFile.writeAsBytes(
        pdfBytes,
        flush: true,
      );

      final finalFile =
          await temporaryFile.rename(
        absolutePdfPath,
      );

      final fileSize =
          await finalFile.length();

      if (fileSize <= 0) {
        throw const ArchiveStorageException(
          'ملف PDF الناتج فارغ.',
        );
      }

      final digest = await sha256
          .bind(finalFile.openRead())
          .first;

      return PreparedArchivePdf(
        absoluteFolderPath:
            absoluteFolderPath,
        relativeFolderPath:
            relativeFolderPath
                .replaceAll('\\', '/'),
        absolutePdfPath:
            absolutePdfPath,
        relativePdfPath:
            relativePdfPath,
        fileSizeBytes: fileSize,
        sha256Hash:
            digest.toString(),
        pageCount:
            sourceFiles.length,
      );
    } catch (exception) {
      final temporaryFile =
          File(temporaryPdfPath);

      if (await temporaryFile.exists()) {
        try {
          await temporaryFile.delete();
        } catch (_) {}
      }

      final finalFile =
          File(absolutePdfPath);

      if (await finalFile.exists()) {
        try {
          await finalFile.delete();
        } catch (_) {}
      }

      if (await folderDirectory.exists()) {
        try {
          await folderDirectory.delete(
            recursive: true,
          );
        } catch (_) {}
      }

      if (
          exception
          is ArchiveStorageException) {
        rethrow;
      }

      throw ArchiveStorageException(
        'فشل تحويل الصور إلى PDF: '
        '$exception',
      );
    }
  }

  /*
  |--------------------------------------------------------------------------
  | حذف صور السكانر المؤقتة فقط بعد نجاح الحفظ
  |--------------------------------------------------------------------------
  */

  static Future<void>
      deleteSuccessfulScanImages(
    List<String> sourceImagePaths,
  ) async {
    final scanRoot = Directory(
      scanTemporaryPath,
    ).absolute.path.toLowerCase();

    final safePrefix = scanRoot.endsWith(
      Platform.pathSeparator,
    )
        ? scanRoot
        : '$scanRoot'
            '${Platform.pathSeparator}';

    for (final sourcePath
        in sourceImagePaths) {
      final file = File(sourcePath);

      if (!await file.exists()) {
        continue;
      }

      final absolutePath =
          file.absolute.path.toLowerCase();

      if (!absolutePath.startsWith(
        safePrefix,
      )) {
        // لا نحذف الصور التي اختارها
        // الموظف من مجلد شخصي.
        continue;
      }

      try {
        await file.delete();
      } catch (_) {
        // بقاء صورة مؤقتة أفضل من
        // حذف ملف غير مقصود.
      }
    }
  }

  /*
  |--------------------------------------------------------------------------
  | حفظ ملف رئيسي من الصور
  |--------------------------------------------------------------------------
  */

  static Future<DocumentModel>
      saveMainDocumentFromImages({
    required String documentNumber,
    required String documentDate,
    required String documentTitle,
    required String notes,
    required String status,
    String? reminderDate,
    String? reminderNote,
    required List<String> sourceImagePaths,
    String scanMode =
        'single_document',
    String? scanBatchId,
  }) async {
    final relativeFolder =
        buildMainRelativeFolder(
      documentNumber: documentNumber,
      documentDate: documentDate,
    );

    final pdfName =
        buildPdfFileName(
      number: documentNumber,
      title: documentTitle,
    );

    final preparedPdf =
        await createPdfFromImages(
      sourceImagePaths:
          sourceImagePaths,
      relativeFolderPath:
          relativeFolder,
      pdfFileName: pdfName,
    );

    final document = DocumentModel(
      documentNumber:
          documentNumber.trim(),
      documentDate:
          documentDate.trim(),
      documentTitle:
          documentTitle.trim(),
      notes: notes.trim(),
      status: status,
      reminderDate: reminderDate,
      reminderNote: reminderNote,
      hasPdf: true,
      relativeFolderPath:
          preparedPdf.relativeFolderPath,
      pdfRelativePath:
          preparedPdf.relativePdfPath,
      pdfSizeBytes:
          preparedPdf.fileSizeBytes,
      pdfSha256:
          preparedPdf.sha256Hash,
      pageCount:
          preparedPdf.pageCount,
      scanMode: scanMode,
      scanBatchId: scanBatchId,
    );

    final response =
        await ApiService.postJson(
      'insert_document.php',
      document.toCreateJson(),
    );

    final savedValue =
        response['document'];

    if (savedValue is! Map) {
      throw const ApiException(
        'لم يرجع الخادم بيانات الملف المحفوظ.',
      );
    }

    await deleteSuccessfulScanImages(
      sourceImagePaths,
    );

    return DocumentModel.fromJson(
      Map<String, dynamic>.from(
        savedValue,
      ),
    );
  }

  /*
  |--------------------------------------------------------------------------
  | حفظ كتاب تابع من الصور
  |--------------------------------------------------------------------------
  */

  static Future<AttachmentModel>
      saveAttachmentFromImages({
    required int parentDocumentId,
    String? parentDocumentNumber,
    String? parentDocumentTitle,
    required String subDocumentNumber,
    required String subDocumentDate,
    required String subDocumentTitle,
    required String notes,
    String? reminderDate,
    String? reminderNote,
    required List<String> sourceImagePaths,
  }) async {
    final relativeFolder =
        buildAttachmentRelativeFolder(
      parentDocumentId:
          parentDocumentId,
      subDocumentNumber:
          subDocumentNumber,
      subDocumentDate:
          subDocumentDate,
    );

    final pdfName =
        buildPdfFileName(
      number: subDocumentNumber,
      title: subDocumentTitle,
    );

    final preparedPdf =
        await createPdfFromImages(
      sourceImagePaths:
          sourceImagePaths,
      relativeFolderPath:
          relativeFolder,
      pdfFileName: pdfName,
    );

    final attachment =
        AttachmentModel(
      parentDocumentId:
          parentDocumentId,
      parentDocumentNumber:
          parentDocumentNumber,
      parentDocumentTitle:
          parentDocumentTitle,
      subDocumentNumber:
          subDocumentNumber.trim(),
      subDocumentDate:
          subDocumentDate.trim(),
      subDocumentTitle:
          subDocumentTitle.trim(),
      notes: notes.trim(),
      reminderDate: reminderDate,
      reminderNote: reminderNote,
      hasPdf: true,
      relativeFolderPath:
          preparedPdf.relativeFolderPath,
      pdfRelativePath:
          preparedPdf.relativePdfPath,
      pdfSizeBytes:
          preparedPdf.fileSizeBytes,
      pdfSha256:
          preparedPdf.sha256Hash,
      pageCount:
          preparedPdf.pageCount,
    );

    final response =
        await ApiService.postJson(
      'insert_attachment.php',
      attachment.toCreateJson(),
    );

    final savedValue =
        response['attachment'];

    if (savedValue is! Map) {
      throw const ApiException(
        'لم يرجع الخادم بيانات الكتاب التابع.',
      );
    }

    await deleteSuccessfulScanImages(
      sourceImagePaths,
    );

    return AttachmentModel.fromJson(
      Map<String, dynamic>.from(
        savedValue,
      ),
    );
  }
}