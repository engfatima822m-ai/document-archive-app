import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

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

  bool _isLoading = false;
  bool _isScanning = false;
  bool _isLoadingScanners = false;
  bool _isSearching = false;

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

  @override
  void initState() {
    super.initState();
    _loadScanners();
    _ensureArchiveRootExists();
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

  Future<void> _loadScannedImagesFromFolder() async {
    setState(() {
      _isScanning = true;
    });

    try {
      final directory = Directory(_tempFolderPath);

      if (!await directory.exists()) {
        _showMessage('مجلد السحب غير موجود', isError: true);
        return;
      }

      final files = directory
          .listSync()
          .whereType<File>()
          .where((file) {
            final path = file.path.toLowerCase();
            return path.endsWith('.jpg') ||
                path.endsWith('.jpeg') ||
                path.endsWith('.png');
          })
          .map((file) => file.path)
          .toList();

      if (files.isEmpty) {
        _showMessage('لا توجد صور داخل مجلد السحب', isError: true);
        return;
      }

      files.sort();

      setState(() {
        _scannedImagePaths = files;
      });

      _showMessage('تم تحميل ${files.length} صورة من مجلد السحب');
    } catch (e) {
      _showMessage('حدث خطأ أثناء تحميل الصور: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _startScanAndImport() async {
    try {
      final dir = Directory(_tempFolderPath);

      if (await dir.exists()) {
        final files = dir.listSync();
        for (final file in files) {
          if (file is File) {
            await file.delete();
          }
        }
      }

      await Process.start(
        _scannerExePath,
        [],
        mode: ProcessStartMode.detached,
      );

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('تنفيذ السحب'),
          content: const Text(
            'تم فتح برنامج Canon.\nاسحبي المستند من البرنامج، ثم ارجعي واضغطي موافق.',
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('موافق'),
            ),
          ],
        ),
      );

      await Future.delayed(const Duration(seconds: 2));
      await _loadScannedImagesFromFolder();
    } catch (e) {
      _showMessage('حدث خطأ أثناء تشغيل السكانر: $e', isError: true);
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
            dialogBackgroundColor: cardColor,
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
    });
  }

  void _fillFormFromDocument(DocumentModel document) {
    setState(() {
      _documentNumberController.text = document.documentNumber;
      _documentDateController.text = document.documentDate;
      _documentTitleController.text = document.documentTitle;
      _notesController.text = document.notes;
    });
  }

  void _clearScannedImages() {
    setState(() {
      _scannedImagePaths = [];
    });
    _showMessage('تم مسح الصور المسحوبة');
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

      final movedFile = await oldFile.rename(newPath);
      movedPaths.add(movedFile.path);
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
        _savedDocument = document;
        _searchedDocument = document;
        _searchResults = [document];
        _scannedImagePaths = [];
      });

      _showMessage('تم حفظ الملف في قاعدة البيانات بنجاح');

      _documentNumberController.clear();
      _documentDateController.clear();
      _documentTitleController.clear();
      _notesController.clear();
      _searchController.text = document.documentNumber;
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.65),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        readOnly: readOnly,
        onTap: onTap,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          hintText: hint,
          labelText: label,
          alignLabelWithHint: true,
          prefixIcon: Icon(icon, color: accentColor),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(color: accentColor, width: 1.5),
          ),
          filled: true,
          fillColor: Colors.transparent,
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.78),
            cardColor,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: borderColor),
      ),
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'شركة توزيع المنتجات النفطية/فرع البصرة',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: darkColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'القسم الاداري/شعبة الموارد البشرية/ وحدة العقوبات',
              style: TextStyle(
                fontSize: 14,
                color: softTextColor,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 18),
            _buildBadge('أرشفة الملفات'),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.18),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: accentColor.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: darkColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildScannerDropdown() {
    if (_isLoadingScanners) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.65),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(width: 12),
            Text(
              'جاري تحميل أجهزة السكانر...',
              style: TextStyle(color: softTextColor),
            ),
          ],
        ),
      );
    }

    if (_scannerNames.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.65),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: accentColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'لم يتم العثور على جهاز سكانر',
                style: TextStyle(
                  color: softTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: _loadScanners,
              child: const Text('إعادة التحميل'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.65),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedScannerIndex,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
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
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: darkColor,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _clearScannedImages,
              icon: const Icon(Icons.delete_outline),
              label: const Text('مسح الصور'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _scannedImagePaths.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return Container(
                width: 130,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.file(
                    File(_scannedImagePaths[index]),
                    fit: BoxFit.cover,
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
          fontSize: 14,
        ),
      );
    }

    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: validPaths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return Container(
            width: 115,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
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

  Widget _buildSearchCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'البحث عن ملف',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: darkColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'يمكنك البحث برقم الملف أو بكلمة موجودة داخل اسم الملف أو الملاحظات.',
              style: TextStyle(
                color: softTextColor,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 18),
            _buildTextField(
              label: 'رقم الملف أو نص البحث',
              icon: Icons.search_rounded,
              controller: _searchController,
              hint: 'مثال: 12345 أو كلمة من الملاحظات',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSearching ? null : _searchDocument,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: _isSearching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.2,
                            ),
                          )
                        : const Icon(Icons.search),
                    label: Text(
                      _isSearching ? 'جاري البحث...' : 'بحث',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _clearSearch,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: darkColor,
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: const Icon(Icons.close),
                    label: const Text(
                      'مسح',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'بيانات الملف',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: darkColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'اسحب الملف من جهاز السكانر ثم أدخل البيانات الأساسية واضغط حفظ.',
              style: TextStyle(
                color: softTextColor,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            _buildScannerDropdown(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _startScanAndImport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                icon: _isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : const Icon(Icons.document_scanner_outlined),
                label: Text(
                  _isScanning ? 'جاري الاستيراد...' : 'سحب من السكانر',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (_scannedImagePaths.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildScannedImagesPreview(),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    label: 'رقم الملف',
                    icon: Icons.numbers_rounded,
                    controller: _documentNumberController,
                    hint: 'مثال: 12345',
                  ),
                ),
                const SizedBox(width: 16),
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
            const SizedBox(height: 16),
            _buildTextField(
              label: 'اسم الملف',
              icon: Icons.description_outlined,
              controller: _documentTitleController,
              hint: 'اكتب اسم الملف',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              label: 'ملاحظات',
              icon: Icons.sticky_note_2_outlined,
              controller: _notesController,
              hint: 'أدخل أي ملاحظات إضافية',
              maxLines: 4,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveDocument,
                style: ElevatedButton.styleFrom(
                  backgroundColor: darkColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _isLoading ? 'جاري الحفظ...' : 'حفظ وإنشاء فولدر',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: activeDocument == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'نتيجة البحث / آخر عملية',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: darkColor,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'لم يتم العثور على أي ملف بعد.',
                    style: TextStyle(
                      color: softTextColor,
                      fontSize: 15,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _searchedDocument != null
                        ? 'نتيجة البحث'
                        : 'آخر ملف تم إنشاؤه',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: darkColor,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildMiniInfoRow('رقم الملف', activeDocument.documentNumber),
                  _buildMiniInfoRow('تأريخ الملف', activeDocument.documentDate),
                  _buildMiniInfoRow('اسم الملف', activeDocument.documentTitle),
                  _buildMiniInfoRow('ملاحظات', activeDocument.notes),
                  _buildMiniInfoRow(
                    'عدد الصور',
                    activeDocument.imagePaths.length.toString(),
                  ),
                  _buildMiniInfoRow('مسار الفولدر', activeDocument.folderPath),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _fillFormFromDocument(activeDocument),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          icon: const Icon(Icons.edit_note_outlined),
                          label: const Text('تعبئة الحقول'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'صور الملف',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: darkColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSavedImagesPreview(activeDocument.imagePaths),
                  if (_searchResults.length > 1) ...[
                    const SizedBox(height: 18),
                    Text(
                      'نتائج إضافية مرتبطة بالبحث (${_searchResults.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: darkColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._searchResults.take(5).map(
                      (doc) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _searchedDocument = doc;
                              _fillFormFromDocument(doc);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.65),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderColor),
                            ),
                            child: Text(
                              '${doc.documentNumber} - ${doc.documentTitle}',
                              style: TextStyle(
                                color: darkColor,
                                fontWeight: FontWeight.w600,
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

  Widget _buildMiniInfoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.65),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: darkColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$title:',
              style: TextStyle(
                color: softTextColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

 Widget _buildSideStatsCard() {
  return Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: const Color(0xFFE7E3DB),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Icon(
              Icons.auto_awesome,
              color: accentColor,
              size: 32,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.65),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: borderColor),
              ),
              child: _scannedImagePaths.isNotEmpty
                  ? Column(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.file(
                              File(_scannedImagePaths.first),
                              fit: BoxFit.contain,
                              width: double.infinity,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: accentColor.withOpacity(0.28),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.collections_outlined,
                                color: accentColor,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'عدد الصفحات المسحوبة: ${_scannedImagePaths.length}',
                                style: TextStyle(
                                  color: darkColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
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
                            size: 72,
                            color: accentColor.withOpacity(0.75),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'ستظهر أول صورة من الملف هنا بعد السحب من السكانر',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: softTextColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'وسيظهر أسفلها عدد الصفحات المسحوبة',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: softTextColor,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}
  Widget _buildDarkTile(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 13,
            ),
          ),
        ],
      ),
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
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: shellColor.withOpacity(0.55),
              borderRadius: BorderRadius.circular(36),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 1000;

                return SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildTopHeader(),
                      const SizedBox(height: 20),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: Column(
                                children: [
                                  _buildResultCard(),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    height: 520,
                                    child: _buildSideStatsCard(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 3,
                              child: Column(
                                children: [
                                  _buildSearchCard(),
                                  const SizedBox(height: 20),
                                  _buildInfoCard(),
                                ],
                              ),
                            ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            _buildSearchCard(),
                            const SizedBox(height: 20),
                            _buildInfoCard(),
                            const SizedBox(height: 20),
                            _buildResultCard(),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 420,
                              child: _buildSideStatsCard(),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}