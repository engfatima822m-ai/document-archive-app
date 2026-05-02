import 'dart:io';

import '../models/attachment_model.dart';
import '../models/document_model.dart';

class DocumentStorageService {
  // المسار الرئيسي للأرشيف على حاسبة الموظف
  static const String baseArchivePath = r'D:\DocumentArchive';

  static final List<DocumentModel> _documents = [];
  static final List<AttachmentModel> _attachments = [];

  // =========================
  // الأساسيات
  // =========================

  static Future<void> ensureBaseFolderExists() async {
    final baseDir = Directory(baseArchivePath);

    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
  }

  static String getDocumentFolderPath(String documentNumber) {
    return '$baseArchivePath\\${documentNumber.trim()}';
  }

  static String getOriginalFolderPath(String documentNumber) {
    return '${getDocumentFolderPath(documentNumber)}\\original';
  }

  static String getAttachmentFolderPath({
    required String parentDocumentNumber,
    required String subDocumentNumber,
  }) {
    return '${getDocumentFolderPath(parentDocumentNumber)}\\${subDocumentNumber.trim()}';
  }

  static Future<bool> documentFolderExists(String documentNumber) async {
    final dir = Directory(getDocumentFolderPath(documentNumber));
    return await dir.exists();
  }

  static Future<bool> originalFolderExists(String documentNumber) async {
    final dir = Directory(getOriginalFolderPath(documentNumber));
    return await dir.exists();
  }

  static Future<bool> attachmentFolderExists({
    required String parentDocumentNumber,
    required String subDocumentNumber,
  }) async {
    final dir = Directory(
      getAttachmentFolderPath(
        parentDocumentNumber: parentDocumentNumber,
        subDocumentNumber: subDocumentNumber,
      ),
    );

    return await dir.exists();
  }

  // =========================
  // إنشاء الفولدرات
  // =========================

  static Future<String> createDocumentFolder(String documentNumber) async {
    await ensureBaseFolderExists();

    final folderPath = getDocumentFolderPath(documentNumber);
    final dir = Directory(folderPath);

    if (await dir.exists()) {
      throw Exception('الملف موجود مسبقاً');
    }

    await dir.create(recursive: true);
    return folderPath;
  }

  static Future<String> createOriginalFolder(String documentNumber) async {
    await ensureBaseFolderExists();

    final mainFolder = Directory(getDocumentFolderPath(documentNumber));

    if (!await mainFolder.exists()) {
      await mainFolder.create(recursive: true);
    }

    final originalPath = getOriginalFolderPath(documentNumber);
    final originalDir = Directory(originalPath);

    if (!await originalDir.exists()) {
      await originalDir.create(recursive: true);
    }

    return originalPath;
  }

  static Future<String> createAttachmentFolder({
    required String parentDocumentNumber,
    required String subDocumentNumber,
  }) async {
    final parentExists = await documentFolderExists(parentDocumentNumber);

    if (!parentExists) {
      throw Exception('الملف الأصلي غير موجود');
    }

    final attachmentPath = getAttachmentFolderPath(
      parentDocumentNumber: parentDocumentNumber,
      subDocumentNumber: subDocumentNumber,
    );

    final attachmentDir = Directory(attachmentPath);

    if (await attachmentDir.exists()) {
      throw Exception('الكتاب التابع موجود مسبقاً داخل هذا الملف');
    }

    await attachmentDir.create(recursive: true);
    return attachmentPath;
  }

  // =========================
  // ترقيم الصور
  // =========================

  static bool _isImageFile(String path) {
    final lower = path.toLowerCase();

    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.webp');
  }

  static int _extractImageNumber(String filePath) {
    final fileName = filePath.split(Platform.pathSeparator).last;
    final dotIndex = fileName.lastIndexOf('.');

    final nameWithoutExtension =
        dotIndex == -1 ? fileName : fileName.substring(0, dotIndex);

    return int.tryParse(nameWithoutExtension) ?? 0;
  }

