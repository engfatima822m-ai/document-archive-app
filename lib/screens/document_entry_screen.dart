import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/document_model.dart';
import '../services/scanner_service.dart';

class DocumentEntryScreen extends StatefulWidget {
  const DocumentEntryScreen({super.key});

  @override
  State<DocumentEntryScreen> createState() => _DocumentEntryScreenState();
}

class _DocumentEntryScreenState extends State<DocumentEntryScreen> {
  final TextEditingController _documentNumberController =
      TextEditingController();
  final TextEditingController _documentDateController = TextEditingController();
  final TextEditingController _documentTitleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  final ScannerService _scannerService = ScannerService();

  static const String _archiveRootPath = r'F:\DocumentArchive';
  static const String _tempFolderPath = r'C:\ScannedTemp';
  static const String _scannerExePath =
      r'C:\Program Files (x86)\Canon Electronics\CaptureOnTouch\TouchDR.exe';

  List<String> _scannerNames = [];
  int? _selectedScannerIndex;
  List<String> _scannedImagePaths = [];
  int _currentPreviewIndex = 0;

  bool _isLoading = false;
  bool _isScanning = false;
  bool _isLoadingScanners = false;
  bool _isSearching = false;
  bool _isImportingTempImages = false;
  bool _isPrinting = false;

  DocumentModel? _savedDocument;
  DocumentModel? _searchedDocument;
  List<DocumentModel> _searchResults = [];

  final Color bgColor = const Color(0xFFF5F1E8);
  final Color shellColor = const Color(0xFFD7D2C8);
  final Color cardColor = const Color(0xFFF7F3EB);
  final Color accentColor = const Color(0xFFD4B04C);
  final Color darkColor = const Color(0xFF2B2B2B);
  final Color softTextColor = const Color(0xFF6E6A64);
  final Color borderColor = const Color(0xFFE2DCCE);

