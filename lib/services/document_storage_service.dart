import 'dart:io';
import '../models/document_model.dart';

class DocumentStorageService {
  static const String baseArchivePath = r'F:\DocumentArchive';

  static final List<DocumentModel> _documents = [];

  static Future<void> ensureBaseFolderExists() async {
    final baseDir = Directory(baseArchivePath);
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
  }

  static String getDocumentFolderPath(String documentNumber) {
    return '$baseArchivePath\\$documentNumber';
  }

  static Future<bool> documentFolderExists(String documentNumber) async {
    final folderPath = getDocumentFolderPath(documentNumber);
    final dir = Directory(folderPath);
    return await dir.exists();
  }

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

  static Future<DocumentModel> createDocumentRecord({
    required String documentNumber,
    required String documentDate,
    required String documentTitle,
    required String notes,
    required String folderPath,
    required List<String> imagePaths,
  }) async {
    final document = DocumentModel(
      documentNumber: documentNumber,
      documentDate: documentDate,
      documentTitle: documentTitle,
      notes: notes,
      folderPath: folderPath,
      imagePaths: imagePaths,
    );

    _documents.add(document);
    return document;
  }

  static Future<DocumentModel> createAndSaveDocument({
    required String documentNumber,
    required String documentDate,
    required String documentTitle,
    required String notes,
  }) async {
    final exists = await documentFolderExists(documentNumber);

    if (exists) {
      throw Exception('الملف موجود مسبقاً');
    }

    final folderPath = await createDocumentFolder(documentNumber);

    final document = DocumentModel(
      documentNumber: documentNumber,
      documentDate: documentDate,
      documentTitle: documentTitle,
      notes: notes,
      folderPath: folderPath,
      imagePaths: [],
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
}