  static Future<int> getNextImageIndex(String folderPath) async {
    final dir = Directory(folderPath);

    if (!await dir.exists()) {
      return 1;
    }

    final entities = await dir.list().toList();

    final imageNumbers = entities
        .whereType<File>()
        .map((file) => file.path)
        .where(_isImageFile)
        .map(_extractImageNumber)
        .where((number) => number > 0)
        .toList();

    if (imageNumbers.isEmpty) {
      return 1;
    }

    imageNumbers.sort();
    return imageNumbers.last + 1;
  }

  static Future<List<String>> copyImagesToFolderSequentially({
    required List<String> sourceImagePaths,
    required String targetFolderPath,
  }) async {
    final targetDir = Directory(targetFolderPath);

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    int nextIndex = await getNextImageIndex(targetFolderPath);
    final List<String> savedPaths = [];

    for (final sourcePath in sourceImagePaths) {
      final sourceFile = File(sourcePath);

      if (!await sourceFile.exists()) {
        continue;
      }

      if (!_isImageFile(sourcePath)) {
        continue;
      }

      final extension = sourcePath.split('.').last.toLowerCase();
      final newPath = '$targetFolderPath\\$nextIndex.$extension';

      final copiedFile = await sourceFile.copy(newPath);
      savedPaths.add(copiedFile.path);

      nextIndex++;
    }

    return savedPaths;
  }

  static Future<List<String>> moveImagesToFolderSequentially({
    required List<String> sourceImagePaths,
    required String targetFolderPath,
  }) async {
    final targetDir = Directory(targetFolderPath);

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    int nextIndex = await getNextImageIndex(targetFolderPath);
    final List<String> savedPaths = [];

    for (final sourcePath in sourceImagePaths) {
      final sourceFile = File(sourcePath);

      if (!await sourceFile.exists()) {
        continue;
      }

      if (!_isImageFile(sourcePath)) {
        continue;
      }

      final extension = sourcePath.split('.').last.toLowerCase();
      final newPath = '$targetFolderPath\\$nextIndex.$extension';

      try {
        final movedFile = await sourceFile.rename(newPath);
        savedPaths.add(movedFile.path);
      } catch (_) {
        // إذا فشل rename بسبب اختلاف القرص أو قفل الملف، نستخدم copy ثم delete
        final copiedFile = await sourceFile.copy(newPath);
        savedPaths.add(copiedFile.path);

        try {
          await sourceFile.delete();
        } catch (_) {}
      }

      nextIndex++;
    }

    return savedPaths;
  }

  // =========================
  // الملفات الرئيسية
  // =========================

  static Future<DocumentModel> createDocumentRecord({
    required String documentNumber,
    required String documentDate,
    required String documentTitle,
    required String notes,
    required String status,
    String? reminderDate,
    String? reminderNote,
    required String folderPath,
    required List<String> imagePaths,
  }) async {
    final document = DocumentModel(
      documentNumber: documentNumber.trim(),
      documentDate: documentDate,
      documentTitle: documentTitle,
      notes: notes,
      status: status,
      reminderDate: reminderDate,
      reminderNote: reminderNote,
      folderPath: folderPath,
      imagePaths: imagePaths,
    );

    _documents.add(document);
    return document;
  }

  static Future<DocumentModel> createAndSaveMainDocument({
    required String documentNumber,
    required String documentDate,
    required String documentTitle,
    required String notes,
    required String status,
    String? reminderDate,
    String? reminderNote,
    required List<String> sourceImagePaths,
    bool moveFiles = false,
  }) async {
    final exists = await documentFolderExists(documentNumber);

    if (exists) {
      throw Exception('الملف موجود مسبقاً');
    }

    final originalFolderPath = await createOriginalFolder(documentNumber);

    final savedImagePaths = moveFiles
        ? await moveImagesToFolderSequentially(
            sourceImagePaths: sourceImagePaths,
            targetFolderPath: originalFolderPath,
          )
        : await copyImagesToFolderSequentially(
            sourceImagePaths: sourceImagePaths,
            targetFolderPath: originalFolderPath,
          );

    final document = DocumentModel(
      documentNumber: documentNumber.trim(),
      documentDate: documentDate,
      documentTitle: documentTitle,
      notes: notes,
      status: status,
      reminderDate: reminderDate,
      reminderNote: reminderNote,
      folderPath: originalFolderPath,
      imagePaths: savedImagePaths,
    );

    _documents.add(document);
    return document;
  }