  String get _apiBaseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2/document_api';
    }
    return 'http://localhost/document_api';
  }

  bool get _hasMultiplePreviewImages => _scannedImagePaths.length > 1;

  @override
  void initState() {
    super.initState();
    _loadScanners();
    _ensureArchiveRootExists();
    _ensureTempFolderExists();
  }

  Future<void> _ensureArchiveRootExists() async {
    try {
      final rootDir = Directory(_archiveRootPath);
      if (!await rootDir.exists()) {
        await rootDir.create(recursive: true);
      }
    } catch (e) {
      _showMessage('تعذر إنشاء مجلد الأرشفة الرئيسي: $e', isError: true);
    }
  }

  Future<void> _ensureTempFolderExists() async {
    try {
      final tempDir = Directory(_tempFolderPath);
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
    } catch (e) {
      _showMessage('تعذر إنشاء مجلد السحب المؤقت: $e', isError: true);
    }
  }

  bool _isImageFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.tif') ||
        lower.endsWith('.tiff');
  }

  Future<List<String>> _getScannedFilesFromTempFolder() async {
    final directory = Directory(_tempFolderPath);

    if (!await directory.exists()) {
      return [];
    }

    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => _isImageFile(file.path))
        .map((file) => file.path)
        .toList();

    files.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return files;
  }

  Future<void> _clearTempFolder() async {
    final dir = Directory(_tempFolderPath);

    if (!await dir.exists()) return;

    final files = dir.listSync();
    for (final entity in files) {
      if (entity is File) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  void _setPreviewImages(List<String> images) {
    setState(() {
      _scannedImagePaths = images;
      _currentPreviewIndex = 0;
    });
  }

  void _goToNextPreviewImage() {
    if (_scannedImagePaths.isEmpty || !_hasMultiplePreviewImages) return;

    setState(() {
      _currentPreviewIndex =
          (_currentPreviewIndex + 1) % _scannedImagePaths.length;
    });
  }

  void _goToPreviousPreviewImage() {
    if (_scannedImagePaths.isEmpty || !_hasMultiplePreviewImages) return;

    setState(() {
      _currentPreviewIndex =
          (_currentPreviewIndex - 1 + _scannedImagePaths.length) %
              _scannedImagePaths.length;
    });
  }

  Future<void> _loadScanners() async {
    setState(() {
      _isLoadingScanners = true;
    });

    try {
      final scanners = await _scannerService.getAvailableScanners();
      setState(() {
        _scannerNames = scanners;
        _selectedScannerIndex = scanners.isNotEmpty ? 0 : null;
      });
    } catch (e) {
      _showMessage('تعذر تحميل أجهزة السكانر: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingScanners = false;
        });
      }
    }
  }

  Future<void> _loadScannedImagesFromFolder({bool showMessage = true}) async {
    setState(() {
      _isImportingTempImages = true;
    });

    try {
      final files = await _getScannedFilesFromTempFolder();

      if (files.isEmpty) {
        if (showMessage) {
          _showMessage(
            'لا توجد صور داخل C:\\ScannedTemp',
            isError: true,
          );
        }
        return;
      }

      _setPreviewImages(files);

      if (showMessage) {
        _showMessage('تم تحميل ${files.length} صورة من مجلد السحب');
      }
    } catch (e) {
      _showMessage('حدث خطأ أثناء تحميل الصور: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isImportingTempImages = false;
        });
      }
    }
  }

  Future<void> _startScanAndImport() async {
    setState(() {
      _isScanning = true;
      _scannedImagePaths = [];
      _currentPreviewIndex = 0;
    });

    try {
      await _ensureTempFolderExists();
      await _clearTempFolder();

      final scannerExe = File(_scannerExePath);
      if (!await scannerExe.exists()) {
        _showMessage(
          'تعذر العثور على برنامج السكانر في المسار المحدد',
          isError: true,
        );
        return;
      }

      await Process.start(
        _scannerExePath,
        [],
        mode: ProcessStartMode.detached,
      );

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('تنفيذ السحب'),
          content: const Text(
            'تم فتح برنامج Canon.\n'
            'اسحبي الأوراق من برنامج السكانر، وبعد اكتمال السحب اضغطي "تم السحب".',
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('تم السحب'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      bool loaded = false;

      for (int i = 0; i < 10; i++) {
        final files = await _getScannedFilesFromTempFolder();

        if (files.isNotEmpty) {
          _setPreviewImages(files);
          loaded = true;
          break;
        }

        await Future.delayed(const Duration(seconds: 1));
      }

      if (!loaded) {
        _showMessage(
          'لم يتم العثور على صور جديدة بعد السحب',
          isError: true,
        );
        return;
      }

      _showMessage('تم تحميل ${_scannedImagePaths.length} صورة بنجاح');
    } catch (e) {
      _showMessage('حدث خطأ أثناء تشغيل السكانر: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
      builder: (context, child) {
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.light(
              primary: accentColor,
              onPrimary: Colors.white,
              surface: cardColor,
              onSurface: darkColor,
            ),
            dialogTheme: DialogThemeData(backgroundColor: cardColor),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      _documentDateController.text =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
      setState(() {});
    }
  }

  DocumentModel _documentFromJson(Map<String, dynamic> map) {
    final rawImagePaths = map['image_paths'];

    List<String> imagePaths = [];
    if (rawImagePaths is List) {
      imagePaths = rawImagePaths.map((e) => e.toString()).toList();
    }

    return DocumentModel(
      id: map['id'] is int ? map['id'] : int.tryParse('${map['id']}'),
      documentNumber: (map['document_number'] ?? '').toString(),
      documentDate: (map['document_date'] ?? '').toString(),
      documentTitle: (map['document_title'] ?? '').toString(),
      notes: (map['notes'] ?? '').toString(),
      folderPath: (map['folder_path'] ?? '').toString(),
      imagePaths: imagePaths,
    );
  }

  Future<List<DocumentModel>> _fetchAllDocumentsFromApi() async {
    final uri = Uri.parse('$_apiBaseUrl/get_documents.php');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('فشل الاتصال بالخادم أثناء جلب الملفات');
    }

    final data = jsonDecode(response.body);

    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'فشل جلب الملفات');
    }

    final List docs = data['data'] ?? [];
    return docs
        .map((item) => _documentFromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<DocumentModel?> _fetchDocumentByNumberFromApi(
    String documentNumber,
  ) async {
    final uri = Uri.parse(
      '$_apiBaseUrl/get_document_by_number.php?number=$documentNumber',
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('فشل الاتصال بالخادم أثناء البحث');
    }

    final data = jsonDecode(response.body);

    if (data['success'] == true && data['data'] != null) {
      return _documentFromJson(Map<String, dynamic>.from(data['data']));
    }

    return null;
  }

  Future<void> _insertDocumentToApi(DocumentModel document) async {
    final uri = Uri.parse('$_apiBaseUrl/insert_document.php');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({
        'document_number': document.documentNumber,
        'document_date': document.documentDate,
        'document_title': document.documentTitle,
        'notes': document.notes,
        'folder_path': document.folderPath,
        'image_paths': document.imagePaths,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('فشل الاتصال بالخادم أثناء الحفظ');
    }

    final data = jsonDecode(response.body);

    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'فشل حفظ الملف');
    }
  }

  Future<List<DocumentModel>> _searchDocumentsInApi(String query) async {
    final allDocuments = await _fetchAllDocumentsFromApi();
    final lowerQuery = query.toLowerCase();

    final results = allDocuments.where((doc) {
      return doc.documentNumber.toLowerCase().contains(lowerQuery) ||
          doc.documentTitle.toLowerCase().contains(lowerQuery) ||
          doc.notes.toLowerCase().contains(lowerQuery);
    }).toList();

    results.sort((a, b) => b.documentDate.compareTo(a.documentDate));
    return results;
  }

  Future<void> _searchDocument() async {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      _showMessage('يرجى إدخال رقم الملف أو كلمة للبحث', isError: true);
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final exactDocument = await _fetchDocumentByNumberFromApi(query);
      final results = await _searchDocumentsInApi(query);

      setState(() {
        _searchedDocument =
            exactDocument ?? (results.isNotEmpty ? results.first : null);
        _searchResults = results;
      });

      if (_searchedDocument == null) {
        _showMessage('لم يتم العثور على نتيجة', isError: true);
      } else {
        _fillFormFromDocument(_searchedDocument!);
        _showMessage('تم العثور على ${results.length} نتيجة');
      }
    } catch (e) {
      _showMessage('حدث خطأ أثناء البحث: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchedDocument = null;
      _searchResults = [];
      _scannedImagePaths = [];
      _currentPreviewIndex = 0;
    });
  }

  void _fillFormFromDocument(DocumentModel document) {
    final existingImages =
        document.imagePaths.where((path) => File(path).existsSync()).toList();

    setState(() {
      _documentNumberController.text = document.documentNumber;
      _documentDateController.text = document.documentDate;
      _documentTitleController.text = document.documentTitle;
      _notesController.text = document.notes;
      _scannedImagePaths = existingImages;
      _currentPreviewIndex = 0;
    });
  }

  void _clearScannedImages() {
    setState(() {
      _scannedImagePaths = [];
      _currentPreviewIndex = 0;
    });
    _showMessage('تم مسح الصور المعروضة');
  }

  Future<String> _createDocumentFolder(String documentNumber) async {
    final folderPath = p.join(_archiveRootPath, documentNumber);
    final folder = Directory(folderPath);

    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    return folderPath;
  }

  Future<List<String>> _moveScannedFilesToDocumentFolder({
    required List<String> scannedFiles,
    required String targetFolderPath,
  }) async {
    final List<String> movedPaths = [];

    for (int i = 0; i < scannedFiles.length; i++) {
      final oldPath = scannedFiles[i];
      final oldFile = File(oldPath);

      if (!await oldFile.exists()) continue;

      final extension = p.extension(oldPath).toLowerCase();
      final newPath = p.join(targetFolderPath, '${i + 1}$extension');
      final newFile = File(newPath);

      await oldFile.copy(newPath);
      await oldFile.delete();

      movedPaths.add(newFile.path);
    }

    return movedPaths;
  }

  Future<void> _saveDocument() async {
    final documentNumber = _documentNumberController.text.trim();
    final documentDate = _documentDateController.text.trim();
    final documentTitle = _documentTitleController.text.trim();
    final notes = _notesController.text.trim();

    if (documentNumber.isEmpty) {
      _showMessage('يرجى إدخال رقم الملف', isError: true);
      return;
    }

    if (documentDate.isEmpty) {
      _showMessage('يرجى اختيار تأريخ الملف', isError: true);
      return;
    }

    if (documentTitle.isEmpty) {
      _showMessage('يرجى إدخال اسم الملف', isError: true);
      return;
    }

    if (_scannedImagePaths.isEmpty) {
      _showMessage('يرجى سحب الملف أولاً من جهاز السكانر', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final existingDocument =
          await _fetchDocumentByNumberFromApi(documentNumber);

      if (existingDocument != null) {
        _showMessage('هذا الملف موجود مسبقاً', isError: true);
        return;
      }

      final folderPath = await _createDocumentFolder(documentNumber);

      final movedImages = await _moveScannedFilesToDocumentFolder(
        scannedFiles: _scannedImagePaths,
        targetFolderPath: folderPath,
      );

      if (movedImages.isEmpty) {
        throw Exception('لم يتم نقل الصور إلى فولدر الملف');
      }

      final document = DocumentModel(
        id: null,
        documentNumber: documentNumber,
        documentDate: documentDate,
        documentTitle: documentTitle,
        notes: notes,
        folderPath: folderPath,
        imagePaths: movedImages,
      );

      await _insertDocumentToApi(document);

      setState(() {
        _savedDocument = null;
        _searchedDocument = null;
        _searchResults = [];
        _scannedImagePaths = [];
        _currentPreviewIndex = 0;
      });

      _showMessage('تم حفظ الملف في قاعدة البيانات وإنشاء الفولدر بنجاح');

      _documentNumberController.clear();
      _documentDateController.clear();
      _documentTitleController.clear();
      _notesController.clear();
      _searchController.clear();
    } catch (e) {
      _showMessage('حدث خطأ أثناء الحفظ: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _printCurrentDocument() async {
    final activeDocument = _searchedDocument ?? _savedDocument;

    if (activeDocument == null) {
      _showMessage('لا يوجد ملف محدد للطباعة', isError: true);
      return;
    }

    final validImagePaths = activeDocument.imagePaths
        .where((path) => File(path).existsSync() && _isImageFile(path))
        .toList();

    if (validImagePaths.isEmpty) {
      _showMessage('لا توجد صور صالحة للطباعة لهذا الملف', isError: true);
      return;
    }

    setState(() {
      _isPrinting = true;
    });

    try {
      final pdf = pw.Document();

      for (final imagePath in validImagePaths) {
        final Uint8List imageBytes = await File(imagePath).readAsBytes();
        final imageProvider = pw.MemoryImage(imageBytes);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(18),
            build: (context) {
              return pw.Center(
                child: pw.Image(
                  imageProvider,
                  fit: pw.BoxFit.contain,
                ),
              );
            },
          ),
        );
      }

      await Printing.layoutPdf(
        name: 'document_${activeDocument.documentNumber}',
        onLayout: (format) async => pdf.save(),
      );
    } catch (e) {
      _showMessage('حدث خطأ أثناء الطباعة: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isPrinting = false;
        });
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.right),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    final bool isMultiline = maxLines > 1;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        minLines: isMultiline ? maxLines : 1,
        readOnly: readOnly,
        onTap: onTap,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 12.4,
          color: darkColor,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: softTextColor.withOpacity(0.7),
            fontSize: 11.4,
          ),
          labelText: label,
          labelStyle: TextStyle(
            color: softTextColor,
            fontSize: 11.4,
            fontWeight: FontWeight.w600,
          ),
          alignLabelWithHint: true,
          prefixIcon: Icon(
            icon,
            color: accentColor,
            size: 18,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: isMultiline ? 8 : 6,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: accentColor, width: 1.1),
          ),
          filled: true,
          fillColor: Colors.transparent,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, {IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: accentColor, size: 18),
          const SizedBox(width: 6),
        ],
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: darkColor,
          ),
        ),
      ],
    );
  }

 Widget _buildTopHeaderCompact() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Row(
      children: [

        // 🔹 فراغ يسار (حتى يدفع النص لليمين)
        const Expanded(
          flex: 2,
          child: SizedBox(),
        ),

        // 🔹 النص يمين
        Expanded(
          flex: 5,
          child: Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'شركة توزيع المنتجات النفطية',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: darkColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'فرع البصرة',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: darkColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'القسم الاداري / شعبة الموارد البشرية /\nوحدة العقوبات',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    color: softTextColor,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
  Widget _buildScannerDropdown() {
    if (_isLoadingScanners) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              'جاري تحميل أجهزة السكانر...',
              style: TextStyle(color: softTextColor, fontSize: 11.4),
            ),
          ],
        ),
      );
    }

    if (_scannerNames.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: accentColor, size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'لم يتم العثور على جهاز سكانر',
                style: TextStyle(
                  color: softTextColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.4,
                ),
              ),
            ),
            TextButton(
              onPressed: _loadScanners,
              child: const Text('إعادة'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedScannerIndex,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          style: TextStyle(
            color: darkColor,
            fontSize: 12.4,
            fontWeight: FontWeight.w600,
          ),
          items: List.generate(_scannerNames.length, (index) {
            return DropdownMenuItem<int>(
              value: index,
              child: Text(
                _scannerNames[index],
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),
          onChanged: (value) {
            setState(() {
              _selectedScannerIndex = value;
            });
          },
        ),
      ),
    );
  }

  Widget _buildScannedImagesPreview() {
    if (_scannedImagePaths.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'الصور المسحوبة',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: darkColor,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _clearScannedImages,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('مسح الصور'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _scannedImagePaths.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final imagePath = _scannedImagePaths[index];
              final imageFile = File(imagePath);

              return Container(
                width: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: imageFile.existsSync()
                      ? Image.file(imageFile, fit: BoxFit.cover)
                      : Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSavedImagesPreview(List<String> imagePaths) {
    final validPaths =
        imagePaths.where((path) => File(path).existsSync()).toList();

    if (validPaths.isEmpty) {
      return Text(
        'لا توجد صور متاحة للعرض',
        style: TextStyle(
          color: softTextColor,
          fontSize: 11.2,
        ),
      );
    }

    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: validPaths.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          return Container(
            width: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(validPaths[index]),
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback? onPressed,
    required String label,
    required IconData icon,
    bool dark = false,
    bool loading = false,
    double height = 34,
  }) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: dark ? darkColor : accentColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: loading
            ? const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Icon(icon, size: 15),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 11.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildOutlinedActionButton({
    required VoidCallback? onPressed,
    required String label,
    required IconData icon,
    bool loading = false,
    double height = 34,
  }) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: darkColor,
          side: BorderSide(color: borderColor),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: loading
            ? const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 15),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 11.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('البحث عن ملف', icon: Icons.search_rounded),
            const SizedBox(height: 8),
            _buildTextField(
              label: 'رقم الملف أو نص البحث',
              icon: Icons.manage_search_rounded,
              controller: _searchController,
              hint: 'مثال: 12345 أو كلمة من الملاحظات',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    onPressed: _isSearching ? null : _searchDocument,
                    label: _isSearching ? 'جاري البحث...' : 'بحث',
                    icon: Icons.search,
                    loading: _isSearching,
                    height: 34,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildOutlinedActionButton(
                    onPressed: _clearSearch,
                    label: 'مسح',
                    icon: Icons.close,
                    height: 34,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniInfoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.72),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value.isEmpty ? '-' : value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: darkColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.2,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$title:',
              style: TextStyle(
                color: softTextColor,
                fontWeight: FontWeight.w700,
                fontSize: 10.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final activeDocument = _searchedDocument ?? _savedDocument;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: activeDocument == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(
                    'نتيجة البحث',
                    icon: Icons.assignment_outlined,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'لم يتم العثور على أي ملف بعد.',
                    style: TextStyle(
                      color: softTextColor,
                      fontSize: 11.2,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(
                    'نتيجة البحث',
                    icon: Icons.assignment_outlined,
                  ),
                  const SizedBox(height: 8),
                  _buildMiniInfoRow('رقم الملف', activeDocument.documentNumber),
                  _buildMiniInfoRow('تأريخ الملف', activeDocument.documentDate),
                  _buildMiniInfoRow('اسم الملف', activeDocument.documentTitle),
                  _buildMiniInfoRow('ملاحظات', activeDocument.notes),
                  _buildMiniInfoRow(
                    'عدد الصور',
                    activeDocument.imagePaths.length.toString(),
                  ),
                  _buildMiniInfoRow('مسار الفولدر', activeDocument.folderPath),
                  const SizedBox(height: 6),
                  _buildActionButton(
                    onPressed: () => _fillFormFromDocument(activeDocument),
                    label: 'تعبئة الحقول',
                    icon: Icons.edit_note_outlined,
                    height: 34,
                  ),
                  const SizedBox(height: 6),
                  _buildActionButton(
                    onPressed: _isPrinting ? null : _printCurrentDocument,
                    label: _isPrinting ? 'جاري تجهيز الطباعة...' : 'طباعة الملف',
                    icon: Icons.print_outlined,
                    dark: true,
                    loading: _isPrinting,
                    height: 34,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'صور الملف',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: darkColor,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _buildSavedImagesPreview(activeDocument.imagePaths),
                  if (_searchResults.length > 1) ...[
                    const SizedBox(height: 8),
                    Text(
                      'نتائج إضافية (${_searchResults.length})',
                      style: TextStyle(
                        fontSize: 11.2,
                        fontWeight: FontWeight.w700,
                        color: darkColor,
                      ),
                    ),
                    const SizedBox(height: 5),
                    ..._searchResults.take(5).map(
                      (doc) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _searchedDocument = doc;
                            });
                            _fillFormFromDocument(doc);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.72),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: borderColor),
                            ),
                            child: Text(
                              '${doc.documentNumber} - ${doc.documentTitle}',
                              style: TextStyle(
                                color: darkColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 10.8,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildPreviewNavigationButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.94),
      borderRadius: BorderRadius.circular(8),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Icon(
            icon,
            color: darkColor,
            size: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildLargePreviewCard({double height = 620}) {
    final hasImages = _scannedImagePaths.isNotEmpty;
    final currentImagePath = hasImages
        ? _scannedImagePaths[_currentPreviewIndex.clamp(
            0,
            _scannedImagePaths.length - 1,
          )]
        : null;

    return Container(
      height: height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildSectionTitle('الصورة الكاملة', icon: Icons.image_outlined),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.72),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: hasImages
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: File(currentImagePath!).existsSync()
                              ? Image.file(
                                  File(currentImagePath),
                                  fit: BoxFit.fill,
                                  width: double.infinity,
                                  height: double.infinity,
                                )
                              : Container(
                                  width: double.infinity,
                                  height: double.infinity,
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      size: 34,
                                    ),
                                  ),
                                ),
                        ),
                        if (_hasMultiplePreviewImages)
                          Positioned(
                            right: 6,
                            child: _buildPreviewNavigationButton(
                              icon: Icons.chevron_right_rounded,
                              onTap: _goToPreviousPreviewImage,
                            ),
                          ),
                        if (_hasMultiplePreviewImages)
                          Positioned(
                            left: 6,
                            child: _buildPreviewNavigationButton(
                              icon: Icons.chevron_left_rounded,
                              onTap: _goToNextPreviewImage,
                            ),
                          ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image_outlined,
                            size: 54,
                            color: accentColor.withOpacity(0.75),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'ستظهر الصورة الكاملة هنا',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: softTextColor,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'بعد السحب من السكانر أو تعبئة الحقول من نتيجة البحث',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: softTextColor,
                              fontSize: 11.2,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accentColor.withOpacity(0.28)),
            ),
            child: Column(
              children: [
                Text(
                  'عدد الصفحات: ${_scannedImagePaths.length}',
                  style: TextStyle(
                    color: darkColor,
                    fontSize: 11.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_hasMultiplePreviewImages) ...[
                  const SizedBox(height: 2),
                  Text(
                    'الصفحة ${_currentPreviewIndex + 1} من ${_scannedImagePaths.length}',
                    style: TextStyle(
                      color: softTextColor,
                      fontSize: 10.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(
              'بيانات الملف',
              icon: Icons.folder_copy_outlined,
            ),
            const SizedBox(height: 5),
            Text(
              'اسحب الملف من جهاز السكانر ثم أدخل البيانات الأساسية.',
              style: TextStyle(
                color: softTextColor,
                height: 1.3,
                fontSize: 10.8,
              ),
            ),
            const SizedBox(height: 8),
            _buildScannerDropdown(),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    onPressed: _isScanning ? null : _startScanAndImport,
                    label: _isScanning ? 'جاري الانتظار...' : 'سحب من السكانر',
                    icon: Icons.document_scanner_outlined,
                    loading: _isScanning,
                    height: 32,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildOutlinedActionButton(
                    onPressed: _isImportingTempImages
                        ? null
                        : () => _loadScannedImagesFromFolder(),
                    label: _isImportingTempImages
                        ? 'جاري التحميل...'
                        : 'تحميل الصور',
                    icon: Icons.folder_open_outlined,
                    loading: _isImportingTempImages,
                    height: 32,
                  ),
                ),
              ],
            ),
            if (_scannedImagePaths.isNotEmpty) ...[
              const SizedBox(height: 7),
              _buildScannedImagesPreview(),
            ],
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    label: 'رقم الملف',
                    icon: Icons.numbers_rounded,
                    controller: _documentNumberController,
                    hint: '12345',
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildTextField(
                    label: 'تأريخ الملف',
                    icon: Icons.calendar_month_outlined,
                    controller: _documentDateController,
                    hint: 'اختر التاريخ',
                    readOnly: true,
                    onTap: _pickDate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _buildTextField(
              label: 'اسم الملف',
              icon: Icons.description_outlined,
              controller: _documentTitleController,
              hint: 'اكتب اسم الملف',
            ),
            const SizedBox(height: 6),
            _buildTextField(
              label: 'ملاحظات',
              icon: Icons.sticky_note_2_outlined,
              controller: _notesController,
              hint: 'أدخل أي ملاحظات إضافية',
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSaveBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: _buildActionButton(
        onPressed: _isLoading ? null : _saveDocument,
        label: _isLoading ? 'جاري الحفظ...' : 'حفظ',
        icon: Icons.save_outlined,
        dark: true,
        loading: _isLoading,
        height: 34,
      ),
    );
  }

  Widget _buildRightColumn() {
    return Column(
      children: [
        _buildTopHeaderCompact(),
        const SizedBox(height: 10),
        _buildSearchCard(),
        const SizedBox(height: 10),
        _buildResultCard(),
        const SizedBox(height: 10),
        _buildInfoCard(),
        const SizedBox(height: 8),
        _buildBottomSaveBar(),
      ],
    );
  }

  Widget _buildWideLayout() {
    return Directionality(
      textDirection: ui.TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: _buildLargePreviewCard(height: 690),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: _buildRightColumn(),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      children: [
        _buildTopHeaderCompact(),
        const SizedBox(height: 10),
        _buildSearchCard(),
        const SizedBox(height: 10),
        _buildResultCard(),
        const SizedBox(height: 10),
        _buildInfoCard(),
        const SizedBox(height: 10),
        _buildLargePreviewCard(height: 460),
        const SizedBox(height: 8),
        _buildBottomSaveBar(),
      ],
    );
  }

  @override
  void dispose() {
    _documentNumberController.dispose();
    _documentDateController.dispose();
    _documentTitleController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: shellColor.withOpacity(0.52),
              borderRadius: BorderRadius.circular(18),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 1100;

                return SingleChildScrollView(
                  child: isWide ? _buildWideLayout() : _buildNarrowLayout(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}