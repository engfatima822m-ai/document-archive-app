import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/document_model.dart';
import '../services/scanner_service.dart';
import 'documents_by_status_screen.dart';
import 'document_search_screen.dart';
import 'reminders_screen.dart';

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
  final TextEditingController _parentDocumentNumberController =
      TextEditingController();
  final TextEditingController _parentDocumentTitleController =
      TextEditingController();
  final TextEditingController _subDocumentNumberController =
      TextEditingController();
  final TextEditingController _reminderDateController =
      TextEditingController();
  final TextEditingController _reminderNoteController =
      TextEditingController();

  final ScannerService _scannerService = ScannerService();

  static const String _archiveRootPath = r'D:\DocumentArchive';
  static const String _backupRootPath = r'E:\DocumentArchiveBackup';
  static const String _databaseName = 'document_archive_db';
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
  bool _isImportingTempImages = false;
  bool _isPrinting = false;
  bool _isLoadingParentDocuments = false;
  bool _isRefreshingApp = false;
  bool _isBackingUp = false;

  bool _isSubDocument = false;
  String _selectedStatus = 'قيد الإنجاز';
  String? _selectedCategory;
  String? _selectedCommitteeFolderPath;

  final List<String> _categories = const [
    'عقوبات',
    'كتب',
    'محاضر لجان تحقيقية',
    'مذكرات',
  ];

  DocumentModel? _savedDocument;
  DocumentModel? _selectedParentDocument;
  List<DocumentModel> _parentDocumentOptions = [];

  final Color bgColor = const Color(0xFFF6F8FC);
  final Color shellColor = const Color(0xFFEAF1FB);
  final Color cardColor = const Color(0xFFFFFFFF);
  final Color accentColor = const Color(0xFF1E3A5F);
  final Color accentLightColor = const Color(0xFF3B82F6);
  final Color accentDarkColor = const Color(0xFF0F172A);
  final Color darkColor = const Color(0xFF1E293B);
  final Color softTextColor = const Color(0xFF64748B);
  final Color borderColor = const Color(0xFFD6E2F0);

  String get _apiBaseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2/document_api';
    }
    return 'http://localhost/document_api';
  }

  bool get _hasMultiplePreviewImages => _scannedImagePaths.length > 1;

  LinearGradient get _mainGradient => LinearGradient(
        colors: [accentColor, accentLightColor],
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
      );

  LinearGradient get _softGradient => const LinearGradient(
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFF8FAFC),
        ],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      );

  LinearGradient get _headerGradient => const LinearGradient(
        colors: [
          Color(0xFFF8FAFC),
          Color(0xFFDBEAFE),
        ],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      );

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
        lower.endsWith('.tiff') ||
        lower.endsWith('.webp');
  }

  String _normalizeDateOnly(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _openRemindersScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const RemindersScreen(),
      ),
    );

    if (!mounted) return;

    if (result is Map) {
      final bool changed = result['changed'] == true;
      final dynamic selectedDocument = result['document'];

      if (changed) {
        _showMessage('تم تحديث التنبيهات');
      }

      if (selectedDocument is DocumentModel) {
        setState(() {
          _savedDocument = selectedDocument;
        });

        await _fillFormFromDocument(selectedDocument);

        if (!mounted) return;
        _showMessage('تم فتح تفاصيل الملف ${selectedDocument.documentNumber}');
      }
    }
  }

  String _committeeBaseFolderPath() {
    final dateText = _documentDateController.text.trim();
    final yearFolder = dateText.length >= 4
        ? _safeFolderName(dateText.substring(0, 4))
        : _safeFolderName(DateTime.now().year.toString());

    return p.join(_archiveRootPath, yearFolder, 'محاضر لجان تحقيقية');
  }

  bool _isSelectedCommitteeFolderInsideBase(String selectedPath) {
    final base = p.normalize(_committeeBaseFolderPath()).toLowerCase();
    final selected = p.normalize(selectedPath).toLowerCase();

    return selected == base || selected.startsWith('$base${Platform.pathSeparator}');
  }

  Future<void> _pickCommitteeFolder() async {
    try {
      final basePath = _committeeBaseFolderPath();
      final baseDir = Directory(basePath);

      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }

      final selectedPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'اختاري أو أنشئي فولدر رئيس اللجنة',
        initialDirectory: basePath,
      );

      if (selectedPath == null || selectedPath.trim().isEmpty) {
        return;
      }

      if (!_isSelectedCommitteeFolderInsideBase(selectedPath)) {
        _showMessage(
          'يرجى اختيار فولدر داخل مسار محاضر لجان تحقيقية فقط',
          isError: true,
        );
        return;
      }

      setState(() {
        _selectedCommitteeFolderPath = selectedPath;
      });

      _showMessage('تم اختيار فولدر رئيس اللجنة: ${p.basename(selectedPath)}');
    } catch (e) {
      _showMessage('تعذر اختيار فولدر رئيس اللجنة: $e', isError: true);
    }
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

  Future<void> _evictImageCacheForPaths(List<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await FileImage(file).evict();
        }
      } catch (_) {}
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
    // مهم: لا نستخدم TWAIN هنا حتى لا يمسك درايفر السكانر ويمنع برنامج Canon من السحب.
    // السحب الفعلي يتم عن طريق تشغيل برنامج CaptureOnTouch فقط.
    setState(() {
      _isLoadingScanners = false;
      _scannerNames = ['Canon CaptureOnTouch'];
      _selectedScannerIndex = 0;
    });
  }

  Future<void> _loadScannedImagesFromFolder({bool showMessage = true}) async {
    final oldImages = List<String>.from(_scannedImagePaths);

    setState(() {
      _isImportingTempImages = true;

      // مهم جدًا: نفرغ الصور المعروضة حتى لا تبقى صورة قديمة في الذاكرة.
      _scannedImagePaths = [];
      _currentPreviewIndex = 0;
    });

    try {
      // نمسح كاش الصور القديمة والجديدة لأن برنامج Canon قد يحفظ بنفس الاسم مثل Image_001.
      await _evictImageCacheForPaths(oldImages);

      final files = await _getScannedFilesFromTempFolder();

      if (files.isEmpty) {
        if (showMessage) {
          _showMessage('لا توجد صور داخل C:\\ScannedTemp', isError: true);
        }
        return;
      }

      await _evictImageCacheForPaths(files);
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

  Future<void> _runWindowsCommand(String command) async {
    if (!Platform.isWindows) return;

    try {
      await Process.run(
        'cmd',
        ['/c', command],
        runInShell: true,
      );
    } catch (_) {}
  }

  Future<void> _closeCanonScannerProcesses() async {
    // نغلق كل العمليات المحتملة الخاصة ببرنامج Canon/CaptureOnTouch
    // حتى لا يبقى درايفر ISIS محجوز وتظهر رسالة Error:80FD1131.
    if (!Platform.isWindows) return;

    final processNames = <String>[
      'TouchDR.exe',
      'TouchDR2.exe',
      'CaptureOnTouch.exe',
      'CaptureOnTouchV5Pro.exe',
      'COT.exe',
      'COTMgr.exe',
      'DRScanner.exe',
      'DRScannerService.exe',
    ];

    for (final processName in processNames) {
      await _runWindowsCommand('taskkill /F /T /IM "$processName"');
    }

    // احتياط إضافي: نغلق أي عملية اسمها يحتوي CaptureOnTouch أو TouchDR فقط.
    // هذا لا يغيّر تصميم التطبيق، فقط يحرر الدرايفر قبل السحبة التالية.
    try {
      await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r"Get-Process | Where-Object { $_.ProcessName -like '*TouchDR*' -or $_.ProcessName -like '*CaptureOnTouch*' -or $_.ProcessName -like '*COT*' -or $_.ProcessName -like '*DRScanner*' } | Stop-Process -Force -ErrorAction SilentlyContinue",
        ],
        runInShell: true,
      );
    } catch (_) {}

    // ننتظر قليلاً لأن درايفر ISIS يحتاج ثواني حتى يتحرر بعد إغلاق البرنامج.
    await Future.delayed(const Duration(milliseconds: 700));
  }

  Future<void> _startCanonScannerProgram() async {
    final scannerExe = File(_scannerExePath);

    if (!await scannerExe.exists()) {
      throw Exception(
        'تعذر العثور على برنامج السكانر في المسار:\n$_scannerExePath',
      );
    }

    await Process.start(
      _scannerExePath,
      [],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );

    // نمهل برنامج Canon حتى يفتح ويتعرف على السكانر قبل أي إجراء آخر.
    await Future.delayed(const Duration(seconds: 1));
  }

  Future<bool> _waitAndLoadScannedImages() async {
    for (int i = 0; i < 20; i++) {
      final files = await _getScannedFilesFromTempFolder();

      if (files.isNotEmpty) {
        // مهم: نفس اسم الصورة قد يتكرر بين السحبات، لذلك نمسح الكاش قبل العرض.
        await _evictImageCacheForPaths(files);
        _setPreviewImages(files);
        return true;
      }

      await Future.delayed(const Duration(seconds: 1));
    }

    return false;
  }

  Future<void> _startScanAndImport() async {
    setState(() {
      _isScanning = true;
      _scannedImagePaths = [];
      _currentPreviewIndex = 0;
    });

    try {
      await _ensureTempFolderExists();

      // قبل كل سحب: نغلق أي نسخة قديمة من Canon وننتظر تحرير درايفر ISIS.
      await _closeCanonScannerProcesses();

      // نفرغ مجلد السحب المؤقت حتى لا يقرأ التطبيق صوراً قديمة.
      await _clearTempFolder();

      // نفتح برنامج Canon من جديد كجلسة نظيفة.
      await _startCanonScannerProgram();

      if (!mounted) return;

      final bool? scanCompleted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: cardColor,
          title: const Text('تنفيذ السحب'),
          content: const Text(
            'تم فتح برنامج Canon.\n\n'
            '1- اسحب الأوراق من برنامج Canon.\n'
            '2- بعد انتهاء السحب اضغط Finish داخل برنامج Canon.\n'
            '3- انتظر ثانيتين، ثم ارجع للتطبيق واضغط "تم السحب".\n\n'
            'إذا حدث خلل في جهاز السكانر أو أُلغيت العملية، اضغط "إلغاء / خروج" حتى يغلق التطبيق برنامج Canon ويحرر درايفر ISIS.\n\n'
            'التطبيق سيغلق برنامج Canon بعد تحميل الصور حتى لا يبقى درايفر ISIS محجوزاً للسحبة القادمة.',
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('إلغاء / خروج'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('تم السحب'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (scanCompleted != true) {
        await _closeCanonScannerProcesses();

        if (!mounted) return;

        setState(() {
          _scannedImagePaths = [];
          _currentPreviewIndex = 0;
        });

        _showMessage('تم إلغاء عملية السحب');
        return;
      }
      if (!mounted) return;

      // بعد الضغط على تم السحب نحمّل الصور أولاً.
      final loaded = await _waitAndLoadScannedImages();

      // ثم نغلق Canon وننتظر حتى يتحرر الدرايفر للمرة القادمة.
      await _closeCanonScannerProcesses();

      if (!loaded) {
        _showMessage(
          'لم يتم العثور على صور جديدة بعد السحب. تأكدي أن برنامج Canon يحفظ الصور داخل C:\\ScannedTemp',
          isError: true,
        );
        return;
      }

      _showMessage('تم تحميل ${_scannedImagePaths.length} صورة بنجاح');
    } catch (e) {
      await _closeCanonScannerProcesses();
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
      _documentDateController.text = _normalizeDateOnly(picked);
      setState(() {});
    }
  }

  Future<void> _pickReminderDate() async {
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
      _reminderDateController.text = _normalizeDateOnly(picked);
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
      category: map['category']?.toString(),
      notes: (map['notes'] ?? '').toString(),
      status: (map['status'] ?? 'قيد الإنجاز').toString(),
      reminderDate: map['reminder_date']?.toString(),
      reminderNote: map['reminder_note']?.toString(),
      folderPath: (map['folder_path'] ?? '').toString(),
      imagePaths: imagePaths,
    );
  }

  DocumentModel _attachmentFromJson(Map<String, dynamic> map) {
    final rawImagePaths = map['image_paths'];

    List<String> imagePaths = [];
    if (rawImagePaths is List) {
      imagePaths = rawImagePaths.map((e) => e.toString()).toList();
    }

    return DocumentModel(
      id: map['id'] is int ? map['id'] : int.tryParse('${map['id']}'),
      documentNumber: (map['sub_document_number'] ?? '').toString(),
      documentDate: (map['sub_document_date'] ?? '').toString(),
      documentTitle: (map['sub_document_title'] ?? '').toString(),
      category: map['category']?.toString(),
      notes: (map['notes'] ?? '').toString(),
      status: 'كتاب تابع',
      reminderDate: map['reminder_date']?.toString(),
      reminderNote: map['reminder_note']?.toString(),
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

    final List docs = data['documents'] ?? [];
    return docs
        .map((item) => _documentFromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> _loadParentDocumentOptions({bool showMessage = false}) async {
    setState(() {
      _isLoadingParentDocuments = true;
    });

    try {
      final allDocuments = await _fetchAllDocumentsFromApi();

      final mainDocuments = allDocuments.where((doc) {
        return doc.status.trim() != 'كتاب تابع' &&
            doc.documentNumber.trim().isNotEmpty &&
            doc.documentTitle.trim().isNotEmpty;
      }).toList();

      mainDocuments.sort((a, b) {
        final aDate = DateTime.tryParse(a.documentDate) ?? DateTime(1900, 1, 1);
        final bDate = DateTime.tryParse(b.documentDate) ?? DateTime(1900, 1, 1);
        return bDate.compareTo(aDate);
      });

      if (!mounted) return;

      setState(() {
        _parentDocumentOptions = mainDocuments;

        if (_selectedParentDocument != null) {
          final stillExists = mainDocuments.any((doc) =>
              doc.documentNumber == _selectedParentDocument!.documentNumber &&
              doc.documentDate == _selectedParentDocument!.documentDate &&
              doc.documentTitle == _selectedParentDocument!.documentTitle);

          if (!stillExists) {
            _selectedParentDocument = null;
            _parentDocumentNumberController.clear();
            _parentDocumentTitleController.clear();
          }
        }
      });

      if (showMessage) {
        _showMessage('تم تحديث قائمة الملفات الأصلية');
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('تعذر تحميل الملفات الأصلية: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingParentDocuments = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchDocumentWithAttachmentsFromApi(
    String documentNumber,
  ) async {
    final uri = Uri.parse('$_apiBaseUrl/get_document_by_number.php').replace(
      queryParameters: {'document_number': documentNumber},
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('فشل الاتصال بالخادم أثناء البحث');
    }

    final data = jsonDecode(response.body);

    if (data['success'] == true && data['document'] != null) {
      final document = _documentFromJson(
        Map<String, dynamic>.from(data['document']),
      );

      final List attachmentsJson = data['attachments'] ?? [];
      final attachments = attachmentsJson
          .map(
            (item) => _attachmentFromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();

      return {
        'document': document,
        'attachments': attachments,
      };
    }

    return null;
  }

  Future<DocumentModel?> _fetchDocumentByNumberFromApi(
    String documentNumber,
  ) async {
    final result = await _fetchDocumentWithAttachmentsFromApi(documentNumber);
    return result?['document'] as DocumentModel?;
  }


  Future<void> _ensureParentDocumentSelectedFromNumber() async {
    final typedNumber = _parentDocumentNumberController.text.trim();
    if (typedNumber.isEmpty) return;

    if (_parentDocumentOptions.isEmpty) {
      await _loadParentDocumentOptions();
    }

    if (!mounted) return;

    final normalizedTypedNumber = typedNumber.toLowerCase();

    final exactMatches = _parentDocumentOptions.where((doc) {
      return doc.documentNumber.trim().toLowerCase() == normalizedTypedNumber;
    }).toList();

    if (exactMatches.isEmpty) {
      setState(() {
        _selectedParentDocument = null;
      });
      return;
    }

    exactMatches.sort((a, b) {
      final aDate = DateTime.tryParse(a.documentDate) ?? DateTime(1900, 1, 1);
      final bDate = DateTime.tryParse(b.documentDate) ?? DateTime(1900, 1, 1);
      return bDate.compareTo(aDate);
    });

    final selected = exactMatches.first;

    setState(() {
      _selectedParentDocument = selected;
      _parentDocumentNumberController.text = selected.documentNumber;
      _parentDocumentTitleController.text = selected.documentTitle;

      // القاعدة الجديدة: الكتاب التابع يأخذ تصنيف الملف الأصلي تلقائياً.
      if (_isSubDocument && _categories.contains(selected.category)) {
        _selectedCategory = selected.category;
        _selectedCommitteeFolderPath = null;
      }
    });
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
        'category': document.category,
        'notes': document.notes,
        'status': document.status,
        'reminder_date': document.reminderDate,
        'reminder_note': document.reminderNote,
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

  Future<void> _insertAttachmentToApi({
    required String parentDocumentNumber,
    required String parentDocumentTitle,
    required String subDocumentNumber,
    required String subDocumentDate,
    required String subDocumentTitle,
    required String notes,
    String? category,
    String? reminderDate,
    String? reminderNote,
    required String folderPath,
    required List<String> imagePaths,
  }) async {
    final uri = Uri.parse('$_apiBaseUrl/insert_attachment.php');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({
        'parent_document_number': parentDocumentNumber,
        'parent_document_title': parentDocumentTitle,
        'sub_document_number': subDocumentNumber,
        'sub_document_date': subDocumentDate,
        'sub_document_title': subDocumentTitle,
        'category': category,
        'notes': notes,
        'reminder_date': reminderDate,
        'reminder_note': reminderNote,
        'folder_path': folderPath,
        'image_paths': imagePaths,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('فشل الاتصال بالخادم أثناء حفظ الكتاب التابع');
    }

    final data = jsonDecode(response.body);

    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'فشل حفظ الكتاب التابع');
    }
  }

  String _resolveDocumentRootFolderPath(String folderPath) {
    if (folderPath.trim().isEmpty) return '';

    final normalized = p.normalize(folderPath);
    final folderName = p.basename(normalized).toLowerCase();

    if (folderName == 'original') {
      return p.dirname(normalized);
    }

    return normalized;
  }

  int _extractLeadingNumber(String filePath) {
    final fileName = p.basenameWithoutExtension(filePath).trim();
    final match = RegExp(r'^\d+').firstMatch(fileName);
    if (match == null) return -1;
    return int.tryParse(match.group(0) ?? '') ?? -1;
  }

  Future<List<String>> _loadAllImagesFromDocumentFolder(
      String folderPath) async {
    try {
      final rootFolderPath = _resolveDocumentRootFolderPath(folderPath);

      if (rootFolderPath.isEmpty) {
        return [];
      }

      final rootDir = Directory(rootFolderPath);
      if (!await rootDir.exists()) {
        return [];
      }

      final List<String> imagePaths = [];

      await for (final entity
          in rootDir.list(recursive: true, followLinks: false)) {
        if (entity is File && _isImageFile(entity.path)) {
          imagePaths.add(entity.path);
        }
      }

      imagePaths.sort((a, b) {
        final aIsOriginal = a.toLowerCase().contains(
          '${Platform.pathSeparator}original${Platform.pathSeparator}',
        );
        final bIsOriginal = b.toLowerCase().contains(
          '${Platform.pathSeparator}original${Platform.pathSeparator}',
        );

        if (aIsOriginal && !bIsOriginal) return -1;
        if (!aIsOriginal && bIsOriginal) return 1;

        final aNum = _extractLeadingNumber(a);
        final bNum = _extractLeadingNumber(b);

        if (aNum != -1 && bNum != -1 && aNum != bNum) {
          return aNum.compareTo(bNum);
        }

        return a.toLowerCase().compareTo(b.toLowerCase());
      });

      return imagePaths;
    } catch (e) {
      _showMessage('حدث خطأ أثناء جلب صور الملف: $e', isError: true);
      return [];
    }
  }



  void _clearScreenAfterSuccessfulSave() {
    if (!mounted) return;

    setState(() {
      _savedDocument = null;
      _scannedImagePaths = [];
      _currentPreviewIndex = 0;
      _isSubDocument = false;
      _selectedStatus = 'قيد الإنجاز';
      _selectedCategory = null;
      _selectedCommitteeFolderPath = null;

      _documentNumberController.clear();
      _documentDateController.clear();
      _documentTitleController.clear();
      _notesController.clear();
      _parentDocumentNumberController.clear();
      _parentDocumentTitleController.clear();
      _subDocumentNumberController.clear();
      _selectedParentDocument = null;
      _reminderDateController.clear();
      _reminderNoteController.clear();
    });
  }


  String _backupTimestamp() {
    final now = DateTime.now();

    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}-'
        '${now.minute.toString().padLeft(2, '0')}-'
        '${now.second.toString().padLeft(2, '0')}';
  }

  Future<String> _findMySqlDumpPath() async {
    final candidates = <String>[
      r'C:\xampp\mysql\bin\mysqldump.exe',
      r'C:\xampp8\mysql\bin\mysqldump.exe',
      r'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqldump.exe',
      r'C:\Program Files\MySQL\MySQL Server 5.7\bin\mysqldump.exe',
    ];

    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }

    final whereResult = await Process.run(
      'where',
      ['mysqldump'],
      runInShell: true,
    );

    if (whereResult.exitCode == 0) {
      final lines = whereResult.stdout
          .toString()
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      if (lines.isNotEmpty) {
        return lines.first;
      }
    }

    throw Exception(
      'لم يتم العثور على mysqldump. تأكدي من وجود XAMPP أو MySQL على الحاسبة.',
    );
  }

  Future<String> _backupDatabaseToE(String databaseBackupFolderPath) async {
    final databaseBackupDir = Directory(databaseBackupFolderPath);
    if (!await databaseBackupDir.exists()) {
      await databaseBackupDir.create(recursive: true);
    }

    final mysqldumpPath = await _findMySqlDumpPath();
    final backupFilePath = p.join(
      databaseBackupFolderPath,
      '${_databaseName}_${_backupTimestamp()}.sql',
    );

    final result = await Process.run(
      mysqldumpPath,
      [
        '--user=root',
        '--host=127.0.0.1',
        '--default-character-set=utf8mb4',
        _databaseName,
      ],
      stdoutEncoding: null,
      stderrEncoding: utf8,
    );

    if (result.exitCode != 0) {
      final errorText = result.stderr.toString().trim();
      throw Exception(
        errorText.isEmpty
            ? 'فشل تصدير قاعدة البيانات'
            : 'فشل تصدير قاعدة البيانات: $errorText',
      );
    }

    final stdoutData = result.stdout;
    final bytes = stdoutData is List<int>
        ? stdoutData
        : utf8.encode(stdoutData.toString());

    await File(backupFilePath).writeAsBytes(bytes, flush: true);

    return backupFilePath;
  }

  Future<void> _backupArchiveIncrementallyToE(
    String archiveBackupFolderPath,
  ) async {
    final sourceDir = Directory(_archiveRootPath);
    if (!await sourceDir.exists()) {
      throw Exception('مجلد الأرشيف الأصلي غير موجود: $_archiveRootPath');
    }

    final targetDir = Directory(archiveBackupFolderPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final result = await Process.run(
      'robocopy',
      [
        _archiveRootPath,
        archiveBackupFolderPath,
        '/E',
        '/XO',
        '/FFT',
        '/R:2',
        '/W:2',
        '/NP',
      ],
      runInShell: true,
    );

    // robocopy يعتبر الأكواد من 0 إلى 7 نجاحاً أو نجاحاً مع ملاحظات.
    if (result.exitCode > 7) {
      final errorText = result.stderr.toString().trim();
      throw Exception(
        errorText.isEmpty
            ? 'فشل نسخ الأرشيف إلى E'
            : 'فشل نسخ الأرشيف إلى E: $errorText',
      );
    }
  }

  Future<void> _createIncrementalBackup() async {
    if (_isBackingUp) return;

    if (!Platform.isWindows) {
      _showMessage('ميزة النسخ الاحتياطي تعمل على Windows فقط', isError: true);
      return;
    }

    final backupRootDir = Directory(_backupRootPath);
    final backupDriveDir = Directory(r'E:\');

    if (!await backupDriveDir.exists()) {
      _showMessage('القرص E غير موجود. تأكدي من وجوده قبل النسخ الاحتياطي.', isError: true);
      return;
    }

    setState(() {
      _isBackingUp = true;
    });

    try {
      if (!await backupRootDir.exists()) {
        await backupRootDir.create(recursive: true);
      }

      final databaseBackupFolderPath = p.join(_backupRootPath, 'Database');
      final archiveBackupFolderPath = p.join(_backupRootPath, 'DocumentArchive');

      final databaseBackupFilePath =
          await _backupDatabaseToE(databaseBackupFolderPath);

      await _backupArchiveIncrementallyToE(archiveBackupFolderPath);

      if (!mounted) return;

      _showMessage(
        'تم إنشاء النسخة الاحتياطية بنجاح على E\n'
        'قاعدة البيانات: ${p.basename(databaseBackupFilePath)}\n'
        'الأرشيف: $archiveBackupFolderPath',
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage('حدث خطأ أثناء النسخ الاحتياطي: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
        });
      }
    }
  }

  Future<void> _refreshApp() async {
    if (_isRefreshingApp) return;

    setState(() {
      _isRefreshingApp = true;
    });

    try {
      // تنظيف حالة الصفحة بالكامل مثل فتح التطبيق من جديد
      _savedDocument = null;
      _scannedImagePaths = [];
      _currentPreviewIndex = 0;
      _isSubDocument = false;
      _selectedStatus = 'قيد الإنجاز';
      _selectedCategory = null;
      _selectedCommitteeFolderPath = null;

      _documentNumberController.clear();
      _documentDateController.clear();
      _documentTitleController.clear();
      _notesController.clear();
      _parentDocumentNumberController.clear();
      _parentDocumentTitleController.clear();
      _subDocumentNumberController.clear();
      _selectedParentDocument = null;
      _reminderDateController.clear();
      _reminderNoteController.clear();

      // إغلاق أي عملية Canon معلقة حتى لا يبقى السكانر محجوزاً
      await _closeCanonScannerProcesses();

      // تنظيف مجلد السحب المؤقت من صور قديمة
      await _clearTempFolder();

      // إعادة تهيئة المجلدات والسكانر
      await _ensureArchiveRootExists();
      await _ensureTempFolderExists();
      await _loadScanners();

      if (!mounted) return;

      _showMessage('تم تحديث وتنظيف التطبيق بنجاح');
    } catch (e) {
      if (!mounted) return;
      _showMessage('حدث خطأ أثناء تحديث التطبيق: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingApp = false;
        });
      }
    }
  }

  Future<void> _fillFormFromDocument(DocumentModel document) async {
    List<String> folderImages = [];

    if (document.folderPath.trim().isNotEmpty) {
      folderImages = await _loadAllImagesFromDocumentFolder(document.folderPath);
    }

    if (folderImages.isEmpty) {
      folderImages =
          document.imagePaths.where((path) => File(path).existsSync()).toList();
    }

    setState(() {
      _isSubDocument = false;
      _documentNumberController.text = document.documentNumber;
      _documentDateController.text = document.documentDate;
      _documentTitleController.text = document.documentTitle;
      _notesController.text = document.notes;
      _selectedStatus = ['قيد الإنجاز', 'منجز', 'تم الاطلاع'].contains(document.status)
          ? document.status
          : 'قيد الإنجاز';
      _selectedCategory = _categories.contains(document.category)
          ? document.category
          : null;
      _selectedCommitteeFolderPath = null;
      _reminderDateController.text = document.reminderDate ?? '';
      _reminderNoteController.text = document.reminderNote ?? '';
      _parentDocumentNumberController.text = document.documentNumber;
      _parentDocumentTitleController.text = document.documentTitle;
      _selectedParentDocument = null;
      _subDocumentNumberController.clear();
      _scannedImagePaths = folderImages;
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

  String _safeFolderName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');

    return cleaned.isEmpty ? 'بدون_اسم' : cleaned;
  }

  Future<String> _createMainDocumentFolder({
    required String documentNumber,
    required String documentDate,
    required String documentTitle,
    required String category,
  }) async {
    final safeNumber = _safeFolderName(documentNumber);
    final safeDate = _safeFolderName(documentDate);
    final safeTitle = _safeFolderName(documentTitle);
    final safeCategory = _safeFolderName(category);
    final yearFolder = documentDate.trim().length >= 4
        ? _safeFolderName(documentDate.trim().substring(0, 4))
        : _safeFolderName(DateTime.now().year.toString());

    // مهم: اسم الفولدر صار يعتمد على الرقم + التاريخ + الاسم
    // حتى إذا تكرر نفس الرقم مع تاريخ أو اسم مختلف ينحفظ بفولدر مستقل.
    final folderName = '${safeNumber}_${safeDate}_$safeTitle';

    String mainFolderPath;

    if (category == 'محاضر لجان تحقيقية') {
      if (_selectedCommitteeFolderPath == null ||
          _selectedCommitteeFolderPath!.trim().isEmpty) {
        throw Exception('يرجى اختيار أو إنشاء فولدر رئيس اللجنة');
      }

      mainFolderPath = p.join(_selectedCommitteeFolderPath!, folderName);
    } else {
      mainFolderPath = p.join(
        _archiveRootPath,
        yearFolder,
        safeCategory,
        folderName,
      );
    }

    final originalFolderPath = p.join(mainFolderPath, 'original');

    final mainFolder = Directory(mainFolderPath);
    final originalFolder = Directory(originalFolderPath);

    if (!await mainFolder.exists()) {
      await mainFolder.create(recursive: true);
    }

    if (!await originalFolder.exists()) {
      await originalFolder.create(recursive: true);
    }

    return originalFolderPath;
  }

  Future<String?> _findParentDocumentFolderPath(
  String parentDocumentNumber, {
  String? parentDocumentTitle,
}) async {
  final rootDir = Directory(_archiveRootPath);
  if (!await rootDir.exists()) return null;

  final selectedParent = _selectedParentDocument;
  if (selectedParent != null &&
      selectedParent.documentNumber.trim() == parentDocumentNumber.trim()) {
    final selectedRootPath =
        _resolveDocumentRootFolderPath(selectedParent.folderPath);

    if (selectedRootPath.trim().isNotEmpty) {
      final selectedRootDir = Directory(selectedRootPath);
      if (await selectedRootDir.exists()) {
        return selectedRootDir.path;
      }
    }
  }

  final safeParentNumber = _safeFolderName(parentDocumentNumber).toLowerCase();
  final safeParentTitle = _safeFolderName(parentDocumentTitle ?? '').toLowerCase();

  // دعم النسخ القديمة: D:\DocumentArchive\رقم_الملف
  final oldDirectFolder = Directory(p.join(_archiveRootPath, parentDocumentNumber));
  if (await oldDirectFolder.exists() && safeParentTitle.isEmpty) {
    return oldDirectFolder.path;
  }

  final List<Directory> possibleFolders = [];

  // البحث داخل كل D:\DocumentArchive بشكل recursive
  await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
    if (entity is Directory) {
      final folderName = p.basename(entity.path).toLowerCase();

      // نتجنب فولدر original لأن المطلوب فولدر الملف الأب نفسه
      if (folderName == 'original') continue;

      final matchesNumber =
          folderName == safeParentNumber || folderName.startsWith('${safeParentNumber}_');

      final matchesTitle =
          safeParentTitle.isEmpty || folderName.contains(safeParentTitle);

      if (matchesNumber && matchesTitle) {
        possibleFolders.add(entity);
      }
    }
  }

  if (possibleFolders.isEmpty) return null;

  possibleFolders.sort((a, b) {
    final aTime = a.statSync().modified;
    final bTime = b.statSync().modified;
    return bTime.compareTo(aTime);
  });

  return possibleFolders.first.path;
}

  Future<String> _createManualParentDocumentFolder({
    required String parentDocumentNumber,
    required String parentDocumentTitle,
    required String category,
  }) async {
    final safeParentNumber = _safeFolderName(parentDocumentNumber);
    final safeParentTitle = _safeFolderName(parentDocumentTitle);
    final safeCategory = _safeFolderName(category);
    final dateText = _documentDateController.text.trim();

    final yearFolder = dateText.length >= 4
        ? _safeFolderName(dateText.substring(0, 4))
        : _safeFolderName(DateTime.now().year.toString());

    final folderName = parentDocumentTitle.trim().isEmpty
        ? safeParentNumber
        : '${safeParentNumber}_$safeParentTitle';

    String parentFolderPath;

    if (category == 'محاضر لجان تحقيقية') {
      if (_selectedCommitteeFolderPath == null ||
          _selectedCommitteeFolderPath!.trim().isEmpty) {
        throw Exception('يرجى اختيار أو إنشاء فولدر رئيس اللجنة');
      }

      parentFolderPath = p.join(_selectedCommitteeFolderPath!, folderName);
    } else {
      parentFolderPath = p.join(
        _archiveRootPath,
        yearFolder,
        safeCategory,
        folderName,
      );
    }

    final parentFolder = Directory(parentFolderPath);

    if (!await parentFolder.exists()) {
      await parentFolder.create(recursive: true);
    }

    return parentFolder.path;
  }

  Future<String> _createAttachmentFolder({
    required String parentDocumentNumber,
    required String parentDocumentTitle,
    required String subDocumentNumber,
    required String subDocumentDate,
    required String subDocumentTitle,
    required String category,
  }) async {
    final safeSubDocumentNumber = _safeFolderName(subDocumentNumber);
    final safeSubDocumentDate = _safeFolderName(subDocumentDate);
    final safeSubDocumentTitle = _safeFolderName(subDocumentTitle);

    // القاعدة الجديدة:
    // الكتاب التابع لا ينشئ فولدراً مستقلاً حسب تصنيفه.
    // دائماً ينحفظ داخل فولدر الملف الأصلي ثم داخل attachments.
    final parentFolderPath = await _findParentDocumentFolderPath(
      parentDocumentNumber,
      parentDocumentTitle: parentDocumentTitle,
    );

    if (parentFolderPath == null || parentFolderPath.trim().isEmpty) {
      throw Exception('لم يتم العثور على فولدر الملف الأصلي. اختاري الملف الأصلي من القائمة أو من الأرشيف أولاً.');
    }

    final folderName = subDocumentTitle.trim().isEmpty
        ? '${safeSubDocumentNumber}_$safeSubDocumentDate'
        : '${safeSubDocumentNumber}_${safeSubDocumentDate}_$safeSubDocumentTitle';

    final attachmentFolderPath = p.join(
      parentFolderPath,
      'attachments',
      folderName,
    );

    final attachmentFolder = Directory(attachmentFolderPath);

    if (!await attachmentFolder.exists()) {
      await attachmentFolder.create(recursive: true);
    }

    return attachmentFolderPath;
  }

  Future<int> _getNextImageIndex(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return 1;

    final files = await dir.list().where((e) => e is File).cast<File>().toList();

    final numbers = <int>[];

    for (final file in files) {
      final fileName = p.basenameWithoutExtension(file.path);
      final number = int.tryParse(fileName);
      if (number != null) {
        numbers.add(number);
      }
    }

    if (numbers.isEmpty) return 1;
    numbers.sort();
    return numbers.last + 1;
  }

  Future<List<String>> _moveScannedFilesToDocumentFolder({
    required List<String> scannedFiles,
    required String targetFolderPath,
  }) async {
    final targetDir = Directory(targetFolderPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final List<String> movedPaths = [];
    int nextIndex = await _getNextImageIndex(targetFolderPath);

    for (final oldPath in scannedFiles) {
      final oldFile = File(oldPath);

      if (!await oldFile.exists()) continue;
      if (!_isImageFile(oldPath)) continue;

      final extension = p.extension(oldPath).toLowerCase().isEmpty
          ? '.jpg'
          : p.extension(oldPath).toLowerCase();
      final newPath = p.join(targetFolderPath, '$nextIndex$extension');
      final newFile = File(newPath);

      // إذا كانت الصورة أصلاً داخل فولدر الهدف، لا نحذفها ولا ننسخها فوق نفسها.
      if (p.normalize(oldFile.path).toLowerCase() ==
          p.normalize(newFile.path).toLowerCase()) {
        movedPaths.add(oldFile.path);
        nextIndex++;
        continue;
      }

      await oldFile.copy(newPath);

      // الصور المسحوبة تكون عادة داخل C:\ScannedTemp، لذلك نحذفها بعد نسخها للأرشيف.
      // إذا كان الملف من مكان آخر ومقفول، نتجاهل فشل الحذف حتى لا يتوقف الحفظ.
      try {
        await oldFile.delete();
      } catch (_) {}

      movedPaths.add(newFile.path);
      nextIndex++;
    }

    return movedPaths;
  }

  Future<void> _saveDocument() async {
    final documentNumber = _documentNumberController.text.trim();
    final documentDate = _documentDateController.text.trim();
    final documentTitle = _documentTitleController.text.trim();
    String selectedCategory = _selectedCategory?.trim() ?? '';
    final notes = _notesController.text.trim();
    final parentDocumentNumber = _parentDocumentNumberController.text.trim();
    String parentDocumentTitle = _parentDocumentTitleController.text.trim();
    final subDocumentNumber = _subDocumentNumberController.text.trim();
    final reminderDate = _reminderDateController.text.trim();
    final reminderNote = _reminderNoteController.text.trim();

    if (_isSubDocument) {
      if (parentDocumentNumber.isEmpty) {
        _showMessage('يرجى إدخال رقم الملف الأصلي', isError: true);
        return;
      }

      await _ensureParentDocumentSelectedFromNumber();

      parentDocumentTitle = _parentDocumentTitleController.text.trim();

      final parentCategory = _selectedParentDocument?.category?.trim() ?? '';
      if (parentCategory.isNotEmpty && _categories.contains(parentCategory)) {
        selectedCategory = parentCategory;
        setState(() {
          _selectedCategory = parentCategory;
          _selectedCommitteeFolderPath = null;
        });
      }

      if (subDocumentNumber.isEmpty) {
        _showMessage('يرجى إدخال رقم الكتاب التابع', isError: true);
        return;
      }
    } else {
      if (documentNumber.isEmpty) {
        _showMessage('يرجى إدخال رقم الملف', isError: true);
        return;
      }
    }

    if (documentDate.isEmpty) {
      _showMessage('يرجى اختيار تأريخ الملف', isError: true);
      return;
    }

    if (documentTitle.isEmpty) {
      _showMessage('يرجى إدخال اسم الملف', isError: true);
      return;
    }

    if (selectedCategory.isEmpty) {
      _showMessage(
        _isSubDocument ? 'يرجى اختيار الملف الأصلي حتى يأخذ الكتاب التابع تصنيفه تلقائياً' : 'يرجى اختيار تصنيف الملف',
        isError: true,
      );
      return;
    }

    if (!_isSubDocument &&
        selectedCategory == 'محاضر لجان تحقيقية' &&
        (_selectedCommitteeFolderPath == null ||
            _selectedCommitteeFolderPath!.trim().isEmpty)) {
      _showMessage('يرجى اختيار أو إنشاء فولدر رئيس اللجنة', isError: true);
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
      await _ensureArchiveRootExists();

      if (_isSubDocument) {
        // الكتاب التابع يبقى مربوطاً بالملف الأصلي داخل قاعدة البيانات.
        // وحسب القاعدة الجديدة: الصور تنحفظ داخل فولدر الأصل ثم attachments.
        final folderPath = await _createAttachmentFolder(
          parentDocumentNumber: parentDocumentNumber,
          parentDocumentTitle: parentDocumentTitle,
          subDocumentNumber: subDocumentNumber,
          subDocumentDate: documentDate,
          subDocumentTitle: documentTitle,
          category: selectedCategory,
        );

        final movedImages = await _moveScannedFilesToDocumentFolder(
          scannedFiles: _scannedImagePaths,
          targetFolderPath: folderPath,
        );

        if (movedImages.isEmpty) {
          throw Exception('لم يتم نقل الصور إلى فولدر الكتاب التابع');
        }

        bool apiSaved = true;
        try {
          await _insertAttachmentToApi(
            parentDocumentNumber: parentDocumentNumber,
            parentDocumentTitle: parentDocumentTitle,
            subDocumentNumber: subDocumentNumber,
            subDocumentDate: documentDate,
            subDocumentTitle: documentTitle,
            notes: notes,
            category: selectedCategory,
            reminderDate: reminderDate.isEmpty ? null : reminderDate,
            reminderNote: reminderNote.isEmpty ? null : reminderNote,
            folderPath: folderPath,
            imagePaths: movedImages,
          );
        } catch (_) {
          // لا نلغي حفظ الصور إذا تعذر تسجيل الربط في قاعدة البيانات.
          // الصور محفوظة داخل فولدر الأصل على D، لكن الربط يحتاج نجاح الـ API.
          apiSaved = false;
        }

        final attachmentPreview = DocumentModel(
          id: null,
          documentNumber: subDocumentNumber,
          documentDate: documentDate,
          documentTitle: documentTitle,
          category: selectedCategory,
          notes: notes,
          status: 'كتاب تابع',
          reminderDate: reminderDate.isEmpty ? null : reminderDate,
          reminderNote: reminderNote.isEmpty ? null : reminderNote,
          folderPath: folderPath,
          imagePaths: movedImages,
        );

        setState(() {
          _savedDocument = attachmentPreview;
          _scannedImagePaths = movedImages;
          _currentPreviewIndex = 0;
        });

        _showMessage(
          apiSaved
              ? 'تم حفظ الكتاب التابع داخل فولدر الأصل وربطه بالملف الأصلي بنجاح'
              : 'تم حفظ صور الكتاب التابع داخل فولدر الأصل، لكن لم يتم تسجيل الربط في قاعدة البيانات',
          isError: !apiSaved,
        );
      } else {
        // الملف الرئيسي: ننشئ فولدر باسم رقم الملف داخل D:\DocumentArchive
        // ونضع الصور داخل original. إذا كان الفولدر موجوداً نضيف الصور بتسلسل جديد.
        final folderPath = await _createMainDocumentFolder(
          documentNumber: documentNumber,
          documentDate: documentDate,
          documentTitle: documentTitle,
          category: selectedCategory,
        );

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
          category: selectedCategory,
          notes: notes,
          status: _selectedStatus,
          reminderDate: reminderDate.isEmpty ? null : reminderDate,
          reminderNote: reminderNote.isEmpty ? null : reminderNote,
          folderPath: folderPath,
          imagePaths: movedImages,
        );

        bool apiSaved = true;
        try {
          // مهم: لا نفحص التكرار بالرقم فقط هنا.
          // ملف insert_document.php صار يمنع التكرار حسب الرقم + التاريخ + الاسم.
          await _insertDocumentToApi(document);
        } catch (_) {
          // حتى لو تعطلت قاعدة البيانات، لا نخسر حفظ الصور على D.
          apiSaved = false;
        }

        setState(() {
          _savedDocument = document;
          _scannedImagePaths = movedImages;
          _currentPreviewIndex = 0;
        });

        _showMessage(
          apiSaved
              ? 'تم حفظ الملف الرئيسي داخل D وقاعدة البيانات بنجاح'
              : 'تم حفظ الملف الرئيسي داخل D، لكن لم يتم تسجيله في قاعدة البيانات',
          isError: !apiSaved,
        );
      }

      _clearScreenAfterSuccessfulSave();
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
    final activeDocument = _savedDocument;

    if (activeDocument == null) {
      _showMessage('لا يوجد ملف محدد للطباعة', isError: true);
      return;
    }

    final previewImages =
        _scannedImagePaths.where((path) => File(path).existsSync()).toList();

    final fallbackImages = activeDocument.imagePaths
        .where((path) => File(path).existsSync() && _isImageFile(path))
        .toList();

    final validImagePaths =
        previewImages.isNotEmpty ? previewImages : fallbackImages;

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

  BoxDecoration _cardDecoration({bool gradient = true}) {
    return BoxDecoration(
      color: gradient ? null : cardColor,
      gradient: gradient ? _softGradient : null,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.035),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
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
    ValueChanged<String>? onChanged,
  }) {
    final bool isMultiline = maxLines > 1;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        minLines: isMultiline ? maxLines : 1,
        readOnly: readOnly,
        onTap: onTap,
        onChanged: onChanged,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 15,
          color: darkColor,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: softTextColor.withOpacity(0.72),
            fontSize: 13.2,
          ),
          labelText: label,
          labelStyle: TextStyle(
            color: softTextColor,
            fontSize: 13.2,
            fontWeight: FontWeight.w700,
          ),
          alignLabelWithHint: true,
          prefixIcon: Icon(
            icon,
            color: accentColor,
            size: 20,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: isMultiline ? 16 : 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: accentColor, width: 1.4),
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
          Icon(icon, color: accentColor, size: 22),
          const SizedBox(width: 8),
        ],
        Text(
          title,
          style: TextStyle(
            fontSize: 19,
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
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        gradient: _headerGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'التنبيهات',
                  onPressed: _openRemindersScreen,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.92),
                    foregroundColor: accentColor,
                    padding: const EdgeInsets.all(12),
                  ),
                  icon: const Icon(
                    Icons.notifications_none_rounded,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'نسخ احتياطي إلى E',
                  onPressed: _isBackingUp ? null : _createIncrementalBackup,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.92),
                    foregroundColor: accentColor,
                    padding: const EdgeInsets.all(12),
                  ),
                  icon: _isBackingUp
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup_outlined, size: 26),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'تحديث وتنظيف التطبيق',
                  onPressed: _isRefreshingApp ? null : _refreshApp,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.92),
                    foregroundColor: accentColor,
                    padding: const EdgeInsets.all(12),
                  ),
                  icon: _isRefreshingApp
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 26),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'شركة توزيع المنتجات النفطية',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: darkColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'فرع البصرة',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: darkColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'القسم الاداري / شعبة الموارد البشرية /\nوحدة العقوبات',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      color: softTextColor,
                      height: 1.4,
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'جاري تحميل أجهزة السكانر...',
              style: TextStyle(color: softTextColor, fontSize: 13.5),
            ),
          ],
        ),
      );
    }

    if (_scannerNames.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: accentColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'لم يتم العثور على جهاز سكانر',
                style: TextStyle(
                  color: softTextColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.04),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedScannerIndex,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
          style: TextStyle(
            color: darkColor,
            fontSize: 14.5,
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
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: darkColor,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _clearScannedImages,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('مسح الصور'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _scannedImagePaths.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final imagePath = _scannedImagePaths[index];
              final imageFile = File(imagePath);

              return Container(
                width: 86,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withOpacity(0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
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
          fontSize: 13,
        ),
      );
    }

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: validPaths.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return Container(
            width: 76,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
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
    double height = 48,
  }) {
    final gradient = dark
        ? LinearGradient(
            colors: [accentDarkColor, accentColor],
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
          )
        : _mainGradient;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.22),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Icon(icon, size: 18),
          label: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
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
    double height = 48,
  }) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: darkColor,
          backgroundColor: Colors.white.withOpacity(0.9),
          side: BorderSide(color: borderColor),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewNavigationButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.95),
      borderRadius: BorderRadius.circular(10),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Icon(
            icon,
            color: darkColor,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildLargePreviewCard({double? height}) {
    final hasImages = _scannedImagePaths.isNotEmpty;
    final currentImagePath = hasImages
        ? _scannedImagePaths[
            _currentPreviewIndex.clamp(0, _scannedImagePaths.length - 1)]
        : null;

    return Container(
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildSectionTitle('الصورة الكاملة', icon: Icons.image_outlined),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.88),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: hasImages
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: File(currentImagePath!).existsSync()
                              ? Image.file(
                                  File(currentImagePath),
                                  fit: BoxFit.contain,
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
                                      size: 40,
                                    ),
                                  ),
                                ),
                        ),
                        if (_hasMultiplePreviewImages)
                          Positioned(
                            right: 10,
                            child: _buildPreviewNavigationButton(
                              icon: Icons.chevron_right_rounded,
                              onTap: _goToPreviousPreviewImage,
                            ),
                          ),
                        if (_hasMultiplePreviewImages)
                          Positioned(
                            left: 10,
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
                            size: 70,
                            color: accentColor.withOpacity(0.75),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'ستظهر الصورة الكاملة هنا',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: softTextColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'بعد السحب من السكانر أو تعبئة الحقول من نتيجة البحث',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: softTextColor,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          if (hasImages)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.82),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: SizedBox(
                height: 95,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _scannedImagePaths.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final imagePath = _scannedImagePaths[index];
                    final imageFile = File(imagePath);
                    final isSelected = index == _currentPreviewIndex;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _currentPreviewIndex = index;
                        });
                      },
                      child: Container(
                        width: 90,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          gradient: isSelected ? _mainGradient : null,
                          color: isSelected ? null : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? accentColor : borderColor,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: imageFile.existsSync()
                              ? Image.file(
                                  imageFile,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: _headerGradient,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                Text(
                  'عدد الصفحات: ${_scannedImagePaths.length}',
                  style: TextStyle(
                    color: darkColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_hasMultiplePreviewImages) ...[
                  const SizedBox(height: 4),
                  Text(
                    'الصفحة ${_currentPreviewIndex + 1} من ${_scannedImagePaths.length}',
                    style: TextStyle(
                      color: softTextColor,
                      fontSize: 12,
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

  Widget _buildDocumentTypeSwitcher() {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTypeChip(
              title: 'ملف رئيسي',
              selected: !_isSubDocument,
              onTap: () {
                setState(() {
                  _isSubDocument = false;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildTypeChip(
              title: 'كتاب تابع',
              selected: _isSubDocument,
              onTap: () {
                setState(() {
                  _isSubDocument = true;
                  if (_documentNumberController.text.trim().isNotEmpty &&
                      _parentDocumentNumberController.text.trim().isEmpty) {
                    _parentDocumentNumberController.text =
                        _documentNumberController.text.trim();
                    _parentDocumentTitleController.text =
                        _documentTitleController.text.trim();
                  }

                  // إذا كان المستخدم فاتح ملفاً أصلياً وحوّل إلى كتاب تابع،
                  // نحافظ على تصنيف الأصل ليستخدمه التابع تلقائياً.
                  if (_savedDocument != null &&
                      _categories.contains(_savedDocument!.category)) {
                    _selectedCategory = _savedDocument!.category;
                  }
                });

                if (_parentDocumentOptions.isEmpty) {
                  _loadParentDocumentOptions();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip({
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          height: 46,
          decoration: BoxDecoration(
            gradient: selected ? _mainGradient : null,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: selected ? Colors.white : darkColor,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusDropdown() {
    const statuses = ['منجز', 'قيد الإنجاز', 'تم الاطلاع'];
    final safeSelectedStatus = statuses.contains(_selectedStatus)
        ? _selectedStatus
        : 'قيد الإنجاز';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeSelectedStatus,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
          style: TextStyle(
            color: darkColor,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
          items: statuses.map((status) {
            return DropdownMenuItem<String>(
              value: status,
              child: Text(
                status,
                textAlign: TextAlign.right,
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedStatus = value;
            });
          },
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _categories.contains(_selectedCategory) ? _selectedCategory : null,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
          hint: Text(
            _isSubDocument ? 'تصنيف الكتاب التابع' : 'تصنيف الملف',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: softTextColor.withOpacity(0.78),
              fontSize: 13.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          style: TextStyle(
            color: darkColor,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
          items: _categories.map((category) {
            return DropdownMenuItem<String>(
              value: category,
              child: Text(
                category,
                textAlign: TextAlign.right,
              ),
            );
          }).toList(),
          onChanged: (_isSubDocument && _selectedParentDocument != null)
              ? null
              : (value) {
                  setState(() {
                    _selectedCategory = value;

                    if (value != 'محاضر لجان تحقيقية') {
                      _selectedCommitteeFolderPath = null;
                    }
                  });
                },
        ),
      ),
    );
  }


  Widget _buildCommitteeFolderSelector() {
    if (_selectedCategory != 'محاضر لجان تحقيقية') {
      return const SizedBox.shrink();
    }

    final selectedName = _selectedCommitteeFolderPath == null
        ? ''
        : p.basename(_selectedCommitteeFolderPath!);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildOutlinedActionButton(
              onPressed: _pickCommitteeFolder,
              label: _selectedCommitteeFolderPath == null
                  ? 'اختيار / إنشاء فولدر رئيس اللجنة'
                  : 'تغيير فولدر رئيس اللجنة',
              icon: Icons.folder_open_rounded,
              height: 46,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF6FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    color: accentColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedCommitteeFolderPath == null
                          ? 'لم يتم اختيار فولدر رئيس اللجنة'
                          : selectedName,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _selectedCommitteeFolderPath == null
                            ? softTextColor
                            : darkColor,
                        fontSize: 13.2,
                        fontWeight: FontWeight.w700,
                      ),
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



  String _cleanArchiveTitle(String value) {
    return value
        .trim()
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _isYearFolderName(String name) {
    return RegExp(r'^\d{4}$').hasMatch(name.trim());
  }

  bool _isArchiveFolderSelectable(String folderPath) {
    final normalized = p.normalize(folderPath);
    final root = p.normalize(_archiveRootPath);
    final folderName = p.basename(normalized).trim();

    if (normalized.toLowerCase() == root.toLowerCase()) return false;
    if (folderName.toLowerCase() == 'original') return false;
    if (_isYearFolderName(folderName)) return false;
    if (_categories.contains(folderName)) return false;

    final hasLeadingNumber = RegExp(r'^\d+').hasMatch(folderName);
    final hasOriginalFolder = Directory(p.join(normalized, 'original')).existsSync();

    return hasLeadingNumber || hasOriginalFolder;
  }

  Map<String, String> _extractArchiveFolderInfo(String folderPath) {
    String normalizedPath = _resolveDocumentRootFolderPath(folderPath);
    if (normalizedPath.trim().isEmpty) {
      normalizedPath = folderPath;
    }

    final folderName = p.basename(normalizedPath).trim();
    final parts = folderName.split('_').where((part) => part.trim().isNotEmpty).toList();

    if (parts.isEmpty) {
      return {'number': '', 'title': ''};
    }

    final numberMatch = RegExp(r'^\d+').firstMatch(parts.first.trim());
    final number = numberMatch?.group(0) ?? parts.first.trim();

    int titleStartIndex = 1;
    if (parts.length >= 3 && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(parts[1].trim())) {
      titleStartIndex = 2;
    }

    final title = parts.length > titleStartIndex
        ? _cleanArchiveTitle(parts.skip(titleStartIndex).join(' '))
        : '';

    return {
      'number': number,
      'title': title,
    };
  }

  Future<List<Directory>> _loadArchiveChildFolders(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return [];

    final folders = await dir
        .list(followLinks: false)
        .where((entity) => entity is Directory)
        .cast<Directory>()
        .toList();

    folders.sort((a, b) {
      final aName = p.basename(a.path).toLowerCase();
      final bName = p.basename(b.path).toLowerCase();
      return aName.compareTo(bName);
    });

    return folders;
  }

  String _archiveRelativePath(String folderPath) {
    final normalizedRoot = p.normalize(_archiveRootPath);
    final normalizedPath = p.normalize(folderPath);

    if (normalizedPath.toLowerCase() == normalizedRoot.toLowerCase()) {
      return 'D:\\DocumentArchive';
    }

    if (normalizedPath.toLowerCase().startsWith(normalizedRoot.toLowerCase())) {
      final relative = normalizedPath.substring(normalizedRoot.length);
      final cleaned = relative.replaceFirst(RegExp(r'^[\\/]+'), '');
      return 'D:\\DocumentArchive${cleaned.isEmpty ? '' : '\\$cleaned'}';
    }

    return normalizedPath;
  }

  String? _extractCategoryFromArchivePath(String folderPath) {
    final normalizedPath = p.normalize(folderPath);

    for (final category in _categories) {
      final safeCategory = _safeFolderName(category).toLowerCase();
      final parts = p
          .split(normalizedPath)
          .map((part) => part.trim().toLowerCase())
          .toList();

      if (parts.contains(safeCategory) ||
          parts.contains(category.trim().toLowerCase())) {
        return category;
      }
    }

    return null;
  }

  void _selectParentFolderFromArchive(String folderPath) {
    final rootFolderPath = _resolveDocumentRootFolderPath(folderPath);
    final selectedPath = rootFolderPath.trim().isEmpty ? folderPath : rootFolderPath;
    final info = _extractArchiveFolderInfo(selectedPath);
    final number = info['number'] ?? '';
    final title = info['title'] ?? '';
    final category = _extractCategoryFromArchivePath(selectedPath);

    if (number.trim().isEmpty) {
      _showMessage('تعذر استخراج رقم الملف من اسم الفولدر', isError: true);
      return;
    }

    if (category == null || category.trim().isEmpty) {
      _showMessage(
        'تم اختيار الملف الأصلي، لكن تعذر تحديد تصنيفه من مسار الأرشيف',
        isError: true,
      );
      return;
    }

    final parentPreview = DocumentModel(
      id: null,
      documentNumber: number.trim(),
      documentDate: '',
      documentTitle: title.trim(),
      category: category,
      notes: '',
      status: 'قيد الإنجاز',
      reminderDate: null,
      reminderNote: null,
      folderPath: selectedPath,
      imagePaths: const [],
    );

    setState(() {
      _selectedParentDocument = parentPreview;
      _parentDocumentNumberController.text = number.trim();
      _parentDocumentTitleController.text = title.trim();
      _selectedCategory = category;
      _selectedCommitteeFolderPath = null;
    });

    _showMessage('تم اختيار الملف الأصلي من الأرشيف وأخذ تصنيفه تلقائياً');
  }

  Future<void> _showArchiveParentFolderPicker() async {
    final rootDir = Directory(_archiveRootPath);
    if (!await rootDir.exists()) {
      _showMessage('مجلد الأرشيف غير موجود: $_archiveRootPath', isError: true);
      return;
    }

    if (!mounted) return;

    String currentPath = _archiveRootPath;
    String searchText = '';
    final searchController = TextEditingController();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canGoBack = p.normalize(currentPath).toLowerCase() !=
                p.normalize(_archiveRootPath).toLowerCase();
            final canSelectCurrent = _isArchiveFolderSelectable(currentPath);

            return Directionality(
              textDirection: ui.TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: BorderSide(color: borderColor),
                ),
                titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                title: Row(
                  children: [
                    Icon(Icons.folder_open_rounded, color: accentColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'اختيار الملف الأصلي من الأرشيف',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: darkColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 720,
                  height: 520,
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: _headerGradient,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.account_tree_outlined, color: accentColor, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _archiveRelativePath(currentPath),
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: darkColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          SizedBox(
                            width: 110,
                            height: 44,
                            child: OutlinedButton.icon(
                              onPressed: canGoBack
                                  ? () {
                                      setDialogState(() {
                                        currentPath = p.dirname(currentPath);
                                        searchText = '';
                                        searchController.clear();
                                      });
                                    }
                                  : null,
                              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                              label: const Text('رجوع'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: darkColor,
                                side: BorderSide(color: borderColor),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: searchController,
                              textAlign: TextAlign.right,
                              onChanged: (value) {
                                setDialogState(() {
                                  searchText = value.trim().toLowerCase();
                                });
                              },
                              decoration: InputDecoration(
                                hintText: 'بحث داخل الفولدر الحالي...',
                                prefixIcon: Icon(Icons.search_rounded, color: accentColor),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.92),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: accentColor, width: 1.4),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: FutureBuilder<List<Directory>>(
                          future: _loadArchiveChildFolders(currentPath),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(color: accentColor),
                                    const SizedBox(height: 10),
                                    Text(
                                      'جاري تحميل الفولدرات...',
                                      style: TextStyle(color: softTextColor, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final folders = (snapshot.data ?? []).where((folder) {
                              if (searchText.isEmpty) return true;
                              return p.basename(folder.path).toLowerCase().contains(searchText);
                            }).toList();

                            if (folders.isEmpty) {
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.86),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Center(
                                  child: Text(
                                    'لا توجد فولدرات داخل هذا المسار',
                                    style: TextStyle(
                                      color: softTextColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              );
                            }

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.88),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: borderColor),
                              ),
                              child: ListView.separated(
                                itemCount: folders.length,
                                separatorBuilder: (_, _) => Divider(height: 1, color: borderColor.withOpacity(0.6)),
                                itemBuilder: (context, index) {
                                  final folder = folders[index];
                                  final folderName = p.basename(folder.path);
                                  final selectable = _isArchiveFolderSelectable(folder.path);
                                  final hasOriginal = Directory(p.join(folder.path, 'original')).existsSync();

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        setDialogState(() {
                                          currentPath = folder.path;
                                          searchText = '';
                                          searchController.clear();
                                        });
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                        child: Row(
                                          children: [
                                            Icon(
                                              hasOriginal ? Icons.snippet_folder_outlined : Icons.folder_outlined,
                                              color: selectable ? accentColor : softTextColor,
                                              size: 22,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    folderName,
                                                    textAlign: TextAlign.right,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: darkColor,
                                                      fontSize: 13.3,
                                                      fontWeight: FontWeight.w800,
                                                    ),
                                                  ),
                                                  if (selectable)
                                                    Text(
                                                      'يمكن اختياره كملف أصلي',
                                                      textAlign: TextAlign.right,
                                                      style: TextStyle(
                                                        color: softTextColor,
                                                        fontSize: 11.5,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (selectable)
                                              TextButton.icon(
                                                onPressed: () {
                                                  _selectParentFolderFromArchive(folder.path);
                                                  Navigator.pop(dialogContext);
                                                },
                                                icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
                                                label: const Text('اختيار'),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: accentColor,
                                                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                                                ),
                                              ),
                                            Icon(Icons.chevron_left_rounded, color: softTextColor, size: 22),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton.icon(
                    onPressed: canSelectCurrent
                        ? () {
                            _selectParentFolderFromArchive(currentPath);
                            Navigator.pop(dialogContext);
                          }
                        : null,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('اختيار هذا الفولدر'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
  }

  List<DocumentModel> _filteredParentDocumentOptions() {
    final query = _parentDocumentNumberController.text.trim().toLowerCase();

    if (query.isEmpty) {
      return _parentDocumentOptions.take(6).toList();
    }

    final filtered = _parentDocumentOptions.where((doc) {
      final number = doc.documentNumber.trim().toLowerCase();
      final title = doc.documentTitle.trim().toLowerCase();
      final date = doc.documentDate.trim().toLowerCase();

      return number.contains(query) ||
          title.contains(query) ||
          date.contains(query);
    }).toList();

    return filtered.take(8).toList();
  }

  void _selectParentDocument(DocumentModel doc) {
    setState(() {
      _selectedParentDocument = doc;
      _parentDocumentNumberController.text = doc.documentNumber;
      _parentDocumentTitleController.text = doc.documentTitle;

      // عند اختيار ملف أصلي للكتاب التابع نأخذ تصنيف الأصل تلقائياً.
      if (_isSubDocument && _categories.contains(doc.category)) {
        _selectedCategory = doc.category;
        _selectedCommitteeFolderPath = null;
      }
    });
  }

 Widget _buildParentDocumentSuggestions() {
  final options = _filteredParentDocumentOptions();
  final typedNumber = _parentDocumentNumberController.text.trim();

  if (_isLoadingParentDocuments) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'جاري البحث عن الملفات الأصلية...',
            style: TextStyle(
              color: softTextColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  if (typedNumber.isNotEmpty && options.isEmpty) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        'لا توجد نتائج لهذا الرقم. يمكنك إدخال اسم الملف الأصلي يدويًا.',
        textAlign: TextAlign.right,
        style: TextStyle(
          color: softTextColor,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  if (options.isEmpty) return const SizedBox.shrink();

  return Container(
    width: double.infinity,
    constraints: const BoxConstraints(maxHeight: 170),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.95),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(
          color: accentColor.withOpacity(0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: options.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: borderColor.withOpacity(0.65),
      ),
      itemBuilder: (context, index) {
        final doc = options[index];

        final isSelected = _selectedParentDocument != null &&
            _selectedParentDocument!.documentNumber == doc.documentNumber &&
            _selectedParentDocument!.documentDate == doc.documentDate &&
            _selectedParentDocument!.documentTitle == doc.documentTitle;

        return Material(
          color: isSelected
              ? accentLightColor.withOpacity(0.16)
              : Colors.transparent,
          child: InkWell(
            onTap: () => _selectParentDocument(doc),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.description_outlined,
                    color: isSelected ? accentColor : softTextColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${doc.documentNumber} - ${doc.documentDate} - ${doc.documentTitle}',
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: darkColor,
                        fontSize: 13.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

  Widget _buildParentDocumentDropdown() {
    return _buildParentDocumentSuggestions();
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(
              'بيانات الملف',
              icon: Icons.folder_copy_outlined,
            ),
            const SizedBox(height: 6),
            Text(
              'اسحب الملف من جهاز السكانر ثم أدخل البيانات الأساسية.',
              style: TextStyle(
                color: softTextColor,
                height: 1.4,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 10),
            _buildDocumentTypeSwitcher(),
            const SizedBox(height: 10),
            _buildScannerDropdown(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    onPressed: _isScanning ? null : _startScanAndImport,
                    label: _isScanning ? 'جاري الانتظار...' : 'سحب من السكانر',
                    icon: Icons.document_scanner_outlined,
                    loading: _isScanning,
                    height: 46,
                  ),
                ),
                const SizedBox(width: 8),
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
                    height: 46,
                  ),
                ),
              ],
            ),
            if (_scannedImagePaths.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildScannedImagesPreview(),
            ],
            const SizedBox(height: 10),
            if (_isSubDocument) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      label: 'رقم الملف الأصلي',
                      icon: Icons.account_tree_outlined,
                      controller: _parentDocumentNumberController,
                      hint: 'اكتبي رقم الملف الأصلي يدويًا',
                      onChanged: (value) {
                        setState(() {
                          _selectedParentDocument = null;
                        });

                        if (_parentDocumentOptions.isEmpty &&
                            value.trim().isNotEmpty &&
                            !_isLoadingParentDocuments) {
                          _loadParentDocumentOptions();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    height: 46,
                    child: IconButton(
                      tooltip: 'تحديث قائمة الملفات الأصلية',
                      onPressed: _isLoadingParentDocuments
                          ? null
                          : () => _loadParentDocumentOptions(
                                showMessage: true,
                              ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.9),
                        foregroundColor: accentColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: borderColor),
                        ),
                      ),
                      icon: _isLoadingParentDocuments
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTextField(
                      label: 'رقم الكتاب التابع',
                      icon: Icons.subdirectory_arrow_left_outlined,
                      controller: _subDocumentNumberController,
                      hint: 'مثال: 55',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildParentDocumentDropdown(),
              const SizedBox(height: 8),
              _buildOutlinedActionButton(
                onPressed: _showArchiveParentFolderPicker,
                label: 'اختيار الملف الأصلي من الأرشيف',
                icon: Icons.folder_open_outlined,
                height: 46,
              ),
              const SizedBox(height: 8),
              _buildTextField(
                label: 'اسم الملف الأصلي',
                icon: Icons.drive_file_rename_outline,
                controller: _parentDocumentTitleController,
                hint: 'يظهر تلقائيًا بعد اختيار النتيجة، ويمكن إدخاله يدويًا عند عدم وجود الملف',
                readOnly: false,
              ),
              const SizedBox(height: 8),
            ] else ...[
              _buildTextField(
                label: 'رقم الملف',
                icon: Icons.numbers_rounded,
                controller: _documentNumberController,
                hint: '12345',
              ),
              const SizedBox(height: 8),
            ],
            _buildCategoryDropdown(),
            const SizedBox(height: 8),
            if (_selectedCategory == 'محاضر لجان تحقيقية') ...[
              _buildCommitteeFolderSelector(),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    label: _isSubDocument ? 'تأريخ الكتاب' : 'تأريخ الملف',
                    icon: Icons.calendar_month_outlined,
                    controller: _documentDateController,
                    hint: 'اختر التاريخ',
                    readOnly: true,
                    onTap: _pickDate,
                  ),
                ),
                if (!_isSubDocument) ...[
                  const SizedBox(width: 8),
                  Expanded(child: _buildStatusDropdown()),
                ],
              ],
            ),
            const SizedBox(height: 8),
            _buildTextField(
              label: _isSubDocument ? 'اسم الكتاب التابع' : 'اسم الملف',
              icon: Icons.description_outlined,
              controller: _documentTitleController,
              hint: _isSubDocument ? 'اكتب اسم الكتاب التابع' : 'اكتب اسم الملف',
            ),
            const SizedBox(height: 8),
            _buildTextField(
              label: 'ملاحظات',
              icon: Icons.sticky_note_2_outlined,
              controller: _notesController,
              hint: 'أدخل أي ملاحظات إضافية',
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    label: 'تاريخ التذكير',
                    icon: Icons.alarm_outlined,
                    controller: _reminderDateController,
                    hint: 'اختر تاريخ التذكير',
                    readOnly: true,
                    onTap: _pickReminderDate,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTextField(
                    label: 'ملاحظة التذكير',
                    icon: Icons.notification_important_outlined,
                    controller: _reminderNoteController,
                    hint: 'مثال: متابعة الكتاب',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSaveBar() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _cardDecoration(),
      child: _buildActionButton(
        onPressed: _isLoading ? null : _saveDocument,
        label: _isLoading ? 'جاري الحفظ...' : 'حفظ',
        icon: Icons.save_outlined,
        dark: true,
        loading: _isLoading,
        height: 50,
      ),
    );
  }

  Future<void> _openSearchScreen() async {
    final result = await Navigator.push<DocumentModel>(
      context,
      MaterialPageRoute(
        builder: (_) => const DocumentSearchScreen(),
      ),
    );

    if (result != null) {
      setState(() {
        _savedDocument = result;
      });
      await _fillFormFromDocument(result);
    }
  }

  Widget _buildSearchNavigationButton() {
    return _buildActionButton(
      onPressed: _openSearchScreen,
      label: 'البحث عن ملف',
      icon: Icons.search_rounded,
    );
  }

  Widget _buildRightColumn({required bool scrollableInside}) {
    final content = Column(
      children: [
        _buildTopHeaderCompact(),
        const SizedBox(height: 12),
        _buildActionButton(
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const DocumentsByStatusScreen(),
              ),
            );

            if (result != null) {
              await _fillFormFromDocument(
                _documentFromJson(result),
              );
            }
          },
          label: 'عرض الملفات',
          icon: Icons.folder_open,
        ),
        const SizedBox(height: 12),
        _buildSearchNavigationButton(),
        const SizedBox(height: 12),
        _buildInfoCard(),
        const SizedBox(height: 10),
        _buildBottomSaveBar(),
      ],
    );

    if (!scrollableInside) return content;

    return SingleChildScrollView(
      child: content,
    );
  }

  Widget _buildWideLayout(BoxConstraints constraints) {
    final availableHeight = constraints.maxHeight > 0
        ? constraints.maxHeight
        : MediaQuery.of(context).size.height;

    return SizedBox(
      height: availableHeight,
      child: Directionality(
        textDirection: ui.TextDirection.ltr,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 7,
              child: _buildLargePreviewCard(),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 5,
              child: _buildRightColumn(scrollableInside: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      children: [
        _buildTopHeaderCompact(),
        const SizedBox(height: 12),
        _buildActionButton(
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const DocumentsByStatusScreen(),
              ),
            );

            if (result != null) {
              await _fillFormFromDocument(
                _documentFromJson(result),
              );
            }
          },
          label: 'عرض الملفات',
          icon: Icons.folder_open,
        ),
        const SizedBox(height: 12),
        _buildSearchNavigationButton(),
        const SizedBox(height: 12),
        _buildInfoCard(),
        const SizedBox(height: 12),
        SizedBox(
          height: 520,
          child: _buildLargePreviewCard(),
        ),
        const SizedBox(height: 10),
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
    _parentDocumentNumberController.dispose();
    _parentDocumentTitleController.dispose();
    _subDocumentNumberController.dispose();
    _reminderDateController.dispose();
    _reminderNoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 1100;

              return Container(
                width: double.infinity,
                height: double.infinity,
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFF8FAFC),
                      Color(0xFFEAF2FF),
                    ],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: isWide
                    ? _buildWideLayout(constraints)
                    : SingleChildScrollView(
                        child: _buildNarrowLayout(),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}