  static List<DocumentModel> getAllDocuments() {
    return List.unmodifiable(_documents);
  }

  static DocumentModel? getDocumentByNumber(String documentNumber) {
    try {
      return _documents.firstWhere(
        (doc) => doc.documentNumber.trim() == documentNumber.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  static List<DocumentModel> searchDocuments(String query) {
    final q = query.trim().toLowerCase();

    if (q.isEmpty) return [];

    return _documents.where((doc) {
      return doc.documentNumber.toLowerCase().contains(q) ||
          doc.documentTitle.toLowerCase().contains(q) ||
          doc.notes.toLowerCase().contains(q);
    }).toList();
  }

  // =========================
  // الكتب التابعة
  // =========================

  static Future<AttachmentModel> createAttachmentRecord({
    required String parentDocumentNumber,
    required String subDocumentNumber,
    required String subDocumentDate,
    required String subDocumentTitle,
    required String notes,
    required String folderPath,
    required List<String> imagePaths,
  }) async {
    final attachment = AttachmentModel(
      parentDocumentNumber: parentDocumentNumber.trim(),
      subDocumentNumber: subDocumentNumber.trim(),
      subDocumentDate: subDocumentDate,
      subDocumentTitle: subDocumentTitle,
      notes: notes,
      folderPath: folderPath,
      imagePaths: imagePaths,
    );

    _attachments.add(attachment);
    return attachment;
  }

  static Future<AttachmentModel> appendSubDocumentToExistingDocument({
    required String parentDocumentNumber,
    required String subDocumentNumber,
    required String subDocumentDate,
    required String subDocumentTitle,
    required String notes,
    required List<String> sourceImagePaths,
    bool moveFiles = false,
  }) async {
    final parentExists = await documentFolderExists(parentDocumentNumber);

    if (!parentExists) {
      throw Exception('الملف الأصلي غير موجود');
    }

    final subFolderExists = await attachmentFolderExists(
      parentDocumentNumber: parentDocumentNumber,
      subDocumentNumber: subDocumentNumber,
    );

    if (subFolderExists) {
      throw Exception('يوجد كتاب تابع بنفس الرقم داخل هذا الملف');
    }

    final attachmentFolderPath = await createAttachmentFolder(
      parentDocumentNumber: parentDocumentNumber,
      subDocumentNumber: subDocumentNumber,
    );

    final savedImagePaths = moveFiles
        ? await moveImagesToFolderSequentially(
            sourceImagePaths: sourceImagePaths,
            targetFolderPath: attachmentFolderPath,
          )
        : await copyImagesToFolderSequentially(
            sourceImagePaths: sourceImagePaths,
            targetFolderPath: attachmentFolderPath,
          );

    final attachment = AttachmentModel(
      parentDocumentNumber: parentDocumentNumber.trim(),
      subDocumentNumber: subDocumentNumber.trim(),
      subDocumentDate: subDocumentDate,
      subDocumentTitle: subDocumentTitle,
      notes: notes,
      folderPath: attachmentFolderPath,
      imagePaths: savedImagePaths,
    );

    _attachments.add(attachment);
    return attachment;
  }

  static List<AttachmentModel> getAllAttachments() {
    return List.unmodifiable(_attachments);
  }

  static List<AttachmentModel> getAttachmentsForDocument(
    String parentDocumentNumber,
  ) {
    return _attachments
        .where(
          (att) =>
              att.parentDocumentNumber.trim() == parentDocumentNumber.trim(),
        )
        .toList();
  }

  static AttachmentModel? getAttachmentByNumbers({
    required String parentDocumentNumber,
    required String subDocumentNumber,
  }) {
    try {
      return _attachments.firstWhere(
        (att) =>
            att.parentDocumentNumber.trim() == parentDocumentNumber.trim() &&
            att.subDocumentNumber.trim() == subDocumentNumber.trim(),
      );
    } catch (_) {
      return null;
    }
  }
}